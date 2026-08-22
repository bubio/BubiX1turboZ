## Raw Win32 / GDI+ / Common Controls bindings shared by the Windows UI
## backends.
##
## Every Windows backend imports this one module, so the linker flags that
## find user32/gdi32/comdlg32/comctl32/shell32/ole32/gdiplus live here and
## nowhere else. The bindings are the plain C entry points; the shaping into
## the application's own vocabulary is done by the backends and by
## winshell.nim, mirroring how bubix1/ui/linux/gtk3.nim and gtkshell.nim
## split the same job for GTK.
##
## This file names a host library and so belongs under bubix1/ui - the
## boundary bubix1/ui/README.md draws. It is compiled only on the platforms
## whose UI facades select a windows backend.

import std/widestrs

{.passL: "-luser32 -lgdi32 -lcomdlg32 -lcomctl32 -lshell32 -lole32 -lgdiplus -luuid".}

type
  Handle* = pointer
  HWND* = Handle
  HMENU* = Handle
  HINSTANCE* = Handle
  HDC* = Handle
  HGDIOBJ* = Handle
  HBITMAP* = Handle
  HBRUSH* = Handle
  HICON* = Handle
  HCURSOR* = Handle
  HGLOBAL* = Handle
  ATOM* = uint16
  WPARAM* = uint
  LPARAM* = int
  LRESULT* = int
  Colorref* = uint32
  WndProc* = proc (hwnd: HWND, msg: uint32, wParam: WPARAM,
                   lParam: LPARAM): LRESULT {.stdcall.}

  Rect* = object
    left*, top*, right*, bottom*: int32

  Point* = object
    x*, y*: int32

  Msg* = object
    hwnd*: HWND
    message*: uint32
    wParam*: WPARAM
    lParam*: LPARAM
    time*: uint32
    pt*: Point

  WndClassExW* = object
    cbSize*: uint32
    style*: uint32
    lpfnWndProc*: WndProc
    cbClsExtra*, cbWndExtra*: int32
    hInstance*: HINSTANCE
    hIcon*: HICON
    hCursor*: HCURSOR
    hbrBackground*: HBRUSH
    lpszMenuName*: WideCString
    lpszClassName*: WideCString
    hIconSm*: HICON

  OpenFileNameW* = object
    lStructSize*: uint32
    hwndOwner*: HWND
    hInstance*: HINSTANCE
    lpstrFilter*: WideCString
    lpstrCustomFilter*: WideCString
    nMaxCustFilter*: uint32
    nFilterIndex*: uint32
    lpstrFile*: WideCString
    nMaxFile*: uint32
    lpstrFileTitle*: WideCString
    nMaxFileTitle*: uint32
    lpstrInitialDir*: WideCString
    lpstrTitle*: WideCString
    flags*: uint32
    nFileOffset*, nFileExtension*: uint16
    lpstrDefExt*: WideCString
    lCustData*: LPARAM
    lpfnHook*: pointer
    lpTemplateName*: WideCString
    pvReserved*: pointer
    dwReserved*, flagsEx*: uint32

  BrowseInfoW* = object
    hwndOwner*: HWND
    pidlRoot*: pointer
    pszDisplayName*: WideCString
    lpszTitle*: WideCString
    ulFlags*: uint32
    lpfn*: proc (hwnd: HWND, msg: uint32, lp, data: LPARAM): cint {.stdcall.}
    lParam*: LPARAM
    iImage*: cint

