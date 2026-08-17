## Native open/save panels and alerts.
##
## Every word a panel shows is looked up here and passed down, so a
## backend draws no text of its own and each new one inherits the
## translations rather than repeating them (see i18n.nim).

import ../i18n

when defined(macosx):
  from ./macos/filedialog as backend import nil
else:
  from ./stub/filedialog as backend import nil

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

proc openFile*(extensions = ""): string =
  ## Empty string means the user cancelled.
  backend.openFile(extensions)

proc saveFile*(extensions = "", suggestedName = ""): string =
  backend.saveFile(extensions, suggestedName)

proc message*(title, body: string) =
  backend.message(title, body, tr(msgButtonOk))

proc missingRom*(title, body, folder: string): bool {.discardable.} =
  ## Startup alert for a ROM folder with no BIOS ROM in it, offering to
  ## reveal `folder` in the host's file manager. True if it was revealed.
  backend.missingRom(title, body, folder, tr(msgButtonOpenRomFolder),
                     tr(msgButtonQuit))

proc chooseDisk*(title: string, rows: openArray[string], initial = 0): int =
  ## Asks which disk of a multi-disk image to insert. Returns -1 if the
  ## user cancelled. `rows` may hold raw Shift-JIS from a D88 header; the
  ## backend decodes it, keeping this app's single decoding point.
  if rows.len == 0:
    return -1
  backend.chooseDisk(title, rows, initial, tr(msgButtonInsert),
                     tr(msgButtonCancel))
