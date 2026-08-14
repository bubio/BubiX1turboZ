## The flat list of disks behind one mount request.
##
## `archive.resolveMedia` answers "which image files did the user hand us",
## which is one level too coarse: a single `.d88` can hold a whole multi-disk
## game, and a 3-disk title can arrive as one such file, as three files in a
## `.7z`, or as an `.m3u` naming three files. This module flattens all three
## shapes into the same `(path, bank)` sequence, so the drive menu can offer
## every disk of a title regardless of how it was packaged, and remembers
## which file each disk came from so the menu can group them under it.
##
## Bubilator88 (`EmulatorViewModel+Disk.swift`), whose disk handling this
## port follows, deliberately does NOT flatten playlists - its write-back
## writes a file-local image index back into the source URL, so an index
## spanning several files would address a bank that does not exist there.
## That constraint has no equivalent here: `bx1_open_floppy` always takes a
## `(path, bank)` pair that is real by construction, so playlists are
## flattened like everything else and the third disk of a 3-disk set stays
## reachable. See DevelopmentPlan phase 7.6.

import std/[os, strutils]
import core

const
  MaxBanks* = 64
    ## Matches MAX_D88_BANKS (src/core/emu.h), the most disks the core will
    ## track for one image, and the number of fixed menu slots per drive.

type
  DiskEntry* = object
    ## One mountable disk: everything `bx1_open_floppy` needs plus what the
    ## menu and the picker show for it.
    path*: string   ## concrete image file on disk
    bank*: int      ## D88 bank index within `path`
    label*: string  ## menu title; raw Shift-JIS bytes when the image had a name
    mediaType*: int ## 0 = 2D, 1 = 2DD, 2 = 2HD, 3 = 1.44M, -1 = unknown
    writeProtected*: bool

  DiskGroup* = object
    ## The run of entries that came out of one file, so a set spanning
    ## several files can be shown under per-file captions.
    name*: string
    start*, count*: int

  DiskSet* = object
    entries*: seq[DiskEntry]
    groups*: seq[DiskGroup]

proc mediaLabel*(mediaType: int): string =
  ## Short name for the picker's type column. An image whose header says
  ## nothing useful gets no label rather than a misleading guess.
  case mediaType
  of 0: "2D"
  of 1: "2DD"
  of 2: "2HD"
  of 3: "1.44M"
  else: ""

proc bankName(bank: Bx1D88Bank): string =
  ## The D88 header's 17 name bytes as a Nim string. Kept in the image's own
  ## encoding (Shift-JIS in practice); nativemenu.m decodes it on the way to
  ## AppKit, so it is never decoded twice or in two places.
  for c in bank.name:
    if c == '\0':
      break
    result.add c
  result = result.strip()

proc addFile(s: var DiskSet, path: string) =
  ## Appends every disk in one image file as its own group. A file the core
  ## cannot read contributes nothing, so a broken entry in a playlist does
  ## not shift the disks after it.
  var banks: array[MaxBanks, Bx1D88Bank]
  let count = bx1ScanD88Banks(path.cstring, MaxBanks.cint, addr banks[0])
  if count <= 0:
    return
  let fileName = path.extractFilename().changeFileExt("")
  s.groups.add DiskGroup(name: fileName, start: s.entries.len, count: count)
  for i in 0 ..< count:
    let name = bankName(banks[i])
    s.entries.add DiskEntry(
      path: path,
      bank: i,
      # An unnamed disk is common; fall back to the file it came from, and
      # number it only when that alone would not tell two disks apart.
      label: if name.len > 0: name
             elif count > 1: fileName & " #" & $i
             else: fileName,
      mediaType: banks[i].mediaType.int,
      writeProtected: banks[i].writeProtected != 0)

proc build*(paths: openArray[string]): DiskSet =
  ## Flattens an ordered list of image files into one disk sequence.
  ## `paths` is expected to hold only floppy images - the caller filters
  ## tapes out, since they do not belong to a drive.
  for p in paths:
    result.addFile(p)

proc groupOf*(s: DiskSet, index: int): int =
  ## Which group entry `index` belongs to, or -1 if it belongs to none.
  for i, g in s.groups:
    if index >= g.start and index < g.start + g.count:
      return i
  -1