const
  # Window styles / show commands
  WsOverlappedWindow* = 0x00cf0000'u32
  WsChild* = 0x40000000'u32
  WsVisible* = 0x10000000'u32
  WsTabstop* = 0x00010000'u32
  WsGroup* = 0x00020000'u32
  WsBorder* = 0x00800000'u32
  WsVscroll* = 0x00200000'u32
  WsClipChildren* = 0x02000000'u32
  WsPopup* = 0x80000000'u32
  WsCaption* = 0x00c00000'u32
  WsSysmenu* = 0x00080000'u32
  SwHide* = 0'i32
  SwShow* = 5'i32
  SwShowNormal* = 1'i32

  # Window messages
  WmDestroy* = 0x0002'u32
  WmSize* = 0x0005'u32
  WmClose* = 0x0010'u32
  WmCommand* = 0x0111'u32
  WmSysCommand* = 0x0112'u32
  WmHscroll* = 0x0114'u32
  WmDrawitem* = 0x002b'u32
  WmMeasureitem* = 0x002c'u32
  WmCtlcolorstatic* = 0x0138'u32
  WmCtlcolordlg* = 0x0136'u32
  WmSetfont* = 0x0030'u32
  WmInitdialog* = 0x0110'u32
  WmNotify* = 0x004e'u32
  WmNcdestroy* = 0x0082'u32
  WmErasebkgnd* = 0x0014'u32
  WmPaint* = 0x000f'u32
  WmLbuttondown* = 0x0201'u32

  # GetWindowLongPtr indices
  GwlpUserdata* = -21'i32
  GwlWndproc* = -4'i32

  # Button / static styles
  BsPushbutton* = 0x00000000'u32
  BsAutocheckbox* = 0x00000003'u32
  BsGroupbox* = 0x00000007'u32
  BsOwnerdraw* = 0x0000000b'u32
  SsLeft* = 0x00000000'u32
  SsCenter* = 0x00000001'u32
  SsCenterimage* = 0x00000200'u32
  SsNotify* = 0x00000100'u32
  SsBitmap* = 0x0000000e'u32

  # Trackbar (comctl32 "msctls_trackbar32")
  TbsHorz* = 0x0000'u32
  TbsAutoticks* = 0x0001'u32
  TbsNoticks* = 0x0010'u32
  TbmSetrange* = (0x0400 + 6).uint32
  TbmSetpos* = (0x0400 + 5).uint32
  TbmGetpos* = (0x0400 + 0).uint32

  # Button check state
  BmSetcheck* = 0x00f1'u32
  BmGetcheck* = 0x00f0'u32
  BstChecked* = 1'u32
  BstUnchecked* = 0'u32

  # SetWindowPos flags
  SwpNozorder* = 0x0004'u32
  SwpNoactivate* = 0x0010'u32
  SwpNomove* = 0x0002'u32
  SwpNosize* = 0x0001'u32
  HwndTop*: HWND = nil

  # Menu flags
  MfString* = 0x00000000'u32
  MfSeparator* = 0x00000800'u32
  MfPopup* = 0x00000010'u32
  MfByposition* = 0x00000400'u32
  MfBycommand* = 0x00000000'u32
  MfChecked* = 0x00000008'u32
  MfUnchecked* = 0x00000000'u32
  MfEnabled* = 0x00000000'u32
  MfGrayed* = 0x00000001'u32
  MfDisabled* = 0x00000002'u32

  # MessageBox
  MbOk* = 0x00000000'u32
  MbOkcancel* = 0x00000001'u32
  MbYesno* = 0x00000004'u32
  MbIconinformation* = 0x00000040'u32
  MbIconwarning* = 0x00000030'u32
  IdOk* = 1'i32
  IdYes* = 6'i32

  # GetOpenFileName / GetSaveFileName flags
  OfnFileMustExist* = 0x00001000'u32
  OfnPathMustExist* = 0x00000800'u32
  OfnOverwriteprompt* = 0x00000002'u32
  OfnExplorer* = 0x00080000'u32

  # SHBrowseForFolder flags
  BifReturnonlyfsdirs* = 0x00000001'u32
  BifNewdialogstyle* = 0x00000040'u32
  BffmInitialized* = 1'i32
  BffmSetselectionw* = (0x0400 + 103).uint32

  # Clipboard formats
  CfUnicodetext* = 13'u32

  # Static color brush stock objects
  WhiteBrush* = 0'i32
  NullBrush* = 5'i32

  # System color index for the dialog/control face - cast to a HBRUSH as
  # `ColorBtnface + 1` (the classic Win32 "pseudo handle" idiom: any
  # COLOR_* index, offset by one, doubles as a HBRUSH that repaints itself
  # in the current theme color and stays correct across a WM_SYSCOLORCHANGE,
  # unlike a stock brush like WhiteBrush which is a literal fixed color).
  ColorBtnface* = 15'i32

  # The .rc resource id assets/windows/app.rc gives the exe's own icon.
  AppIconResourceId* = 1'i32

{.push stdcall, header: "<windows.h>".}
proc getModuleHandleW*(name: WideCString): HINSTANCE {.importc: "GetModuleHandleW".}
proc registerClassExW*(wc: pointer): ATOM {.importc: "RegisterClassExW".}
proc createWindowExW*(exStyle: uint32, className, windowName: WideCString,
  style: uint32, x, y, w, h: int32, parent: HWND, menu: HMENU,
  instance: HINSTANCE, param: pointer): HWND {.importc: "CreateWindowExW".}
proc defWindowProcW*(hwnd: HWND, msg: uint32, wParam: WPARAM,
  lParam: LPARAM): LRESULT {.importc: "DefWindowProcW".}
