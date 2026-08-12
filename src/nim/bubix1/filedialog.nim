## Native open/save panels and alerts, replacing uing's - which open as a
## sheet on whichever uiWindow they are given, and this app's only uiWindow
## is a placeholder libui requires for the menu bar. See filedialog.m.

{.compile: "filedialog.m".}
{.passL: "-framework Cocoa".}

proc bx1DialogOpenFile(extensions: cstring): cstring
  {.importc: "bx1_dialog_open_file", cdecl.}
proc bx1DialogSaveFile(extensions, suggestedName: cstring): cstring
  {.importc: "bx1_dialog_save_file", cdecl.}
proc bx1DialogFree(text: cstring) {.importc: "bx1_dialog_free", cdecl.}
proc bx1DialogMessage(title, body: cstring) {.importc: "bx1_dialog_message", cdecl.}

const
  DiskExtensions* = "d88,d77,d8e,1dd,2d,zip,7z,m3u,m3u8"
    ## Everything FD0/FD1's Insert accepts: disk images, archives and
    ## playlists together, so one action covers them all (the model
    ## Bubilator88 uses - see its diskFileTypes).
  TapeExtensions* = "tap,cmt,t88,wav,zip,7z,m3u,m3u8"
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
  bx1DialogMessage(title.cstring, body.cstring)
