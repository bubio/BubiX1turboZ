## The window the emulator draws in, as far as the application is concerned:
## show it, resize it to a picture, toggle fullscreen, read its position,
## tear it down, and pump whatever host event loop stands beside SDL's.
##
## On macOS (and any platform without its own backend) these go straight to
## the SDL window. On Linux the SDL surface is embedded under a GTK menu bar,
## so the same operations act on the GTK top-level instead - see
## bubix1/ui/linux/gtkshell.nim. Keeping them behind this facade is what lets
## bubix1turboz.nim manage its one window without naming either platform.

import sdl2

when defined(linux):
  from ./linux/hostwindow as backend import nil
elif defined(windows):
  from ./windows/hostwindow as backend import nil
else:
  from ./stub/hostwindow as backend import nil

proc present*(win: WindowPtr, x, y: cint, restorePos: bool) =
  ## Put the (hidden) window on screen. `x`/`y` are the remembered position
  ## to restore when `restorePos` is true; a backend that lets SDL place the
  ## window from createWindow ignores them.
  backend.present(win, x, y, restorePos)

proc setSize*(win: WindowPtr, width, height: cint) =
  ## Size the window to fit a picture of exactly this size (plus whatever
  ## chrome the platform adds around it).
  backend.setSize(win, width, height)

proc setFullscreen*(win: WindowPtr, on: bool) =
  backend.setFullscreen(win, on)

proc getPosition*(win: WindowPtr, x, y: var cint) =
  ## The window's on-screen position, to remember across runs.
  backend.getPosition(win, x, y)

proc destroy*(win: WindowPtr) =
  backend.destroy(win)

proc pumpEvents*() =
  ## Called once per pass of the application's event loop, for a platform
  ## whose native toolkit has an event queue of its own beside SDL's.
  backend.pumpEvents()
