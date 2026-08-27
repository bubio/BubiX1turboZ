## Win32 backend for ui/hostwindow.nim.
##
## The menu bar attaches directly to the window SDL created (`SetMenu`),
## rather than to a separate top-level the SDL surface is embedded under as
## on Linux - see winshell.nim. So most operations here differ from the
## plain-SDL stub only by accounting for the menu bar's height, and by
## hiding the menu in fullscreen (matching Linux, where the bar is likewise
## hidden rather than left to eat into the picture - see gtkshell.setFullscreen).

import sdl2
import ./win32
import ./winshell

proc pushQuit() {.cdecl.} =
  var e: Event
  e.kind = QuitEvent
  discard pushEvent(addr e)

proc windowHwnd(win: WindowPtr): HWND =
  var info: WMInfo
  getVersion(info.version)
  if getWMInfo(win, info) == False32:
    return nil
  # SDL's SDL_SysWMinfo union for Windows begins, right after the version
  # and subsystem fields, with `HWND window` - the same alignment trick the
  # Linux backend uses for its own union member (see its windowXid).
  cast[ptr HWND](addr info.padding[0])[]

proc present*(win: WindowPtr, x, y: cint, restorePos: bool) =
  winshell.mainHwnd = windowHwnd(win)
  if winshell.mainHwnd == nil:
    win.showWindow()
    return
  winshell.closeHandler = pushQuit
  winshell.ensureHook()
  # nativemenu.installMenuBar runs well before this (see bubix1turboz.nim),
  # building the HMENU with no window to attach it to yet; this is the
  # first point a real HWND exists to give it to.
  if winshell.menuBar != nil:
    # The client area SDL sized to fit the picture, captured before the menu
    # can take a slice out of it. SetMenu does not grow the window to keep
    # that area: it makes room for the bar out of the client rect instead
    # (confirmed empirically - GetClientRect read straight after SetMenu
    # comes back one menu bar short of what SDL_CreateWindow was asked for).
    # Left uncorrected, every frame stretches the guest picture into a client
    # area a few percent shorter than intended, which a nearest-neighbour
    # scale turns into unevenly doubled and dropped rows.
    var wanted: win32.Rect
    discard getClientRect(winshell.mainHwnd, addr wanted)
    discard setMenu(winshell.mainHwnd, winshell.menuBar)
    # Asking SDL for that same client size again is what restores it:
    # SDL_SetWindowSize sizes the *client* area and re-reads GetMenu on every
    # call, so unlike the size SDL_CreateWindow was given, it does allow for
    # the bar. Handing it back the measured rectangle - rather than the
    # shrunken one plus a menu height from GetSystemMetrics - keeps this
    # independent of how tall the bar actually turned out to be, which
    # SM_CYMENU does not report correctly on a scaled display (it is not
    # DPI-aware, and assets/windows/app.manifest asks for PerMonitorV2).
    sdl2.setSize(win, (wanted.right - wanted.left).cint,
                 (wanted.bottom - wanted.top).cint)
  if restorePos:
    sdl2.setPosition(win, x, y)
  win.showWindow()

proc setSize*(win: WindowPtr, width, height: cint) =
  ## `height` reaches SDL unadjusted, menu bar or not: SDL_SetWindowSize
  ## sizes the client area and already allows for an attached menu, which it
  ## looks up (GetMenu) on every call - so it stays right across the
  ## setFullscreen below detaching and re-attaching the bar.
  ##
  ## Adding a menu height here as well was a bug: it made the client area one
  ## menu bar too tall on every window-scale change, so 400 guest rows were
  ## stretched over 420 or 820 and the extra rows landed as an uneven scatter
  ## of doubled scanlines. The window was correct until the first such change
  ## because present() above is what sizes it at startup.
  sdl2.setSize(win, width, height)

proc setFullscreen*(win: WindowPtr, on: bool) =
  # The menu bar is hidden rather than left in place: it would otherwise
  # take a slice of the screen out of the fullscreen picture, which is not
  # what "fullscreen" means on any of this app's other platforms.
  if winshell.mainHwnd != nil:
    discard setMenu(winshell.mainHwnd, if on: nil else: winshell.menuBar)
  discard sdl2.setFullscreen(win, if on: SDL_WINDOW_FULLSCREEN_DESKTOP else: 0)

proc getPosition*(win: WindowPtr, x, y: var cint) =
  sdl2.getPosition(win, x, y)

proc destroy*(win: WindowPtr) =
  sdl2.destroyWindow(win)

proc pumpEvents*() =
  ## Nothing to do: the menu bar lives on the same HWND and message queue
  ## SDL already pumps every call to SDL_PollEvent, unlike Linux's separate
  ## GTK top-level and its own event queue. winshell's message hook fires
  ## synchronously from inside that same pump.
  discard
