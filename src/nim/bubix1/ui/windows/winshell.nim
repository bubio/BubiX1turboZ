## Shared state for the Windows UI backends: the SDL window's `HWND`, the
## menu bar `nativemenu` attaches to it, and the single hook that catches
## the native messages SDL's own event pump does not turn into `SDL_Event`s
## (`WM_COMMAND` for a menu click, `WM_CLOSE` for the window's own close
## button).
##
## Unlike Linux, the SDL window is not reparented under anything - a native
## Win32 menu bar attaches to the very window SDL created (`SetMenu`), so
## there is only ever one `HWND` and no separate top-level to embed into
## (see hostwindow.nim). That also means there is no second toolkit event
## queue to drain: `SDL_SetWindowsMessageHook` below fires synchronously
## from inside SDL's own `SDL_PumpEvents`, so `hostwindow.pumpEvents` has
## nothing to do (see its stub-like body).

import ./win32

var
  mainHwnd*: HWND
  menuBar*: HMENU
  commandHandler*: proc (id: cint) {.cdecl.}
  closeHandler*: proc () {.cdecl.}
  gdiplusToken: uint
  gdiplusUp = false

proc ensureGdiplus*() =
  ## Brings GDI+ up once, for the PNG decoding the state picker needs
  ## (win32.pngToHBitmap). Never shut down: the process exits with the rest
  ## of the application, and GDI+ has no use after that.
  if gdiplusUp:
    return
  var input = GdiplusStartupInput(gdiplusVersion: 1)
  discard gdiplusStartup(addr gdiplusToken, addr input, nil)
  gdiplusUp = true

proc messageHook(userdata: pointer, hWnd: pointer, message: cuint,
                 wParam: uint64, lParam: int64) {.cdecl.} =
  ## Installed once via `SDL_SetWindowsMessageHook`, ahead of SDL's own
  ## `WndProc`. SDL pumps every window on this thread's message queue, not
  ## only its own (`PeekMessage` with a null `hwnd` filter), so this fires
  ## for the state picker and volume panel windows too - those own their
  ## message handling directly in their WndProc, so anything not addressed
  ## to `mainHwnd` here is left alone. Without this check a button click in
  ## either of those windows would be misread as a menu command carrying an
  ## unrelated tag, and closing either would quit the application.
  if hWnd != mainHwnd:
    return
  case message
  of WmCommand:
    # The low word of wParam is the menu item id when the command came from
    # a menu (lParam is 0 and the high word is 0 in that case, but every id
    # this app hands out is one nativemenu allocated, so no other source of
    # WM_COMMAND competes with it here).
    if commandHandler != nil:
      commandHandler(cint(wParam and 0xffff'u64))
  of WmClose:
    if closeHandler != nil:
      closeHandler()
  else:
    discard

proc sdlSetWindowsMessageHook(callback: proc (userdata: pointer, hWnd: pointer,
    message: cuint, wParam: uint64, lParam: int64) {.cdecl.}, userdata: pointer)
  {.importc: "SDL_SetWindowsMessageHook", cdecl.}

var hookInstalled = false

proc ensureHook*() =
  if not hookInstalled:
    sdlSetWindowsMessageHook(messageHook, nil)
    hookInstalled = true

var registeredClasses: seq[string]

proc registerWindowClass*(name: string, wndProc: WndProc) =
  ## Registers a window class once, for a backend that owns a real window
  ## of its own (the state picker, the volume panel) rather than attaching
  ## to the SDL one - idempotent so a backend can call it on every open
  ## without tracking whether it already has.
  if name in registeredClasses:
    return
  let instance = getModuleHandleW(WideCString(nil))
  # The app's own icon (assets/windows/app.rc, resource id 1) - the same one
  # the exe and the SDL main window already show, so these windows do not
  # fall back to the generic default application icon in their title bar.
  let appIcon = loadIconW(instance, cast[WideCString](cast[pointer](AppIconResourceId)))
  var wc = WndClassExW(
    cbSize: sizeof(WndClassExW).uint32,
    lpfnWndProc: wndProc,
    hInstance: instance,
    hIcon: appIcon,
    hIconSm: appIcon,
    hCursor: loadCursorW(nil, cast[pointer](32512)), # IDC_ARROW
    # The dialog/control face color, not a literal white: these windows are
    # full of native controls (buttons, trackbars, static labels) drawn in
    # the current theme, and a hardcoded white background makes them look
    # like they are floating on top of it instead of belonging to it.
    hbrBackground: cast[HBRUSH](cast[pointer](ColorBtnface + 1)),
    lpszClassName: toWide(name))
  discard registerClassExW(addr wc)
  registeredClasses.add name

proc runModalLoop*(isDone: proc (): bool) =
  ## Blocks the calling thread pumping this thread's whole message queue -
  ## which includes the SDL window's, so the emulator's own message
  ## handling keeps working - until `isDone` says the dialog has closed.
  ## Mirrors gtk_dialog_run's blocking behaviour (ui/statepicker.nim's own
  ## doc comment: "Blocks the caller...").
  var msg: Msg
  while not isDone():
    let r = getMessageW(addr msg, nil, 0, 0)
    if r <= 0:
      break
    discard translateMessage(addr msg)
    discard dispatchMessageW(addr msg)

proc menuHeight*(): int32 =
  ## The height a single-row menu bar adds above the client area, so
  ## `hostwindow.setSize` can size the whole window to fit a picture of a
  ## given size below it - the same job Linux's setSize does by reading the
  ## GTK menu bar's allocated height, except Windows has no widget to
  ## measure: SM_CYMENU is the standard metric for a default, single-line
  ## menu. A caption long enough to wrap the bar to a second row is not
  ## accounted for; this app's menu never gets that long.
  if menuBar != nil: getSystemMetrics(SmCymenu) else: 0'i32
