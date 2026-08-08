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
## Menu policy follows BluePrint/DevelopmentPlan 0.5: the core still has
## USE_FLOPPY_DISK=4 and USE_HARD_DISK, but only floppy drives 1-2 and no
## HDD are exposed here - feature reduction happens at this layer, not in
## the core.

import std/[os, strformat, strutils]
import uing
import sdl2
import sdl2/audio
import bubix1/core
import bubix1/keymap
import bubix1/paths
import bubix1/cocoamenu
import bubix1/recentfiles

const
  ScreenWidth = 640
  ScreenHeight = 400
  WindowHeightAspect = 480 # WINDOW_HEIGHT_ASPECT from vm/x1/x1.h
  RecentSlots = 8 # matches MAX_HISTORY in src/core/config.h

proc fail(msg: string) =
  stderr.writeLine "bubix1turboz: " & msg
  quit 1

proc main() =
  paths.ensureDirsExist()

  # Invariant 1: uing before SDL.
  uing.init()
  if not sdl2.init(INIT_VIDEO or INIT_AUDIO or INIT_EVENTS):
    fail "SDL_Init failed: " & $getError()

  let h = bx1Create(paths.romsDir().cstring, paths.configFilePath().cstring)
  if h == nil:
    fail "bx1_create failed (place BIOS ROMs in " & paths.romsDir() & ")"

  var recent = recentfiles.load(paths.recentFilesPath())
  var running = true
  var paused = false

  proc rememberRecent(path: string) =
    recent = recentfiles.pushFront(recent, path)
    for i in 0 ..< RecentSlots:
      let label = if i < recent.len: &"{i+1}. {recent[i].extractFilename()}" else: &"{i+1}. (empty)"
      discard cocoamenu.setMenuItemTitle("File", &"{i+1}. ", label)

  proc openFloppyAt(parent: Window, drv: int) =
    let path = uing.openFile(parent)
    if path.len > 0:
      let inserted = bx1OpenFloppy(h, drv.cint, path.cstring, 0)
      if inserted != 0:
        rememberRecent(path)

  var win: Window

  # --- File menu ---
  let fileMenu = newMenu "File"
  fileMenu.addItem("Open Floppy 1...", proc (sender: MenuItem, w: Window) =
    openFloppyAt(w, 0))
  fileMenu.addItem("Open Floppy 2...", proc (sender: MenuItem, w: Window) =
    openFloppyAt(w, 1))
  fileMenu.addItem("Eject Floppy 1", proc (sender: MenuItem, w: Window) =
    bx1CloseFloppy(h, 0))
  fileMenu.addItem("Eject Floppy 2", proc (sender: MenuItem, w: Window) =
    bx1CloseFloppy(h, 1))
  fileMenu.addSeparator()
  fileMenu.addItem("Open Tape...", proc (sender: MenuItem, w: Window) =
    let path = uing.openFile(w)
    if path.len > 0:
      if bx1OpenTape(h, path.cstring, 1) != 0:
        rememberRecent(path))
  fileMenu.addItem("Eject Tape", proc (sender: MenuItem, w: Window) =
    bx1CloseTape(h))
  fileMenu.addSeparator()
  # Fixed slots (not a real submenu - uing/libui-ng menus cannot nest).
  # Titles are rewritten in place via cocoamenu.setMenuItemTitle as the
  # recent list changes; "N. " is the stable prefix used to find them.
  for i in 0 ..< RecentSlots:
    let idx = i
    let label = if idx < recent.len: &"{idx+1}. {recent[idx].extractFilename()}" else: &"{idx+1}. (empty)"
    fileMenu.addItem(label, proc (sender: MenuItem, w: Window) =
      if idx < recent.len:
        let path = recent[idx]
        let ext = path.splitFile().ext.toLowerAscii()
        if ext in [".tap", ".cmt", ".t88", ".wav"]:
          discard bx1OpenTape(h, path.cstring, 1)
        else:
          discard bx1OpenFloppy(h, 0, path.cstring, 0))
  fileMenu.addSeparator()
  fileMenu.addQuitItem(proc (): bool =
    running = false
    if win != nil:
      win.destroy()
      win = nil
    true)

  # --- Machine menu ---
  let machineMenu = newMenu "Machine"
  machineMenu.addItem("Reset", proc (sender: MenuItem, w: Window) =
    bx1Reset(h))
  machineMenu.addItem("Special Reset (NEW ON)", proc (sender: MenuItem, w: Window) =
    bx1SpecialReset(h))
  machineMenu.addCheckItem("Pause", proc (sender: MenuItem, w: Window) =
    paused = sender.checked)

  # --- State menu ---
  let stateMenu = newMenu "State"
  stateMenu.addItem("Save State...", proc (sender: MenuItem, w: Window) =
    let path = uing.saveFile(w)
    if path.len > 0:
      discard bx1SaveState(h, path.cstring))
  stateMenu.addItem("Load State...", proc (sender: MenuItem, w: Window) =
    let path = uing.openFile(w)
    if path.len > 0:
      discard bx1LoadState(h, path.cstring))

  # --- Settings menu ---
  # Manual "radio button" behavior: each group is a set of check items
  # where selecting one clears the others. uing/libui-ng has no native
  # radio-item type.
  let settingsMenu = newMenu "Settings"
  var monitorItems: array[2, MenuItem]
  let monitorLabels = ["Monitor: 15kHz", "Monitor: 24kHz"]
  for i in 0 ..< 2:
    let idx = i
    monitorItems[i] = settingsMenu.addCheckItem(monitorLabels[i], proc (sender: MenuItem, w: Window) =
      bx1SetMonitorType(h, idx.cint)
      for j in 0 ..< 2:
        monitorItems[j].checked = (j == idx))
  settingsMenu.addSeparator()
  var soundItems: array[3, MenuItem]
  let soundLabels = ["Sound: PSG Only", "Sound: +1 FM Board (CZ-8BS1)", "Sound: +2 FM Boards (CZ-8BS1)"]
  for i in 0 ..< 3:
    let idx = i
    soundItems[i] = settingsMenu.addCheckItem(soundLabels[i], proc (sender: MenuItem, w: Window) =
      bx1SetSoundType(h, idx.cint)
      for j in 0 ..< 3:
        soundItems[j].checked = (j == idx))
  settingsMenu.addSeparator()
  let scanlineItem = settingsMenu.addCheckItem("Scanline Effect", proc (sender: MenuItem, w: Window) =
    # libui-ng check items do not auto-toggle on click - unlike the
    # monitor/sound radio groups above (which always assign `.checked`
    # explicitly for every item in the group), a lone toggle has to flip
    # its own state by hand, or it reads back whatever it was last set to.
    sender.checked = not sender.checked
    bx1SetScanLine(h, sender.checked.cint))

  win = newWindow("BubiX1turboZ", 320, 80, true)
  win.margined = true
  let box = newVerticalBox(true)
  box.add newLabel("BubiX1turboZ")
  win.child = box
  win.onClosing = proc (sender: Window): bool =
    running = false
    win = nil
    true
  win.show()

  # Reflect the config loaded by bx1_create (either from config.ini or
  # built-in defaults) in the initial checkmarks.
  let curMonitor = bx1GetMonitorType(h)
  if curMonitor >= 0 and curMonitor < 2:
    monitorItems[curMonitor].checked = true
  let curSound = bx1GetSoundType(h)
  if curSound >= 0 and curSound < 3:
    soundItems[curSound].checked = true
  scanlineItem.checked = bx1GetScanLine(h) != 0

  # libui-ng attaches no keyboard shortcuts to any menu item (phase 1.2);
  # wire up the standard macOS ones by hand. Must happen after win.show()
  # - NSApp has no main menu before that.
  discard cocoamenu.setMenuShortcut("", "Quit", "q")
  discard cocoamenu.setMenuShortcut("Machine", "Reset", "r")
  discard cocoamenu.setMenuShortcut("State", "Save State", "s")
  discard cocoamenu.setMenuShortcut("State", "Load State", "l")

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

    if not paused:
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

  bx1SaveConfig(h, paths.configFilePath().cstring)
  recentfiles.save(paths.recentFilesPath(), recent)

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
