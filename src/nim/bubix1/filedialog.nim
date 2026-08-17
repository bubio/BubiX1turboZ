## Native open/save panels and alerts. They run app-modal rather than as a
## sheet: the only window this app has is SDL's, and a panel hanging off it
## is not where macOS puts one. See filedialog.m.
##
## The AppKit side draws no words of its own: every button title is passed
## down from the catalog here, so the GTK and Win32 backends this will grow
## inherit the same translations (see i18n.nim).

import ./i18n

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

const
  DiskExtensions* = "d88,d77,d8e,1dd,2d,zip,7z,m3u,m3u8"
    ## Everything FD0/FD1's Insert accepts: disk images, archives and
    ## playlists together, so one action covers them all (the model
    ## Bubilator88 uses - see its diskFileTypes).
  TapeExtensions* = "tap,cmt,t88,wav,zip,7z,m3u,m3u8"
    ## Currently unreferenced: no UI opens a tape (see bubix1turboz.nim,
    ## where the CMT menu would be built). Kept for when the deck is
    ## exposed again.
  BlankDiskExtensions* = "d88"

proc takeString(raw: cstring): string =
  if raw == nil:
    return ""
  result = $raw
  bx1DialogFree(raw)

proc openFile*(extensions = ""): string =
  ## Empty string means the user cancelled.
  takeString(bx1DialogOpenFile(extensions.cstring))

proc saveFile*(extensions = "", suggestedName = ""): string =
  takeString(bx1DialogSaveFile(extensions.cstring, suggestedName.cstring))

proc message*(title, body: string) =
  let ok = tr(msgButtonOk)
  bx1DialogMessage(title.cstring, body.cstring, ok.cstring)

proc missingRom*(title, body, folder: string): bool {.discardable.} =
  ## Startup alert for a ROM folder with no BIOS ROM in it, offering to
  ## reveal `folder` in the Finder. True if the folder was revealed.
  let open = tr(msgButtonOpenRomFolder)
  let quitLabel = tr(msgButtonQuit)
  bx1DialogMissingRom(title.cstring, body.cstring, folder.cstring,
                      open.cstring, quitLabel.cstring) != 0

proc chooseDisk*(title: string, rows: openArray[string], initial = 0): int =
  ## Asks which disk of a multi-disk image to insert. Returns -1 if the user
  ## cancelled. `rows` may hold raw Shift-JIS from a D88 header; the dialog
  ## decodes it (see filedialog.m).
  if rows.len == 0:
    return -1
  var raw = allocCStringArray(rows)
  let insert = tr(msgButtonInsert)
  let cancel = tr(msgButtonCancel)
  result = bx1DialogChooseDisk(title.cstring, raw, rows.len.cint, initial.cint,
                               insert.cstring, cancel.cstring).int
  deallocCStringArray(raw)