proc destroyWindow*(hwnd: HWND): cint {.importc: "DestroyWindow".}
proc showWindow*(hwnd: HWND, cmdShow: int32): cint {.importc: "ShowWindow".}
proc updateWindow*(hwnd: HWND): cint {.importc: "UpdateWindow".}
proc setWindowTextW*(hwnd: HWND, text: WideCString): cint {.importc: "SetWindowTextW".}
proc moveWindow*(hwnd: HWND, x, y, w, h: int32, repaint: cint): cint {.importc: "MoveWindow".}
proc setWindowPos*(hwnd: HWND, insertAfter: HWND, x, y, w, h: int32,
  flags: uint32): cint {.importc: "SetWindowPos".}
proc getClientRect*(hwnd: HWND, rect: pointer): cint {.importc: "GetClientRect".}
proc getWindowRect*(hwnd: HWND, rect: pointer): cint {.importc: "GetWindowRect".}
proc screenToClient*(hwnd: HWND, point: pointer): cint {.importc: "ScreenToClient".}
proc clientToScreen*(hwnd: HWND, point: pointer): cint {.importc: "ClientToScreen".}
proc invalidateRect*(hwnd: HWND, rect: pointer, erase: cint): cint {.importc: "InvalidateRect".}
proc getDlgItem*(hwnd: HWND, id: cint): HWND {.importc: "GetDlgItem".}
proc setFocus*(hwnd: HWND): HWND {.importc: "SetFocus".}
proc enableWindow*(hwnd: HWND, enable: cint): cint {.importc: "EnableWindow".}
proc getParent*(hwnd: HWND): HWND {.importc: "GetParent".}
proc setParent*(hwnd, newParent: HWND): HWND {.importc: "SetParent".}

proc getWindowLongPtrW*(hwnd: HWND, index: int32): int {.importc: "GetWindowLongPtrW".}
proc setWindowLongPtrW*(hwnd: HWND, index: int32, value: int): int {.importc: "SetWindowLongPtrW".}
proc callWindowProcW*(prevWndFunc: pointer, hwnd: HWND, msg: uint32,
  wParam: WPARAM, lParam: LPARAM): LRESULT {.importc: "CallWindowProcW".}

proc getMessageW*(msg: pointer, hwnd: HWND, msgMin, msgMax: uint32): cint {.importc: "GetMessageW".}
proc peekMessageW*(msg: pointer, hwnd: HWND, msgMin, msgMax: uint32,
  remove: uint32): cint {.importc: "PeekMessageW".}
proc translateMessage*(msg: pointer): cint {.importc: "TranslateMessage".}
proc dispatchMessageW*(msg: pointer): LRESULT {.importc: "DispatchMessageW".}
proc postQuitMessage*(exitCode: cint) {.importc: "PostQuitMessage".}
proc sendMessageW*(hwnd: HWND, msg: uint32, wParam: WPARAM,
  lParam: LPARAM): LRESULT {.importc: "SendMessageW".}
proc postMessageW*(hwnd: HWND, msg: uint32, wParam: WPARAM,
  lParam: LPARAM): cint {.importc: "PostMessageW".}

proc createMenu*(): HMENU {.importc: "CreateMenu".}
proc createPopupMenu*(): HMENU {.importc: "CreatePopupMenu".}
proc appendMenuW*(menu: HMENU, flags: uint32, idOrSubmenu: uint, text: WideCString): cint {.importc: "AppendMenuW".}
proc removeMenu*(menu: HMENU, position: uint32, flags: uint32): cint {.importc: "RemoveMenu".}
proc modifyMenuW*(menu: HMENU, position: uint32, flags: uint32,
  idOrSubmenu: uint, text: WideCString): cint {.importc: "ModifyMenuW".}
proc checkMenuItem*(menu: HMENU, id: uint32, check: uint32): uint32 {.importc: "CheckMenuItem".}
proc enableMenuItem*(menu: HMENU, id: uint32, enable: uint32): cint {.importc: "EnableMenuItem".}
proc getMenuItemCount*(menu: HMENU): cint {.importc: "GetMenuItemCount".}
proc setMenu*(hwnd: HWND, menu: HMENU): cint {.importc: "SetMenu".}
proc drawMenuBar*(hwnd: HWND): cint {.importc: "DrawMenuBar".}
proc destroyMenu*(menu: HMENU): cint {.importc: "DestroyMenu".}

proc messageBoxW*(hwnd: HWND, text, caption: WideCString, kind: uint32): cint {.importc: "MessageBoxW".}

