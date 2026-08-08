## BubiX1turboZ application entry point.
##
## Single window, single-threaded main loop (phase 5 milestone; moving
## emulation to its own thread is a follow-up once this is verified stable
## - see docs/dev/DevelopmentPlan.md phase 5).
##
## Window ownership follows the phase 1.2 spike's proven design (案 B):
## uing owns the menu bar, SDL2 owns the emulation surface. Two invariants
## from that spike are load-bearing and must not be reordered:
##   1. `uing.init()` must run before `sdl2.init()`, or SDL's Cocoa
##      backend claims `NSApp` first and libui's window/menu/text-edit
##      event handling silently breaks (looks fine until you type).
##   2. Each loop iteration must drain `sdl2.pollEvent` before calling
##      `uing.mainStep`, or SDL never observes keyboard events - both
##      libraries pump the same Cocoa event queue with
##      `nextEventMatchingMask`, and whichever runs first wins.
##
## ROM/config path handling here is a placeholder (a required CLI arg).
## docs/dev/DevelopmentPlan.md phase 6 replaces this with a proper
## platform-conventions path module (~/Library/Application Support/...
## on macOS) - do not build that logic here.

import std/[os, strformat]
import uing
import sdl2
import sdl2/audio
import bubix1/core
import bubix1/keymap

const
  ScreenWidth = 640
  ScreenHeight = 400
  WindowHeightAspect = 480 # WINDOW_HEIGHT_ASPECT from vm/x1/x1.h

proc fail(msg: string) =
  stderr.writeLine "bubix1turboz: " & msg
  quit 1

