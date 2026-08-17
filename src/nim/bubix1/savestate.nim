## The `.bx1s` save state container.
##
## The emulation core serializes its devices into one opaque byte stream
## (`bx1_vm_state_save`); everything that makes that stream usable - what
## machine and ROM it belongs to, which disks were mounted, when it was
## saved, what it looked like - lives here, in a section-based file this
## layer owns end to end. Deliberately NOT compatible with the original
## eX1turboZ `.sta`; see docs/dev/SaveState.md for the full specification
## and for what the original format got wrong.
##
## Layout: a 64 byte header, a table of 16 byte section descriptors, then
## the section payloads. Sections are found by tag, so unknown ones are
## skipped and adding one later breaks nothing.

import std/[json, options, os, streams, times, unicode]
import deflate
import ./i18n

const
  Magic* = 0x53315842'u32       ## "BX1S", little endian
  FormatVersion* = 1'u16        ## container layout, not the core's state
  CompressNone = 0'u16
  CompressDeflate = 1'u16
  HeaderSize = 64
  SectionEntrySize = 16
  ProducerLen = 32

  TagVm = 0x54534d56'u32        ## "VMST"
  TagMeta = 0x4154454d'u32      ## "META"
  TagThumb = 0x424d4854'u32     ## "THMB"

type
  DriveState* = object
    ## One drive as it stood when the state was written. `source` is what
    ## the user opened (an archive or playlist, possibly), `image` the
    ## concrete file that ended up in the drive.
    ##
    ## The title's other disks are deliberately not listed: re-resolving
    ## `source` through the same archive/diskset pipeline that produced
    ## them regenerates the identical list, labels and grouping included,
    ## so storing a copy would only create something that can go stale.
    occupied*: bool
    source*, image*, label*: string
    bank*: int
    imageSize*: int
    imageCrc32*: uint32
    writeProtected*: bool

  ReinitConfig* = object
    ## Settings the original's EMU::load_state() reacts to by rebuilding
    ## the VM. This layer cannot rebuild it, so these are compared and a
    ## mismatch refuses the load (see docs/dev/SaveState.md section 6).
    soundType*, printerType*, serialType*: int
    soundFrequency*, soundLatency*: int

  RuntimeConfig* = object
    ## Settings the devices read from the global config at run time, so
    ## they have to be applied *before* the VM blob is handed over.
    monitorType*, driveType*: int
    correctDiskTiming*, ignoreDiskCrc*: seq[bool]

  StateMeta* = object
    savedAt*: int64
    producer*: string
    coreStateId*: uint32
    machine*: string
    iplCrc32*: uint32
    reinit*: ReinitConfig
    runtime*: RuntimeConfig
    drives*: seq[DriveState]
    title*: string
    cpuPower*: int
    fullSpeed*: bool

  StateInfo* = object
    ## What a slot listing needs: everything but the multi-megabyte blob.
    meta*: StateMeta
    hasThumbnail*: bool

  Section = object
    tag: uint32
    offset, stored, raw: int

# ----------------------------------------------------------------------
# Metadata as JSON
# ----------------------------------------------------------------------

proc escapeBytes(s: string): string =
  ## Widens raw bytes to the code points U+0000-U+00FF so they survive a
  ## trip through JSON.
  ##
  ## A D88 disk name is whatever bytes the image was written with -
  ## Shift-JIS in practice - and Nim's json module passes such bytes
  ## through untouched, which would leave the META section invalid UTF-8
  ## and unreadable by anything but this app. Note this only widens: the
  ## value stays the original byte sequence, still undecoded, because
  ## nativemenu.m is the one place in this app that turns D88 names into
  ## text (see diskset.nim).
  for c in s:
    result.add Rune(c.ord).toUTF8

proc unescapeBytes(s: string): string =
  ## Inverse of `escapeBytes`. A code point above U+00FF cannot have come
  ## from it, so it is dropped rather than truncated into a stray byte.
  for r in s.runes:
    if r.int32 <= 0xff:
      result.add chr(r.int32)

proc toBytes(s: string): seq[byte] =
  result = newSeq[byte](s.len)
  for i, c in s:
    result[i] = c.byte

proc toStr(b: seq[byte]): string =
  result = newString(b.len)
  for i, v in b:
    result[i] = v.char

