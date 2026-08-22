## Win32 backend for ui/filedialog.nim: the classic Explorer open/save
## panels (GetOpenFileNameW/GetSaveFileNameW), the folder browser
## (SHBrowseForFolderW), and TaskDialogIndirect for everything this app
## needs a button on - a plain message, the missing-ROM choice, and the
## multi-disk chooser (as a set of radio buttons rather than GTK's combo
## box, which TaskDialog has no equivalent control for).
##
## Every dialog parents to winshell.mainHwnd, the one window this app owns;
## setParentWindow has nothing to do because of it (see its doc comment).

import std/strutils
import ./win32
import ./winshell

const MaxPathBuf = 32768
  ## Generous enough for GetOpenFileNameW's long-path form (OFN_EXPLORER)
  ## and for SHGetPathFromIDListW's MAX_PATH-bound result alike.

proc earlyInit*() =
  ensureCom()

proc setParentWindow*(window: pointer) =
  ## The Windows dialogs already parent to winshell.mainHwnd; there is
  ## nothing to store from this SDL_Window* pointer.
  discard

proc buildFilter(extensions: string): WideCString =
  ## The "Description\0*.ext;*.EXT\0\0" double-null-terminated multi-string
  ## GetOpenFileNameW/GetSaveFileNameW expect. Each extension is listed in
  ## both cases, as the caller's own pattern arrives spelled both ways.
  var patterns: seq[string]
  for ext in extensions.split(','):
    let e = ext.strip()
    if e.len == 0: continue
    patterns.add "*." & e.toLowerAscii()
    patterns.add "*." & e.toUpperAscii()
  if patterns.len == 0:
    return toWide("All Files (*.*)\0*.*\0")
  let joined = patterns.join(";")
  toWide(joined & " (" & joined & ")\0" & joined & "\0")

proc runFileDialog(save: bool, extensions, suggestedName, startDir: string): string =
  var buf = newSeq[uint16](MaxPathBuf)
  utf8ToUtf16Buf(suggestedName, buf)
  let filter = buildFilter(extensions)
  var dirWide = toWide(startDir)
  var ofn = OpenFileNameW(
    lStructSize: sizeof(OpenFileNameW).uint32,
    hwndOwner: winshell.mainHwnd,
    lpstrFilter: filter,
    lpstrFile: cast[WideCString](addr buf[0]),
    nMaxFile: buf.len.uint32,
    lpstrInitialDir: (if startDir.len > 0: dirWide else: WideCString(nil)),
    flags: OfnExplorer or
      (if save: OfnOverwriteprompt else: OfnFileMustExist or OfnPathMustExist))
  let ok = if save: getSaveFileNameW(addr ofn) else: getOpenFileNameW(addr ofn)
  if ok == 0:
    return ""
  utf16BufToUtf8(buf)

proc openFile*(extensions, startDir: string): string =
  runFileDialog(false, extensions, "", startDir)

proc saveFile*(extensions, suggestedName, startDir: string): string =
  runFileDialog(true, extensions, suggestedName, startDir)

proc chooseFolder*(title, prompt, startDir: string): string =
  ## `prompt` (the accept button's own label on the other platforms) has no
  ## home here: the classic folder browser's OK button is not relabelled,
  ## so only `title`, shown as the instructional text above the tree, is used.
  var titleWide = toWide(title)
  var bi = BrowseInfoW(hwndOwner: winshell.mainHwnd, lpszTitle: titleWide,
    ulFlags: BifReturnonlyfsdirs or BifNewdialogstyle)
  let pidl = shBrowseForFolderW(addr bi)
  if pidl == nil:
    return ""
  var buf = newSeq[uint16](MaxPathBuf)
  discard shGetPathFromIDListW(pidl, cast[WideCString](addr buf[0]))
  coTaskMemFree(pidl)
  utf16BufToUtf8(buf)

proc message*(title, body, okLabel: string) =
  ensureCommonControls()
  var buttons = @[TaskDialogButton(id: IdOk, text: toWide(okLabel))]
  discard runTaskDialog(winshell.mainHwnd, title, title, body, buttons, IdOk)

proc missingRom*(title, body, folder, openLabel, quitLabel: string): bool =
  ensureCommonControls()
  const OpenId = 100'i32
  var buttons = @[
    TaskDialogButton(id: OpenId, text: toWide(openLabel)),
    TaskDialogButton(id: IdCancel, text: toWide(quitLabel))]
  let (btn, _) = runTaskDialog(winshell.mainHwnd, title, title, body,
    buttons, OpenId)
  result = btn == OpenId
  if result:
    discard shellExecuteW(winshell.mainHwnd, toWide("open"), toWide(folder),
      WideCString(nil), WideCString(nil), SwShowNormal)

proc chooseDisk*(title: string, rows: openArray[string], initial: int,
                 insertLabel, cancelLabel: string): int =
  ensureCommonControls()
  const RadioBase = 1000'i32
  var radios: seq[TaskDialogButton]
  for i, row in rows:
    radios.add TaskDialogButton(id: RadioBase + i.int32, text: toWide(sjisToUtf8(row)))
  var buttons = @[
    TaskDialogButton(id: IdOk, text: toWide(insertLabel)),
    TaskDialogButton(id: IdCancel, text: toWide(cancelLabel))]
  let defaultRadio = RadioBase + max(0, initial).int32
  let (btn, radio) = runTaskDialog(winshell.mainHwnd, title, title, "",
    buttons, IdOk, radios, defaultRadio)
  if btn != IdOk:
    return -1
  let idx = radio - RadioBase
  if idx < 0 or idx.int >= rows.len: initial else: idx.int
