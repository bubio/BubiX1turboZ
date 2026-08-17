## AppKit backend for ui/filedialog.nim. See filedialog.m.
##
## The panels run app-modal rather than as a sheet: the only window this
## app has is SDL's, and a panel hanging off it is not where macOS puts
## one.
##
## The AppKit side draws no words of its own - every button title arrives
## from the facade, which took it from the message catalog.

{.compile: "filedialog.m".}
{.passL: "-framework Cocoa".}

proc bx1DialogOpenFile(extensions: cstring): cstring
  {.importc: "bx1_dialog_open_file", cdecl.}
proc bx1DialogSaveFile(extensions, suggestedName: cstring): cstring
  {.importc: "bx1_dialog_save_file", cdecl.}
proc bx1DialogFree(text: cstring) {.importc: "bx1_dialog_free", cdecl.}
proc bx1DialogMessage(title, body, okLabel: cstring)
  {.importc: "bx1_dialog_message", cdecl.}
proc bx1DialogMissingRom(title, body, folder, openLabel, quitLabel: cstring): cint
  {.importc: "bx1_dialog_missing_rom", cdecl.}
proc bx1DialogChooseDisk(title: cstring, rows: cstringArray, count, initial: cint,
                         insertLabel, cancelLabel: cstring): cint
  {.importc: "bx1_dialog_choose_disk", cdecl.}

proc takeString(raw: cstring): string =
  if raw == nil:
    return ""
  result = $raw
  bx1DialogFree(raw)

proc openFile*(extensions: string): string =
  takeString(bx1DialogOpenFile(extensions.cstring))

proc saveFile*(extensions, suggestedName: string): string =
  takeString(bx1DialogSaveFile(extensions.cstring, suggestedName.cstring))

proc message*(title, body, okLabel: string) =
  bx1DialogMessage(title.cstring, body.cstring, okLabel.cstring)

proc missingRom*(title, body, folder, openLabel, quitLabel: string): bool =
  bx1DialogMissingRom(title.cstring, body.cstring, folder.cstring,
                      openLabel.cstring, quitLabel.cstring) != 0

proc chooseDisk*(title: string, rows: openArray[string], initial: int,
                 insertLabel, cancelLabel: string): int =
  ## `rows` may hold raw Shift-JIS from a D88 header; the dialog decodes
  ## it (see filedialog.m).
  var raw = allocCStringArray(rows)
  result = bx1DialogChooseDisk(title.cstring, raw, rows.len.cint, initial.cint,
                               insertLabel.cstring, cancelLabel.cstring).int
  deallocCStringArray(raw)