proc toJson(m: StateMeta): JsonNode =
  result = %*{
    "format": FormatVersion.int,
    "saved_at": m.savedAt,
    "producer": m.producer,
    "core_state_id": m.coreStateId.int,
    "machine": m.machine,
    "ipl_crc32": m.iplCrc32.int64,
    "reinit_config": {
      "sound_type": m.reinit.soundType,
      "printer_type": m.reinit.printerType,
      "serial_type": m.reinit.serialType,
      "sound_frequency": m.reinit.soundFrequency,
      "sound_latency": m.reinit.soundLatency,
    },
    "runtime_config": {
      "monitor_type": m.runtime.monitorType,
      "drive_type": m.runtime.driveType,
      "correct_disk_timing": m.runtime.correctDiskTiming,
      "ignore_disk_crc": m.runtime.ignoreDiskCrc,
    },
    "drives": newJArray(),
    "title": m.title,
    "cpu_power": m.cpuPower,
    "full_speed": m.fullSpeed,
  }
  for d in m.drives:
    result["drives"].add(
      if d.occupied:
        %*{"source": d.source, "image": d.image, "bank": d.bank,
           "label": escapeBytes(d.label), "image_size": d.imageSize,
           "image_crc32": d.imageCrc32.int64,
           "write_protected": d.writeProtected}
      else:
        %*{"source": newJNull()})

proc str(n: JsonNode, key: string, fallback = ""): string =
  if n.hasKey(key) and n[key].kind == JString: n[key].getStr else: fallback

proc num(n: JsonNode, key: string, fallback = 0): int =
  if n.hasKey(key) and n[key].kind == JInt: n[key].getInt else: fallback

proc u32(n: JsonNode, key: string): uint32 =
  if n.hasKey(key) and n[key].kind == JInt: cast[uint32](n[key].getInt) else: 0

proc flag(n: JsonNode, key: string, fallback = false): bool =
  if n.hasKey(key) and n[key].kind == JBool: n[key].getBool else: fallback

proc boolSeq(n: JsonNode, key: string): seq[bool] =
  if n.hasKey(key) and n[key].kind == JArray:
    for v in n[key]:
      result.add(v.kind == JBool and v.getBool)

proc fromJson(n: JsonNode): StateMeta =
  ## Tolerant by design: a section written by a newer build may carry keys
  ## this one does not know, and one written by an older build may be
  ## missing keys added since. Neither is a reason to reject a state - the
  ## checks that *do* reject (core state id, machine, ROM) are made by the
  ## caller against the fields below, which are always present in practice.
  result.savedAt = (if n.hasKey("saved_at"): n["saved_at"].getBiggestInt else: 0)
  result.producer = n.str("producer")
  result.coreStateId = n.u32("core_state_id")
  result.machine = n.str("machine")
  result.iplCrc32 = n.u32("ipl_crc32")
  result.title = n.str("title")
  result.cpuPower = n.num("cpu_power")
  result.fullSpeed = n.flag("full_speed")
  if n.hasKey("reinit_config"):
    let r = n["reinit_config"]
    result.reinit = ReinitConfig(
      soundType: r.num("sound_type"), printerType: r.num("printer_type"),
      serialType: r.num("serial_type"),
      soundFrequency: r.num("sound_frequency"),
      soundLatency: r.num("sound_latency"))
  if n.hasKey("runtime_config"):
    let r = n["runtime_config"]
    result.runtime = RuntimeConfig(
      monitorType: r.num("monitor_type"), driveType: r.num("drive_type"),
      correctDiskTiming: r.boolSeq("correct_disk_timing"),
      ignoreDiskCrc: r.boolSeq("ignore_disk_crc"))
  if n.hasKey("drives"):
    for d in n["drives"]:
      if d.kind != JObject or not d.hasKey("source") or d["source"].kind != JString:
        result.drives.add DriveState(occupied: false)
      else:
        result.drives.add DriveState(
          occupied: true, source: d.str("source"), image: d.str("image"),
          label: unescapeBytes(d.str("label")), bank: d.num("bank"),
          imageSize: d.num("image_size"), imageCrc32: d.u32("image_crc32"),
          writeProtected: d.flag("write_protected"))

# ----------------------------------------------------------------------
# Container
# ----------------------------------------------------------------------

type
  PendingSection = object
    tag: uint32
    payload: seq[byte]
    rawLen, offset: int