proc openClipboard*(hwnd: HWND): cint {.importc: "OpenClipboard".}
proc closeClipboard*(): cint {.importc: "CloseClipboard".}
proc isClipboardFormatAvailable*(format: uint32): cint {.importc: "IsClipboardFormatAvailable".}
proc getClipboardData*(format: uint32): HGLOBAL {.importc: "GetClipboardData".}
proc globalLock*(mem: HGLOBAL): pointer {.importc: "GlobalLock".}
proc globalUnlock*(mem: HGLOBAL): cint {.importc: "GlobalUnlock".}

proc loadCursorW*(instance: HINSTANCE, name: pointer): HCURSOR {.importc: "LoadCursorW".}
proc loadIconW*(instance: HINSTANCE, name: WideCString): HICON {.importc: "LoadIconW".}
proc getStockObject*(kind: int32): HGDIOBJ {.importc: "GetStockObject".}
proc getSystemMetrics*(index: int32): int32 {.importc: "GetSystemMetrics".}
proc fillRect*(dc: HDC, rect: pointer, brush: HBRUSH): cint {.importc: "FillRect".}
proc setBkMode*(dc: HDC, mode: int32): int32 {.importc: "SetBkMode".}
proc setTextColor*(dc: HDC, color: Colorref): Colorref {.importc: "SetTextColor".}
proc createSolidBrush*(color: Colorref): HBRUSH {.importc: "CreateSolidBrush".}
proc deleteObject*(obj: HGDIOBJ): cint {.importc: "DeleteObject".}
proc drawTextW*(dc: HDC, text: WideCString, count: int32, rect: pointer,
  format: uint32): int32 {.importc: "DrawTextW".}
proc getDC*(hwnd: HWND): HDC {.importc: "GetDC".}
proc releaseDC*(hwnd: HWND, dc: HDC): cint {.importc: "ReleaseDC".}
proc createCompatibleDC*(dc: HDC): HDC {.importc: "CreateCompatibleDC".}
proc createCompatibleBitmap*(dc: HDC, w, h: int32): HBITMAP {.importc: "CreateCompatibleBitmap".}
proc deleteDC*(dc: HDC): cint {.importc: "DeleteDC".}
proc selectObject*(dc: HDC, obj: HGDIOBJ): HGDIOBJ {.importc: "SelectObject".}
proc setStretchBltMode*(dc: HDC, mode: int32): int32 {.importc: "SetStretchBltMode".}
proc stretchBlt*(dstDc: HDC, dstX, dstY, dstW, dstH: int32, srcDc: HDC,
  srcX, srcY, srcW, srcH: int32, rop: uint32): cint {.importc: "StretchBlt".}
proc createFontW*(height, width, escapement, orientation, weight: int32,
  italic, underline, strikeOut, charSet, outPrecision, clipPrecision,
  quality, pitchAndFamily: uint32, faceName: WideCString): HGDIOBJ {.importc: "CreateFontW".}

proc multiByteToWideChar*(codePage: uint32, flags: uint32, mbStr: cstring,
  mbLen: int32, wStr: WideCString, wLen: int32): int32 {.importc: "MultiByteToWideChar".}
proc wideCharToMultiByte*(codePage: uint32, flags: uint32, wStr: WideCString,
  wLen: int32, mbStr: cstring, mbLen: int32, defaultChar: cstring,
  usedDefaultChar: ptr cint): int32 {.importc: "WideCharToMultiByte".}
{.pop.}

# The rest of the Shell/COM/common-dialog surface: windows.h alone does not
# declare any of these (each needs its own header, unlike the winuser.h /
# wingdi.h surface above, which windows.h does pull in) - `-include
# windows.h` (build_nim_app.sh) still guarantees it comes first for these.
proc getOpenFileNameW*(ofn: pointer): cint
  {.importc: "GetOpenFileNameW", stdcall, header: "<commdlg.h>".}
proc getSaveFileNameW*(ofn: pointer): cint
  {.importc: "GetSaveFileNameW", stdcall, header: "<commdlg.h>".}
proc shellExecuteW*(hwnd: HWND, operation, file, parameters, directory: WideCString,
  showCmd: int32): pointer
  {.importc: "ShellExecuteW", stdcall, header: "<shellapi.h>".}
proc shBrowseForFolderW*(bi: pointer): pointer
  {.importc: "SHBrowseForFolderW", stdcall, header: "<shlobj.h>".}
proc shGetPathFromIDListW*(pidl: pointer, path: WideCString): cint
  {.importc: "SHGetPathFromIDListW", stdcall, header: "<shlobj.h>".}
proc coTaskMemFree*(p: pointer)
  {.importc: "CoTaskMemFree", stdcall, header: "<objbase.h>".}
