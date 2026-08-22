## zlib bindings and the two things this app needs from them: raw deflate
## for save state sections, and a PNG encoder for their thumbnails.
##
## The system zlib is used rather than a Nim package (zippy, nimPNG) so the
## save state format costs no new dependency. macOS ships libz with the
## SDK; Linux has it everywhere; a Windows build will have to supply it,
## which is the same requirement the original core has (`USE_ZLIB`).
##
## PNG is written here, not pulled in from a library, because PNG's IDAT
## payload *is* a zlib stream and its chunk checksum *is* zlib's crc32 -
## with libz already linked, the encoder below is the whole format.

when not defined(windows):
  {.passL: "-lz".}
# Windows has no system zlib. scripts/fetch_zlib_windows.sh vendors the
# upstream source and scripts/build_core.sh compiles it straight into
# build/libbubix1core.a on that platform, so the objects arrive through the
# core's own -l flag in build_nim_app.sh rather than a system -lz here; only
# the header search path (passC, also set there) is still needed.

type
  ULong = culong

proc zlibCompressBound(sourceLen: ULong): ULong
  {.importc: "compressBound", header: "zlib.h".}
proc zlibCompress2(dest: ptr uint8, destLen: ptr ULong,
                   source: ptr uint8, sourceLen: ULong, level: cint): cint
  {.importc: "compress2", header: "zlib.h".}
proc zlibUncompress(dest: ptr uint8, destLen: ptr ULong,
                    source: ptr uint8, sourceLen: ULong): cint
  {.importc: "uncompress", header: "zlib.h".}
proc zlibCrc32(crc: ULong, buf: ptr uint8, len: cuint): ULong
  {.importc: "crc32", header: "zlib.h".}

const ZOk = 0.cint

proc crc32*(data: openArray[byte]): uint32 =
  ## Also used for the disk image and IPL ROM fingerprints in a save
  ## state's metadata, not just for PNG chunks.
  if data.len == 0:
    return 0
  zlibCrc32(0, cast[ptr uint8](unsafeAddr data[0]), data.len.cuint).uint32

proc crc32*(data: string): uint32 =
  crc32(data.toOpenArrayByte(0, data.high))

proc compress*(data: openArray[byte], level = 6): seq[byte] =
  ## zlib-wrapped deflate. Returns an empty seq only for empty input;
  ## every failure mode of compress2 with a compressBound-sized output
  ## buffer is a programming error, so it raises instead.
  if data.len == 0:
    return @[]
  var bound = zlibCompressBound(data.len.ULong)
  result = newSeq[byte](bound.int)
  if zlibCompress2(addr result[0], addr bound,
                   cast[ptr uint8](unsafeAddr data[0]), data.len.ULong,
                   level.cint) != ZOk:
    raise newException(IOError, "zlib compress2 failed")
  result.setLen bound.int

proc uncompress*(data: openArray[byte], rawLen: int): seq[byte] =
  ## Inverse of `compress`. `rawLen` comes from the container's section
  ## table, so a corrupt or lying entry surfaces here as an IOError rather
  ## than as a short buffer handed to the emulator.
  if rawLen == 0:
    return @[]
  var outLen = rawLen.ULong
  result = newSeq[byte](rawLen)
  if data.len == 0 or
     zlibUncompress(addr result[0], addr outLen,
                    cast[ptr uint8](unsafeAddr data[0]), data.len.ULong) != ZOk or
     outLen.int != rawLen:
    raise newException(IOError, "zlib uncompress failed")

proc addBe32(s: var seq[byte], v: uint32) =
  s.add byte(v shr 24)
  s.add byte(v shr 16)
  s.add byte(v shr 8)
  s.add byte(v)

proc addChunk(s: var seq[byte], tag: string, payload: openArray[byte]) =
  ## One PNG chunk: length, type, payload, CRC32 over type+payload.
  s.addBe32 payload.len.uint32
  var body = newSeq[byte](4 + payload.len)
  for i in 0 .. 3:
    body[i] = tag[i].byte
  for i, b in payload:
    body[4 + i] = b
  s.add body
  s.addBe32 crc32(body)

proc encodePng*(width, height: int, rgb: openArray[byte]): seq[byte] =
  ## 8-bit truecolour PNG from tightly packed RGB triples. Every scanline
  ## gets filter type 0 (None): the images this writes are small emulator
  ## screenshots, where the filters that would help cost more code than
  ## the bytes they save.
  doAssert rgb.len == width * height * 3
  var raw = newSeq[byte](height * (1 + width * 3))
  var dst = 0
  for y in 0 ..< height:
    raw[dst] = 0
    inc dst
    let src = y * width * 3
    for i in 0 ..< width * 3:
      raw[dst + i] = rgb[src + i]
    dst += width * 3

  result = @[byte 0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
  var ihdr: seq[byte]
  ihdr.addBe32 width.uint32
  ihdr.addBe32 height.uint32
  ihdr.add [byte 8,  # bit depth
            2,       # colour type: truecolour
            0, 0, 0] # deflate, adaptive filtering, no interlace
  result.addChunk("IHDR", ihdr)
  result.addChunk("IDAT", compress(raw))
  result.addChunk("IEND", [])
