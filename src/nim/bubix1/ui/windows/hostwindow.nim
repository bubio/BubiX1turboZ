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
    discard setMenu(winshell.mainHwnd, winshell.menuBar)
  if restorePos:
    sdl2.setPosition(win, x, y)
  win.showWindow()

proc setSize*(win: WindowPtr, width, height: cint) =
  sdl2.setSize(win, width, height + winshell.menuHeight().cint)

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