proc coInitializeEx*(reserved: pointer, coInit: uint32): int32
  {.importc: "CoInitializeEx", stdcall, header: "<objbase.h>".}
proc coUninitialize*()
  {.importc: "CoUninitialize", stdcall, header: "<objbase.h>".}

const CpShiftJis* = 932'u32

proc sjisToUtf8*(s: string): string =
  ## D88 disk names and the like arrive as raw Shift-JIS. This is the app's
  ## one place on Windows that turns them into UTF-8 (the encoding every
  ## Nim `string` in this codebase is otherwise assumed to hold) - the same
  ## role ui/linux/gtk3.nim's sjisToUtf8 plays there, but done in one hop
  ## through UTF-16 since that is the encoding every Win32 text API wants
  ## anyway. A sequence Windows cannot convert is left untouched rather than
  ## dropped, matching the Linux behaviour.
  if s.len == 0:
    return ""
  let wideLen = multiByteToWideChar(CpShiftJis, 0, s.cstring, s.len.int32,
    WideCString(nil), 0)
  if wideLen <= 0:
    return s
  var wideBuf = newSeq[uint16](wideLen)
  discard multiByteToWideChar(CpShiftJis, 0, s.cstring, s.len.int32,
    cast[WideCString](addr wideBuf[0]), wideLen)
  let utf8Len = wideCharToMultiByte(65001'u32, 0, cast[WideCString](addr wideBuf[0]),
    wideLen, nil, 0, nil, nil)
  if utf8Len <= 0:
    return s
  var utf8Buf = newString(utf8Len)
  discard wideCharToMultiByte(65001'u32, 0, cast[WideCString](addr wideBuf[0]),
    wideLen, cast[cstring](addr utf8Buf[0]), utf8Len, nil, nil)
  utf8Buf

const CpUtf8 = 65001'u32

proc utf8ToUtf16Buf*(s: string, buf: var seq[uint16]) =
  ## Writes `s` as null-terminated UTF-16 into `buf` (already sized) - the
  ## write side of the conversion filedialog.nim needs to seed a fixed
  ## buffer a Win32 API (GetOpenFileNameW's lpstrFile) then writes back
  ## into. `buf` is left with just a null terminator if `s` does not fit.
  buf[0] = 0'u16
  if s.len == 0:
    return
  let wideLen = multiByteToWideChar(CpUtf8, 0, s.cstring, s.len.int32,
    WideCString(nil), 0)
  if wideLen <= 0 or wideLen + 1 > buf.len:
    return
  discard multiByteToWideChar(CpUtf8, 0, s.cstring, s.len.int32,
    cast[WideCString](addr buf[0]), wideLen.int32)
  buf[wideLen] = 0'u16

proc utf16BufToUtf8*(buf: openArray[uint16]): string =
  ## Reads a null-terminated UTF-16 buffer (GetOpenFileNameW's lpstrFile,
  ## or SHGetPathFromIDListW's output, on return) into UTF-8.
  var wideLen = 0
  while wideLen < buf.len and buf[wideLen] != 0'u16:
    inc wideLen
  if wideLen == 0:
    return ""
  let utf8Len = wideCharToMultiByte(CpUtf8, 0,
    cast[WideCString](unsafeAddr buf[0]), wideLen.int32, nil, 0, nil, nil)
  if utf8Len <= 0:
    return ""
  result = newString(utf8Len)
  discard wideCharToMultiByte(CpUtf8, 0, cast[WideCString](unsafeAddr buf[0]),
    wideLen.int32, cast[cstring](addr result[0]), utf8Len, nil, nil)

const
  SmCymenu* = 15'i32
  SmCxscreen* = 0'i32
  SmCyscreen* = 1'i32
  DtCenter* = 0x00000001'u32
  DtRight* = 0x00000002'u32
  DtVcenter* = 0x00000004'u32
  DtSingleline* = 0x00000020'u32
  DtEnd_ellipsis* = 0x00008000'u32
  TransparentBk* = 1'i32

proc initCommonControls*() {.importc: "InitCommonControls", stdcall,
  header: "<commctrl.h>".}

type
  DrawItemStruct* = object
    ## WM_DRAWITEM's payload, for an owner-draw button (the state picker's
    ## thumbnail cells - see ui/windows/statepicker.nim).
    ctlType*, ctlID*, itemID*, itemAction*, itemState*: uint32
    hwndItem*: HWND
    hDC*: HDC
    rcItem*: Rect
    itemData*: uint

  Bitmap* = object
    ## The subset of GDI's BITMAP struct pngToHBitmap's caller needs: just
    ## enough to read back the width/height GDI+ decoded, for StretchBlt's
    ## source rectangle.
    bmType*, bmWidth*, bmHeight*, bmWidthBytes*: int32
    bmPlanes*, bmBitsPixel*: uint16
    bmBits*: pointer

