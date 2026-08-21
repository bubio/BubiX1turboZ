## Plain-SDL host window operations.
##
## Unlike the other stub backends this one is not a do-nothing placeholder:
## managing the window is needed on every platform. It is the right backend
## wherever the window is an ordinary top-level SDL window - macOS, and the
## fallback anywhere a native one is not written. Only Linux overrides it, to
## drive the GTK top-level the SDL surface is embedded in.
##
## The calls below read `sdl2.op(win, ...)` rather than `win.op(...)`
## wherever this module exports an operation under the name sdl2 uses for it.
## A bare `win.op(...)` binds to the proc being defined here in preference to
## sdl2's - a silent, unbounded self-recursion the compiler says nothing
## about. Naming the module makes the target explicit.

import sdl2

proc present*(win: WindowPtr, x, y: cint, restorePos: bool) =
  ## The window was created hidden; put it on screen. SDL already placed it
  ## from the arguments to createWindow, so the position is not needed here.
  win.showWindow()

proc setSize*(win: WindowPtr, width, height: cint) =
  sdl2.setSize(win, width, height)

proc setFullscreen*(win: WindowPtr, on: bool) =
  discard sdl2.setFullscreen(win, if on: SDL_WINDOW_FULLSCREEN_DESKTOP else: 0)

proc getPosition*(win: WindowPtr, x, y: var cint) =
  sdl2.getPosition(win, x, y)

proc destroy*(win: WindowPtr) =
  sdl2.destroyWindow(win)

proc pumpEvents*() =
  ## SDL's own event pump is all this platform needs.
  discard
