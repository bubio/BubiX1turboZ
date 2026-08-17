## AppKit backend for ui/statepicker.nim: a grid of thumbnails, one per
## slot. See statepicker.m and docs/dev/SaveState.md section 9.

import std/os
import ../types

{.compile: "statepicker.m".}
# statepicker.h is included by the generated C as well as by the .m file,
# and the compiler is invoked from the project root, so its own directory
# has to be on the include path.
{.passC: "-I" & currentSourcePath().parentDir.}
{.passL: "-framework Cocoa".}

type
  CSlot {.importc: "bx1_state_slot", header: "statepicker.h", bycopy.} = object
    caption, detail, disks: cstring
    png: ptr uint8
    pngLen {.importc: "png_len".}: cint
    enabled: cint

proc bx1StatePicker(title: cstring, slots: ptr CSlot, count: cint,
                    cancelLabel, emptyLabel: cstring): cint
  {.importc: "bx1_state_picker", header: "statepicker.h", cdecl.}

proc choose*(title: string, cells: seq[SlotCell],
             cancelLabel, emptyLabel: string): int =
  # The C strings and PNG buffers must outlive the call, so the Nim values
  # backing them are kept alive here rather than built inline.
  var caption = newSeq[string](cells.len)
  var detail = newSeq[string](cells.len)
  var disks = newSeq[string](cells.len)
  var raw = newSeq[CSlot](cells.len)
  for i, cell in cells:
    caption[i] = cell.caption
    detail[i] = cell.detail
    disks[i] = cell.disks
    raw[i] = CSlot(
      caption: caption[i].cstring,
      detail: detail[i].cstring,
      disks: disks[i].cstring,
      png: if cell.thumbnail.len > 0: unsafeAddr cells[i].thumbnail[0] else: nil,
      pngLen: cell.thumbnail.len.cint,
      enabled: cell.enabled.cint)
  bx1StatePicker(title.cstring, addr raw[0], cells.len.cint,
                 cancelLabel.cstring, emptyLabel.cstring).int