type
  BlendFunction* {.importc: "BLENDFUNCTION", header: "<wingdi.h>", bycopy.} = object
    ## Imported as the real C struct, not a Nim-shaped mirror of it: it is
    ## passed to AlphaBlend by value, where the pointer-conversion escape
    ## hatch the rest of this file's structs use (an untyped `pointer`
    ## parameter) is not available - C checks a by-value struct argument's
    ## type by name, not layout, same as it does the struct pointers below.
    blendOp* {.importc: "BlendOp".}: uint8
    blendFlags* {.importc: "BlendFlags".}: uint8
    sourceConstantAlpha* {.importc: "SourceConstantAlpha".}: uint8
    alphaFormat* {.importc: "AlphaFormat".}: uint8

const
  OdsSelected* = 0x0001'u32
  OdsDisabled* = 0x0004'u32
  AcSrcOver* = 0'u8
  AcSrcAlpha* = 1'u8
  SrcCopy* = 0x00cc0020'u32
  ColorOnColor* = 3'i32
  Transparent* = 1'i32

proc getObjectW(obj: HGDIOBJ, cb: int32, data: pointer): int32
  {.importc: "GetObjectW", stdcall, header: "<wingdi.h>".}

proc bitmapSize*(bmp: HBITMAP): tuple[w, h: int32] =
  ## The pixel size of a bitmap pngToHBitmap decoded - not knowable any
  ## other way, since GDI+ chose it from the PNG's own IHDR.
  var bm: Bitmap
  if getObjectW(bmp, sizeof(Bitmap).int32, addr bm) == 0:
    return (0'i32, 0'i32)
  (bm.bmWidth, bm.bmHeight)

proc alphaBlend*(dstDc: HDC, dstX, dstY, dstW, dstH: int32, srcDc: HDC,
  srcX, srcY, srcW, srcH: int32, blend: BlendFunction): cint
  {.importc: "AlphaBlend", stdcall, header: "<wingdi.h>".}

{.passL: "-lmsimg32".}

const CoinitApartmentthreaded* = 0x2'u32

var
  commonControlsUp = false
  comUp = false

proc ensureCom*() =
  ## TaskDialogIndirect and SHBrowseForFolderW are both COM-backed and fail
  ## silently - no window, no error - if the calling thread never
  ## initialized COM (confirmed empirically: missingRom's TaskDialog simply
  ## never appeared until this was added). Apartment-threaded, the model a
  ## UI thread making blocking calls like these wants.
  if not comUp:
    discard coInitializeEx(nil, CoinitApartmentthreaded)
    comUp = true

proc ensureCommonControls*() =
  ## Brings up the trackbar, TaskDialog and every other comctl32 control
  ## this app's Windows backends use. Requires the exe's manifest to name
  ## comctl32 v6 (see scripts/build_windows.sh) - without it these controls
  ## fall back to the Windows Classic look, or TaskDialogIndirect is not
  ## exported at all.
  ensureCom()
  if not commonControlsUp:
    initCommonControls()
    commonControlsUp = true

# --- GDI+ flat API, for decoding the PNG thumbnails the state picker shows.
type
  GpStatus* = int32
  GpImage* = pointer
  GpBitmap* = pointer
  GdiplusStartupInput* = object
    gdiplusVersion*: uint32
    debugEventCallback*: pointer
    suppressBackgroundThread*: int32
    suppressExternalCodecs*: int32

# gdiplus.h itself does not pull in the OLE headers PROPID comes from, and
# WIN32_LEAN_AND_MEAN (this build's -D, for a lighter windows.h) strips them
# out of windows.h's own include chain too - `#include "gdiplus.h": unknown
# type name 'PROPID'` otherwise. objidl.h drags in ole2.h regardless of that
# define, so force-including it ahead of everything (same -include mechanism
# the project's own build already uses for windows.h) is the standard fix -
# a plain `{.emit.}` is not late enough: Nim's C codegen gathers every
# `header`-pragma #include for a translation unit together, ahead of any
# module-level emit statement's own position in the source.
{.passC: "-include objidl.h".}

{.push stdcall, header: "<gdiplus.h>".}
proc gdiplusStartup*(token: ptr uint, input: pointer,
  output: pointer): GpStatus {.importc: "GdiplusStartup".}
