## The save state slot picker: a grid of thumbnails, one per slot.
##
## Follows Bubilator88's SaveStateSheetView rather than the original's two
## submenus of ten numbered items - a state is worth choosing by what it
## looks like, which a menu cannot show. See statepicker.m for the AppKit
## side and docs/dev/SaveState.md section 9.

import std/os

{.compile: "statepicker.m".}
# statepicker.h is included by the generated C as well as by the .m file,
# and the compiler is invoked from the project root, so its own directory
# has to be on the include path.
{.passC: "-I" & currentSourcePath().parentDir.}
{.passL: "-framework Cocoa".}

type
  SlotCell* = object
    ## One cell. `disks` may hold raw D88 header bytes (Shift-JIS); it is
    ## passed through untouched and decoded on the AppKit side, keeping
    ## this app's single decoding point (see diskset.nim).
    caption*: string   ## "Slot 3"
    detail*: string    ## when it was taken, "" for an empty slot
    disks*: string     ## what was in the drives, "" if nothing
    thumbnail*: seq[byte] ## PNG, empty for an empty slot
    enabled*: bool

  CSlot {.importc: "bx1_state_slot", header: "statepicker.h", bycopy.} = object
    caption, detail, disks: cstring
    png: ptr uint8
    pngLen {.importc: "png_len".}: cint
    enabled: cint

proc bx1StatePicker(title: cstring, slots: ptr CSlot, count: cint): cint
  {.importc: "bx1_state_picker", header: "statepicker.h", cdecl.}

proc choose*(title: string, cells: seq[SlotCell]): int =
  ## Returns the chosen index, or -1 if the user cancelled. Blocks the
  ## caller (and so the emulation loop) until then - drop the audio the
  ## machine could not produce meanwhile once it returns.
  if cells.len == 0:
    return -1
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
  bx1StatePicker(title.cstring, addr raw[0], cells.len.cint).int
