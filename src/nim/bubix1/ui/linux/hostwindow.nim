## GTK backend for ui/hostwindow.nim.
##
## The SDL window is embedded under the menu bar of the shared GTK top-level
## (gtkshell.nim), so the window operations act on that top-level rather than
## on the SDL window directly. The one exception is the close button: it
## arrives as a GTK delete-event and is turned into an ordinary SDL_QUIT, so
## the application's single shutdown path handles it like every other quit.

import sdl2
import ./gtk3
import ./gtkshell

proc pushQuit() {.cdecl.} =
  var e: Event
  e.kind = QuitEvent
  discard pushEvent(addr e)

proc windowXid(win: WindowPtr): tuple[display: pointer, xid: Window] =
  var info: WMInfo
  getVersion(info.version)
  if getWMInfo(win, info) == False32:
    return (nil, 0.Window)
  # SDL's SDL_SysWMinfo union for X11 begins at the aligned start of WMinfo's
  # padding: Display* first, the Window (XID) one pointer later.
  (cast[ptr pointer](addr info.padding[0])[],
   cast[ptr Window](addr info.padding[8])[])

proc present*(win: WindowPtr, x, y: cint, restorePos: bool) =
  let (display, xid) = windowXid(win)
  if display == nil or xid == 0:
    return
  var w, h: cint
  win.getSize(w, h)
  gtkshell.setDeleteHandler(pushQuit)
  gtkshell.embed(display, xid, w, h, x, y, restorePos)

proc setSize*(win: WindowPtr, width, height: cint) =
  gtkshell.setSize(width, height)

proc setFullscreen*(win: WindowPtr, on: bool) =
  gtkshell.setFullscreen(on)

proc getPosition*(win: WindowPtr, x, y: var cint) =
  gtkshell.getPosition(x, y)

proc destroy*(win: WindowPtr) =
  gtkshell.destroy()
  # destroyWindow, not win.destroy(): this module defines its own `destroy`
  # for WindowPtr, which a bare `win.destroy()` binds to in preference to
  # sdl2's - a silent, unbounded self-recursion. The named entry point avoids
  # the collision.
  win.destroyWindow()

proc pumpEvents*() =
  gtkshell.pump()
