## Does-nothing file dialogs for the platforms without a backend yet.
##
## Every panel answers the way a cancelled one does, and messages go to
## the standard error stream, so the application runs to completion
## instead of blocking on UI that is not there.

proc setParentWindow*(window: pointer) =
  ## Nothing here has a window to hang a dialog from.
  discard

proc openFile*(extensions: string): string =
  ## "" is what a cancelled panel returns.
  ""

proc saveFile*(extensions, suggestedName: string): string = ""

proc chooseFolder*(title, prompt: string): string = ""

proc message*(title, body, okLabel: string) =
  stderr.writeLine(title & ": " & body)

proc missingRom*(title, body, folder, openLabel, quitLabel: string): bool =
  ## False means the folder was not revealed; the caller quits either way.
  stderr.writeLine(title & ": " & body & " (" & folder & ")")
  false

proc chooseDisk*(title: string, rows: openArray[string], initial: int,
                 insertLabel, cancelLabel: string): int =
  ## The disk the caller would have preselected, rather than -1: a
  ## multi-disk image should still mount something without a dialog.
  initial
