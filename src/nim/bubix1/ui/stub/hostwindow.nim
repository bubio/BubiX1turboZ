## Plain-SDL host window operations.
##
## Unlike the other stub backends this one is not a do-nothing placeholder:
## managing the window is needed on every platform. It is the right backend
## wherever the window is an ordinary top-level SDL window - macOS, and the
## fallback anywhere a native one is not written. Only Linux overrides it, to
## drive the GTK top-level the SDL surface is embedded in.

import sdl2

proc present*(win: WindowPtr, x, y: cint, restorePos: bool) =
  ## The window was created hidden; put it on screen. SDL already placed it
  ## from the arguments to createWindow, so the position is not needed here.
  win.showWindow()

proc setSize*(win: WindowPtr, width, height: cint) =
  win.setSize(width, height)

proc setFullscreen*(win: WindowPtr, on: bool) =
  discard win.setFullscreen(if on: SDL_WINDOW_FULLSCREEN_DESKTOP else: 0)

proc getPosition*(win: WindowPtr, x, y: var cint) =
  win.getPosition(x, y)

proc destroy*(win: WindowPtr) =
  # destroyWindow, not win.destroy(): this module defines its own `destroy`
  # for WindowPtr, which a bare `win.destroy()` binds to in preference to
  # sdl2's - a silent, unbounded self-recursion. The named entry point avoids
  # the collision.
  win.destroyWindow()

proc pumpEvents*() =
  ## SDL's own event pump is all this platform needs.
  discard