proc gdiplusShutdown*(token: uint) {.importc: "GdiplusShutdown".}
proc gdipCreateBitmapFromStream*(stream: pointer, bitmap: ptr GpBitmap): GpStatus {.importc: "GdipCreateBitmapFromStream".}
proc gdipCreateHBITMAPFromBitmap*(bitmap: GpBitmap, hbmReturn: pointer,
  background: uint32): GpStatus {.importc: "GdipCreateHBITMAPFromBitmap".}
proc gdipDisposeImage*(image: GpImage): GpStatus {.importc: "GdipDisposeImage".}
{.pop.}

{.push stdcall, header: "<objidl.h>".}
proc createStreamOnHGlobal*(hGlobal: HGLOBAL, deleteOnRelease: cint,
  stream: pointer): int32 {.importc: "CreateStreamOnHGlobal".}
{.pop.}

type
  ComVtbl2 = object
    queryInterface, addRef: pointer
    release: proc (self: pointer): uint32 {.stdcall.}

proc comRelease(obj: pointer) =
  ## Releases a COM interface pointer through its vtable's IUnknown::Release
  ## (slot 2), without pulling in a full COM binding for the one call this
  ## file needs.
  if obj == nil: return
  let vtbl = cast[ptr ptr ComVtbl2](obj)[]
  discard vtbl.release(obj)

proc globalAlloc*(flags: uint32, bytes: csize_t): HGLOBAL
  {.importc: "GlobalAlloc", stdcall, header: "<windows.h>".}
proc memcpyToGlobal*(dest: pointer, src: pointer, count: csize_t)
  {.importc: "memcpy", header: "<string.h>".}

const
  GmemMovable* = 0x0002'u32
  PixelFormat32bppArgb* = 0x0026200a'i32