proc save*(path, vmBlobPath: string, meta: StateMeta, thumbnail: seq[byte] = @[]) =
  ## Wraps a blob written by `bx1_vm_state_save` into a `.bx1s` file.
  ##
  ## Written to a temporary file and moved into place, so a crash midway
  ## cannot leave a half-written slot where a working one used to be.
  let blob = readFile(vmBlobPath).toBytes()
  let metaBytes = ($meta.toJson()).toBytes()

  var sections = @[
    PendingSection(tag: TagVm, payload: deflate.compress(blob), rawLen: blob.len),
    PendingSection(tag: TagMeta, payload: metaBytes, rawLen: metaBytes.len)]
  if thumbnail.len > 0:
    sections.add PendingSection(
      tag: TagThumb, payload: thumbnail, rawLen: thumbnail.len)

  var offset = HeaderSize + SectionEntrySize * sections.len
  var thumbOffset = 0
  for sec in sections.mitems:
    sec.offset = offset
    if sec.tag == TagThumb:
      thumbOffset = offset
    offset += sec.payload.len

  let tmp = path & ".tmp"
  var s = newFileStream(tmp, fmWrite)
  if s == nil:
    raise newException(IOError, trf(msgStateCannotWrite, tmp))
  try:
    s.write Magic
    s.write FormatVersion
    s.write CompressDeflate
    s.write meta.savedAt
    # Fixed width and NUL-padded, so the header stays seekable by offset.
    var producer: array[ProducerLen, char]
    for i in 0 ..< min(meta.producer.len, ProducerLen):
      producer[i] = meta.producer[i]
    s.writeData addr producer[0], ProducerLen
    s.write meta.coreStateId
    # The thumbnail is repeated in the header so a reader that wants
    # nothing else (a future Quick Look extension) can seek to it having
    # read only these 64 bytes. It is a normal section as well.
    s.write thumbOffset.uint32
    s.write thumbnail.len.uint32
    s.write sections.len.uint32
    for sec in sections:
      s.write sec.tag
      s.write sec.offset.uint32
      s.write sec.payload.len.uint32
      s.write sec.rawLen.uint32
    for sec in sections:
      if sec.payload.len > 0:
        s.writeData unsafeAddr sec.payload[0], sec.payload.len
  finally:
    s.close()
  moveFile(tmp, path)

proc readSections(s: Stream, path: string): seq[Section] =
  ## Parses and validates header and section table. Raises IOError with a
  ## message fit to show the user - every rejection here means the file is
  ## not one of ours, or not one this build understands.
  if s.readUint32() != Magic:
    raise newException(IOError, trf(msgStateNotOurs, path.extractFilename))
  let version = s.readUint16()
  if version > FormatVersion:
    raise newException(IOError, tr(msgStateNewerVersion))
  let compression = s.readUint16()
  if compression != CompressNone and compression != CompressDeflate:
    raise newException(IOError, tr(msgStateUnknownCompression))
  s.setPosition 0x3c
  let count = s.readUint32().int
  if count <= 0 or count > 64:
    raise newException(IOError, tr(msgStateDamagedTable))
  s.setPosition HeaderSize
  for _ in 0 ..< count:
    var sec: Section
    sec.tag = s.readUint32()
    sec.offset = s.readUint32().int
    sec.stored = s.readUint32().int
    sec.raw = s.readUint32().int
    result.add sec

proc find(sections: seq[Section], tag: uint32): Option[Section] =
  for sec in sections:
    if sec.tag == tag:
      return some(sec)
  none(Section)

proc payload(s: Stream, sec: Section): seq[byte] =
  s.setPosition sec.offset
  var stored = newSeq[byte](sec.stored)
  if sec.stored > 0 and s.readData(addr stored[0], sec.stored) != sec.stored:
    raise newException(IOError, tr(msgStateTruncated))
  if sec.stored == sec.raw: stored else: deflate.uncompress(stored, sec.raw)

proc readInfo*(path: string): StateInfo =
  ## Header and metadata only - the VM blob is never touched, so this is
  ## cheap enough to call for every slot when a menu opens.
  var s = newFileStream(path, fmRead)
  if s == nil:
    raise newException(IOError, trf(msgStateCannotRead, path))
  try:
    let sections = readSections(s, path)
    let meta = sections.find(TagMeta)
    if meta.isNone:
      raise newException(IOError, tr(msgStateNoMetadata))
    result.meta = fromJson(parseJson(toStr(s.payload(meta.get))))
    result.hasThumbnail = sections.find(TagThumb).isSome
  finally:
    s.close()

proc extractVm*(path, destPath: string) =
  ## Writes the decompressed VM blob where `bx1_vm_state_load` can read it.
  var s = newFileStream(path, fmRead)
  if s == nil:
    raise newException(IOError, trf(msgStateCannotRead, path))
  try:
    let vm = readSections(s, path).find(TagVm)
    if vm.isNone:
      raise newException(IOError, tr(msgStateNoMachineState))
    writeFile(destPath, toStr(s.payload(vm.get)))
  finally:
    s.close()

proc readThumbnail*(path: string): seq[byte] =
  ## The stored PNG, or an empty seq when the state carries none.
  var s = newFileStream(path, fmRead)
  if s == nil:
    return @[]
  try:
    let thumb = readSections(s, path).find(TagThumb)
    if thumb.isSome:
      result = s.payload(thumb.get)
  finally:
    s.close()

proc describe*(info: StateInfo): string =
  ## One-line caption for the quick save: when it was taken and what was in
  ## the drives, in Bubilator88's `quickSaveInfo` shape. Both the date
  ## pattern and the way the two halves are joined come from the catalog:
  ## neither is the same in every language.
  let stamp = info.meta.savedAt.fromUnix().local().format(tr(msgStateDateFormat))
  result =
    if info.meta.title.len > 0: trf(msgStateCaption, stamp, info.meta.title)
    else: stamp