proc main() =
  let args = commandLineParams()
  if args.len < 1:
    fail "usage: bubix1turboz <rom_dir>  (temporary until phase 6's path module lands)"
  let romDir = args[0]

  # Invariant 1: uing before SDL.
  uing.init()
  if not sdl2.init(INIT_VIDEO or INIT_AUDIO or INIT_EVENTS):
    fail "SDL_Init failed: " & $getError()

  let h = bx1Create(romDir.cstring)
  if h == nil:
    fail "bx1_create failed (check rom_dir contains IPLROM.X1T etc.)"
  if args.len >= 2:
    let inserted = bx1OpenFloppy(h, 0, args[1].cstring, 0)
    echo &"floppy insert: {inserted}"

  var win: Window
  let fileMenu = newMenu "File"
  fileMenu.addQuitItem(proc (): bool =
    if win != nil:
      win.destroy()
      win = nil
    true)
  win = newWindow("BubiX1turboZ", 320, 80, true)
  win.margined = true
  let box = newVerticalBox(true)
  box.add newLabel("BubiX1turboZ")
  win.child = box
  var running = true
  win.onClosing = proc (sender: Window): bool =
    running = false
    win = nil
    true
  win.show()

  # Nearest-neighbor scaling: X1 text/graphics are drawn at exact pixel
  # boundaries, and linear filtering (SDL's default for the accelerated
  # renderer) blurs and distorts character glyphs when the 640x400
  # texture is stretched to the aspect-corrected window.
  discard setHint("SDL_RENDER_SCALE_QUALITY", "0")

  let sdlWin = createWindow("BubiX1turboZ - Screen", SDL_WINDOWPOS_UNDEFINED,
    SDL_WINDOWPOS_UNDEFINED, ScreenWidth, WindowHeightAspect, SDL_WINDOW_SHOWN)
  if sdlWin == nil:
    fail "SDL_CreateWindow failed: " & $getError()
  let renderer = createRenderer(sdlWin, -1, Renderer_Accelerated)
  if renderer == nil:
    fail "SDL_CreateRenderer failed: " & $getError()
  let texture = renderer.createTexture(SDL_PIXELFORMAT_ARGB8888,
    SDL_TEXTUREACCESS_STREAMING, ScreenWidth, ScreenHeight)
  if texture == nil:
    fail "SDL_CreateTexture failed: " & $getError()
  # Alpha comes back as 0 from the core (see docs/dev/DevelopmentPlan.md
  # 1.4); blending it would make the whole picture transparent.
  discard texture.setTextureBlendMode(BlendMode_None)

  # Audio: must open at the core's *actual* rate, not a requested one
  # (X1turboZ overrides the "48000Hz" table slot to 62500Hz - see
  # bx1_get_actual_sound_rate's doc comment).
  let soundRate = bx1GetActualSoundRate(h)
  var desired: AudioSpec
  desired.freq = soundRate.cint
  desired.format = AUDIO_S16LSB
  desired.channels = 2
  desired.samples = 1024
  desired.callback = proc (userdata: pointer; stream: ptr uint8; len: cint) {.cdecl.} =
    let handle = cast[Bx1Handle](userdata)
    let framesWanted = len div 4 # stereo int16
    let dst = cast[ptr int16](stream)
    let got = bx1PullAudio(handle, dst, framesWanted.cint)
    if got < framesWanted:
      # SDL does not zero the buffer for us; an underrun must be silence,
      # not whatever was left in the device buffer from a prior callback.
      let gotBytes = got * 4
      zeroMem(cast[pointer](cast[uint](stream) + gotBytes.uint), len.int - gotBytes)
  desired.userdata = cast[pointer](h)
  var obtained: AudioSpec
  let audioDev = openAudioDevice(nil, 0.cint, addr desired, addr obtained, 0)
  if audioDev == 0:
    fail "SDL_OpenAudioDevice failed: " & $getError()
  # obtained.freq may legitimately differ from desired.freq if the OS
  # resampled; bx1_pull_audio always hands back soundRate-rate samples
  # regardless, so this is only relevant if SDL's own resampling quality
  # ever becomes a concern.
  echo &"audio device opened at {obtained.freq}Hz (requested {soundRate}Hz)"
  pauseAudioDevice(audioDev, 0)

  let targetBufferedFrames = cint(soundRate.float * 0.1) # ~100ms latency

  uing.mainSteps()

  var ev = sdl2.defaultEvent
  var runFrameSafetyCounter = 0
  while running:
    # Invariant 2: SDL first, then libui.
    while pollEvent(ev):
      case ev.kind
      of QuitEvent:
        running = false
      of KeyDown:
        let vk = keymap.toVk(ev.key.keysym.scancode)
        if vk != 0:
          bx1KeyDown(h, vk, ev.key.repeat.cint)
      of KeyUp:
        let vk = keymap.toVk(ev.key.keysym.scancode)
        if vk != 0:
          bx1KeyUp(h, vk)
      of WindowEvent:
        case ev.window.event
        of WindowEvent_Close:
          running = false
        of WindowEvent_FocusLost:
          # Without this, a key held down when focus moves away from the
          # SDL window would otherwise never see its key-up event and
          # reads to the guest as a permanently stuck key.
          for vk in keymap.scancodeToVk:
            if vk != 0:
              bx1KeyUp(h, vk)
        else:
          discard
      else:
        discard
    discard uing.mainStep(0)
    if win == nil and running:
      # uing's Quit menu item destroys the window without necessarily
      # clearing `running` via onClosing; addQuitItem's own callback
      # above does that already, so this is just documentation of the
      # invariant that `win == nil` implies shutdown is in progress.
      discard

    # Audio-clock-driven pacing (docs/dev/DevelopmentPlan.md architecture
    # decision 4): keep advancing the VM while the ring buffer the SDL
    # callback drains from is below the target latency.
    runFrameSafetyCounter = 0
    while bx1GetBufferedAudioFrames(h) < targetBufferedFrames:
      discard bx1RunFrame(h)
      inc runFrameSafetyCounter
      if runFrameSafetyCounter > 1000:
        # Should be unreachable in normal operation; bail out rather than
        # freeze the UI if the VM ever stops producing audio progress.
        break

    bx1DrawScreen(h)
    var pixels: pointer
    var pitch: cint
    if texture.lockTexture(nil, addr pixels, addr pitch):
      let fb = bx1GetFramebuffer(h)
      let srcStride = ScreenWidth * 4
      if pitch.int == srcStride:
        copyMem(pixels, fb, ScreenHeight * srcStride)
      else:
        for y in 0 ..< ScreenHeight:
          copyMem(cast[pointer](cast[uint](pixels) + uint(y * pitch.int)),
                  cast[pointer](cast[uint](fb) + uint(y * srcStride)), srcStride)
      texture.unlockTexture()
    renderer.clear()
    renderer.copy(texture, nil, nil)
    renderer.present()

  closeAudioDevice(audioDev)
  texture.destroy()
  renderer.destroy()
  sdlWin.destroy()
  sdl2.quit()
  if win != nil:
    win.destroy()
  uing.uninit()
  bx1Destroy(h)

main()