proc pngToHBitmap*(data: seq[byte]): HBITMAP =
  ## Decodes PNG bytes (as produced by bubix1/deflate.encodePng) into a GDI
  ## bitmap via GDI+, the flat C API every non-MFC Win32 program uses for
  ## image formats GDI itself cannot read. Returns nil if `data` is empty or
  ## fails to decode - the caller draws its own empty placeholder then.
  if data.len == 0:
    return nil
  let mem = globalAlloc(GmemMovable, data.len.csize_t)
  if mem == nil:
    return nil
  let locked = globalLock(mem)
  memcpyToGlobal(locked, unsafeAddr data[0], data.len.csize_t)
  discard globalUnlock(mem)
  var stream: pointer
  if createStreamOnHGlobal(mem, 1, addr stream) != 0:
    return nil
  var bitmap: GpBitmap
  result = nil
  if gdipCreateBitmapFromStream(stream, addr bitmap) == 0 and bitmap != nil:
    var hbm: HBITMAP
    if gdipCreateHBITMAPFromBitmap(bitmap, addr hbm, 0xffffffff'u32) == 0:
      result = hbm
    discard gdipDisposeImage(bitmap)
  # The IStream owns the HGLOBAL (deleteOnRelease = 1) and frees it when its
  # last reference drops; releasing this one is that drop.
  comRelease(stream)

proc toWide*(s: string): WideCString =
  ## Converts to a null-terminated UTF-16 string, in memory that is never
  ## freed - deliberately, matching every other one-shot Win32 string buffer
  ## in this file: a window title, a dialog's button text, a menu label are
  ## all created rarely, in response to a user action, so leaking the few
  ## dozen bytes each one takes costs nothing over the life of the process.
  ##
  ## `std/widestrs.newWideCString` is not used for this: it returns a
  ## `WideCStringObj`, whose `=destroy` frees its buffer as soon as the
  ## temporary that produced it goes out of scope - which, through the
  ## implicit converter this proc's `WideCString` return type used to
  ## trigger, happened before this proc even returned to its caller. Every
  ## caller that then stored the result in a struct field for a later Win32
  ## call was holding a dangling pointer to already-freed memory (confirmed
  ## empirically: two toWide() calls of the same length landed on the same
  ## freed-and-reused address, so a TaskDialog's second button silently
  ## repeated the first button's text - the multi-disk chooser and the
  ## missing-ROM alert's Open/Quit pair are both exactly this shape).
  if s.len == 0:
    return cast[WideCString](alloc0(2))
  let wideLen = multiByteToWideChar(CpUtf8, 0, s.cstring, s.len.int32,
    WideCString(nil), 0)
  if wideLen <= 0:
    return cast[WideCString](alloc0(2))
  result = cast[WideCString](alloc0((wideLen + 1) * 2))
  discard multiByteToWideChar(CpUtf8, 0, s.cstring, s.len.int32, result, wideLen)

proc fromWide*(w: WideCString): string =
  $w

# --- TaskDialogIndirect (comctl32 v6), for message/confirm/choice dialogs
# with fully custom button text - the equivalent of GTK's
# gtk_dialog_add_button with an arbitrary label, which MessageBoxW's fixed
# button sets cannot give. Requires the exe to carry a manifest naming
# comctl32 v6 (see scripts/build_windows.sh); ui/windows/filedialog.nim is
# the only caller.
type
  TaskDialogButton* {.packed.} = object
    ## Mirrors commctrl.h's TASKDIALOG_BUTTON, packed for the same reason as
    ## TaskDialogConfig above: it lives in the same pshpack1 region, and an
    ## array of these is what `buttons`/`radioButtons` there points at - an
    ## unpacked (16-byte-stride) array read by the OS as 12-byte-stride
    ## entries misreads every button past the first, which crashed with a
    ## SIGSEGV in the second button's (garbage) text pointer.
    id*: int32
    text*: WideCString

  TaskDialogConfig* {.packed.} = object
    ## Mirrors commctrl.h's own layout exactly: the real TASKDIALOGCONFIG is
    ## wrapped in `#include <pshpack1.h>` / `<poppack.h>` (byte packing, no
    ## alignment padding) - confirmed by reading mingw's commctrl.h and by a
    ## throwaway C program printing sizeof/offsetof against it (160 bytes,
    ## tightly packed). Without `{.packed.}` here Nim pads pointer fields to
    ## natural 8-byte alignment, so this object's sizeof came out to 176 -
    ## TaskDialogIndirect checks cbSize against its own sizeof and rejects
    ## any mismatch with E_INVALIDARG, which is exactly what made every
    ## TaskDialog in this app (including the missing-ROM alert) fail to
    ## appear with no window and no visible error.
    cbSize*: uint32
    hwndParent*: HWND
    hInstance*: HINSTANCE
    flags*: int32
    commonButtons*: int32
    windowTitle*: WideCString
    mainIcon*: WideCString      ## nil: TDF_USE_HICON_MAIN is never set below
    mainInstruction*: WideCString
    content*: WideCString
    buttonCount*: uint32
    buttons*: ptr UncheckedArray[TaskDialogButton]
    defaultButton*: int32
    radioButtonCount*: uint32
    radioButtons*: ptr UncheckedArray[TaskDialogButton]
    defaultRadioButton*: int32
    verificationText*: WideCString
    expandedInformation*: WideCString
    expandedControlText*: WideCString
    collapsedControlText*: WideCString
    footerIcon*: WideCString    ## nil: TDF_USE_HICON_FOOTER is never set
    footer*: WideCString
    callback*: pointer
    callbackData*: int
    width*: uint32

const
  TdfAllowDialogCancellation* = 0x0008'i32
  TdfSizeToContent* = 0x01000000'i32
  IdCancel* = 2'i32

proc taskDialogIndirect(config: pointer, button, radioButton: ptr int32,
  verificationChecked: ptr cint): int32
  {.importc: "TaskDialogIndirect", stdcall, header: "<commctrl.h>".}

proc runTaskDialog*(owner: HWND, title, instruction, content: string,
                    buttons: seq[TaskDialogButton], defaultId: int32,
                    radios: seq[TaskDialogButton] = @[],
                    defaultRadio: int32 = -1): tuple[button, radio: int32] =
  ## Runs a task dialog to completion and returns which button (and, if any
  ## were offered, which radio option) the user picked. `buttons`/`radios`
  ## must stay alive for the call, which is why callers build them just
  ## before calling this rather than caching them.
  var cfg = TaskDialogConfig(
    cbSize: sizeof(TaskDialogConfig).uint32,
    hwndParent: owner,
    flags: TdfAllowDialogCancellation or TdfSizeToContent,
    windowTitle: toWide(title),
    mainInstruction: toWide(instruction),
    content: toWide(content),
    buttonCount: buttons.len.uint32,
    buttons: cast[ptr UncheckedArray[TaskDialogButton]](
      if buttons.len > 0: unsafeAddr buttons[0] else: nil),
    defaultButton: defaultId,
    radioButtonCount: radios.len.uint32,
    radioButtons: cast[ptr UncheckedArray[TaskDialogButton]](
      if radios.len > 0: unsafeAddr radios[0] else: nil),
    defaultRadioButton: defaultRadio)
  var btn, radio: int32 = -1
  discard taskDialogIndirect(addr cfg, addr btn, addr radio, nil)
  (button: btn, radio: radio)
