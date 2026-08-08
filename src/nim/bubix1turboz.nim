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

import std/[os, strformat]
import uing
import sdl2
import sdl2/audio
import bubix1/core
import bubix1/keymap
import bubix1/paths
import bubix1/cocoamenu
import bubix1/recentfiles
import bubix1/archive
import bubix1/ankfont

const
  ScreenWidth = 640
  ScreenHeight = 400
  # A status bar bolted onto a second floating window is easy to lose
  # behind (or below) the main emulator window - confirmed the hard way
  # when a first attempt at this placed the window at (0, 1308) on a
  # tall display and nobody noticed it. Drawing the lamps into a strip
  # at the bottom of the emulator's own window is what "ステータスバー"
  # means on macOS anyway: part of the one window, not a second one.
  StatusBarHeight = 24
  WindowHeight = ScreenHeight + StatusBarHeight
  RecentSlots = 8 # matches MAX_HISTORY in src/core/config.h
  DiskSlots = 16 # fixed slots for the D88 multi-bank picker (phase 7)
  # .nimble is the single source of truth for the app version; the build
  # script reads it and passes it in via -d so it isn't hardcoded twice.
  # The fallback only matters for ad-hoc `nim c` runs outside the script.
  appVersion {.strdefine.} = "0.0.0-dev"

# SDL_DROPFILE hands ownership of `event.drop.file` to the caller; the
# Nim sdl2 binding does not wrap SDL_free itself (see its DropEventObj
# doc comment), so it is declared directly here.
proc sdlFreeStr(mem: cstring) {.importc: "SDL_free", cdecl.}

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

  # Drive 1's currently-mounted D88 path, kept so the Disk menu (bank
  # picker below) can re-issue bx1OpenFloppy with a different bank index
  # without the caller having to remember the path itself. Only drive 1
  # is exposed here: commercial multi-scenario D88s are conventionally
  # the main game disk, which goes in drive 1, while drive 2 (if used at
  # all) is a plain single-image save/data disk.
  var driveOnePath = ""

  proc updateDiskMenu() =
    let count = bx1GetFloppyBankCount(h, 0)
    for i in 0 ..< DiskSlots:
      let show = i < count
      let label = if show: &"{i+1}. " & $bx1GetFloppyBankName(h, 0, i.cint) else: &"{i+1}. (unused)"
      discard cocoamenu.setMenuItemTitle("Disk", &"{i+1}. ", label)
      discard cocoamenu.setMenuItemEnabled("Disk", &"{i+1}. ", show)

  proc mountFloppy(drv: int, path: string, bank: int): bool =
    result = bx1OpenFloppy(h, drv.cint, path.cstring, bank.cint) != 0
    if result and drv == 0:
      driveOnePath = path
      updateDiskMenu()

  proc openFloppyAt(parent: Window, drv: int) =
    let path = uing.openFile(parent)
    if path.len > 0 and mountFloppy(drv, path, 0):
      rememberRecent(path)

  proc loadMedia(path: string) =
    ## Single entry point for anything that can end up mounted: a bare
    ## image, a 7z/zip archive, or an m3u/m3u8 playlist. Used by drag &
    ## drop, Recent Files, and the "Open Disk or Archive..." menu item, so
    ## extension handling lives in exactly one place (archive.classify)
    ## instead of being re-decided at each call site.
    var resolved: seq[string]
    try:
      resolved = archive.resolveMedia(path)
    except IOError as e:
      stderr.writeLine "bubix1turboz: " & e.msg
      return
    var drv = 0
    var mounted = false
    for p in resolved:
      case archive.classify(p)
      of archive.mkTape:
        if bx1OpenTape(h, p.cstring, 1) != 0:
          mounted = true
      of archive.mkFloppy:
        if drv < 2 and mountFloppy(drv, p, 0):
          mounted = true
          inc drv
      of archive.mkArchive, archive.mkPlaylist, archive.mkUnknown:
        discard
    if mounted:
      # The archive/playlist itself is what the user thinks of as "the
      # game" and what they will look for again in Recent Files - not
      # the extracted cache path or an individual disk inside it.
      rememberRecent(path)
      bx1Reset(h)

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
  fileMenu.addItem("Open Disk or Archive...", proc (sender: MenuItem, w: Window) =
    let path = uing.openFile(w)
    if path.len > 0:
      loadMedia(path))
  fileMenu.addSeparator()
  # Fixed slots (not a real submenu - uing/libui-ng menus cannot nest).
  # Titles are rewritten in place via cocoamenu.setMenuItemTitle as the
  # recent list changes; "N. " is the stable prefix used to find them.
  # The action is built by a proc, not written inline in the loop body:
  # a for-loop-scoped `let idx` is one shared binding across every
  # closure created in that loop, so every slot's callback would silently
  # fire with whichever index the loop last reached (confirmed with an
  # isolated repro - every slot opened the same file regardless of which
  # one was clicked). A proc parameter gets a fresh binding per call.
  proc makeRecentAction(idx: int): proc (sender: MenuItem, w: Window) =
    proc (sender: MenuItem, w: Window) =
      if idx < recent.len:
        loadMedia(recent[idx])
  for i in 0 ..< RecentSlots:
    let label = if i < recent.len: &"{i+1}. {recent[i].extractFilename()}" else: &"{i+1}. (empty)"
    fileMenu.addItem(label, makeRecentAction(i))
  fileMenu.addSeparator()
  fileMenu.addQuitItem(proc (): bool =
    running = false
    if win != nil:
      win.destroy()
      win = nil
    true)
  # libui-ng places this in the application menu (About BubiX1turboZ)
  # regardless of which Menu it is added to - like addQuitItem above.
  # Without an explicit addAboutItem call, libui-ng still shows the
  # placeholder item but wires no action to it, which Cocoa then reports
  # as permanently disabled (no target-action pair to validate).
  fileMenu.addAboutItem(proc (sender: MenuItem, w: Window) =
    uing.msgBox(w, "BubiX1turboZ " & appVersion,
      "Multi-platform Sharp X1 turbo Z emulator.\n" &
      "Emulation core: Common Source Code Project's eX1turboZ (GPL-2.0-or-later)."))

  # --- Machine menu ---
  let machineMenu = newMenu "Machine"
  machineMenu.addItem("Reset", proc (sender: MenuItem, w: Window) =
    bx1Reset(h))
  machineMenu.addItem("Special Reset (NEW ON)", proc (sender: MenuItem, w: Window) =
    bx1SpecialReset(h))
  machineMenu.addCheckItem("Pause", proc (sender: MenuItem, w: Window) =
    paused = sender.checked)

  # --- Disk menu (D88 multi-bank picker for drive 1) ---
  # libui-ng cannot add/remove menu items at runtime (phase 6), and the
  # bank count is only known after an image is mounted (the core reads it
  # from the file), so this preallocates fixed slots exactly like Recent
  # Files above and starts them all disabled; updateDiskMenu() renames
  # and enables/disables them once drive 1 actually holds a multi-bank
  # image.
  let diskMenu = newMenu "Disk"
  proc makeDiskBankAction(idx: int): proc (sender: MenuItem, w: Window) =
    # A plain `for`-loop-scoped closure would have every slot's callback
    # share the *same* `idx` binding (all firing with the loop's final
    # value - confirmed with an isolated repro while tracking down why
    # every slot picked the same bank). Wrapping it in a proc call forces
    # a fresh binding per slot, since `idx` is now a parameter.
    proc (sender: MenuItem, w: Window) =
      if driveOnePath.len > 0:
        discard mountFloppy(0, driveOnePath, idx)
  for i in 0 ..< DiskSlots:
    diskMenu.addItem(&"{i+1}. (unused)", makeDiskBankAction(i))

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
  # Labels and index order match the original Windows app's own
  # Device > Display menu (confirmed by side-by-side comparison - see
  # docs/dev/DevelopmentPlan.md phase 5's resolved open item). Index 1
  # ("Standard") is the one that renders text correctly; index 0 ("High
  # Resolution") has a pre-existing glyph rendering bug present in the
  # original app too, not something introduced by this port.
  let monitorLabels = ["Monitor: High Resolution", "Monitor: Standard"]
  # Wrapped in a proc, not written directly in the loop body below: a
  # for-loop-scoped `let idx` is still one shared binding across every
  # closure created in that loop (confirmed with an isolated repro), so
  # every item would silently apply whichever index the loop ended on.
  # A proc parameter gets a fresh binding per call instead.
  proc makeMonitorAction(idx: int): proc (sender: MenuItem, w: Window) =
    proc (sender: MenuItem, w: Window) =
      bx1SetMonitorType(h, idx.cint)
      for j in 0 ..< 2:
        monitorItems[j].checked = (j == idx)
  for i in 0 ..< 2:
    monitorItems[i] = settingsMenu.addCheckItem(monitorLabels[i], makeMonitorAction(i))
  settingsMenu.addSeparator()
  var soundItems: array[3, MenuItem]
  let soundLabels = ["Sound: PSG Only", "Sound: +1 FM Board (CZ-8BS1)", "Sound: +2 FM Boards (CZ-8BS1)"]
  proc makeSoundAction(idx: int): proc (sender: MenuItem, w: Window) =
    proc (sender: MenuItem, w: Window) =
      bx1SetSoundType(h, idx.cint)
      for j in 0 ..< 3:
        soundItems[j].checked = (j == idx)
  for i in 0 ..< 3:
    soundItems[i] = settingsMenu.addCheckItem(soundLabels[i], makeSoundAction(i))
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
    # Returning true here segfaulted in testing: uing's onClosingWrapper
    # (uing.nim) calls `controlDestroy(w.impl)` synchronously whenever
    # this callback returns true - i.e. it destroys the NSWindow from
    # inside its own "window should close" delegate callback, which
    # crashes. (uing's own default onClosing, installed by newWindow
    # before this overrides it, sidesteps that by calling quitAll()
    # instead of destroying anything - but quitAll() is Nim's
    # system.quit(), a hard process exit that would skip
    # bx1SaveConfig/recentfiles.save below.)
    #
    # Returning false tells libui-ng not to touch the window itself;
    # `running = false` alone drives the same graceful shutdown path as
    # the SDL window's WindowEvent_Close and the Quit menu item, whose
    # post-loop cleanup (`if win != nil: win.destroy()`) destroys this
    # window safely once control has unwound back to plain Nim code,
    # outside any Cocoa delegate callback.
    running = false
    false
  win.show()

  # A botched NSApp modal session from *any* Open/Save dialog (uing's
  # openFile/saveFile - reproduced with the stock File > Open Floppy
  # flow, not specific to phase 7's additions) can otherwise leave every
  # menu item in the app permanently disabled after first use of a
  # dialog. See cocoamenu.m's bx1_menu_disable_autoenable_all for the
  # full mechanism. Must run after win.show() - NSApp has no main menu
  # before that.
  cocoamenu.disableAutoEnableAll()

  # Reflect the config loaded by bx1_create (either from config.ini or
  # built-in defaults) in the initial checkmarks.
  let curMonitor = bx1GetMonitorType(h)
  if curMonitor >= 0 and curMonitor < 2:
    monitorItems[curMonitor].checked = true
  let curSound = bx1GetSoundType(h)
  if curSound >= 0 and curSound < 3:
    soundItems[curSound].checked = true
  scanlineItem.checked = bx1GetScanLine(h) != 0
  updateDiskMenu() # disables all slots; nothing is mounted yet

  # libui-ng attaches no keyboard shortcuts to any menu item (phase 1.2);
  # wire up the standard macOS ones by hand. Must happen after win.show()
  # - NSApp has no main menu before that.
  discard cocoamenu.setMenuShortcut("", "Quit", "q")
  discard cocoamenu.setMenuShortcut("Machine", "Reset", "r")
  discard cocoamenu.setMenuShortcut("State", "Save State", "s")
  discard cocoamenu.setMenuShortcut("State", "Load State", "l")

  # Nearest-neighbor scaling: X1 text/graphics are drawn at exact pixel
  # boundaries, and linear filtering (SDL's default for the accelerated
  # renderer) blurs glyphs on any non-integer window resize.
  discard setHint("SDL_RENDER_SCALE_QUALITY", "0")

  # Native 640x400, not the core's own WINDOW_HEIGHT_ASPECT=480 (which
  # stretches the picture to approximate the X1's non-square CRT pixels,
  # like the original Windows app's default window does). Per user
  # feedback the stretched look reads as distorted on a modern display;
  # this project prioritizes a clean, square-pixel picture over
  # replicating that CRT-accurate aspect ratio.
  let sdlWin = createWindow("BubiX1turboZ - Screen", SDL_WINDOWPOS_UNDEFINED,
    SDL_WINDOWPOS_UNDEFINED, ScreenWidth, WindowHeight, SDL_WINDOW_SHOWN)
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

  # The status bar prints with the machine's own 8x8 ANK glyphs; see
  # ankfont.nim for why this rather than SDL_ttf. A missing font ROM leaves
  # `ready == false` and every draw becomes a no-op, so the lamps still work.
  var font = ankfont.load(renderer, paths.romsDir())
  if not font.ready:
    stderr.writeLine "bubix1turboz: no 8x8 font ROM in " & paths.romsDir() &
      "; status bar text disabled"

  uing.mainSteps()

  var ev = sdl2.defaultEvent
  var runFrameSafetyCounter = 0
  var tapeStatus = ""
  var fpsDisplay = 0
  var drawnFrames = 0
  var lastFpsTicks = getTicks()
  var lastStatusTicks = lastFpsTicks
  const StatusPollMs = 200'u32
  # X1turboZ runs at FRAMES_PER_SEC 61.94 (vm/x1/x1.h), which is not a whole
  # number of milliseconds - hence a float accumulator rather than an
  # integer interval, so the error does not compound into visible drift.
  const FrameIntervalMs = 1000.0 / 61.94
  var nextDrawTicks = lastFpsTicks.float
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
      of DropFile:
        # BluePrint line 32: a drop mounts and resets automatically,
        # unlike the File-menu open actions (which leave a running game
        # alone in case the user is hot-swapping a disk mid-session).
        let raw = ev.drop.file
        if raw != nil:
          loadMedia($raw)
          sdlFreeStr(raw)
      else:
        discard
    discard uing.mainStep(0)

    # Audio-clock-driven pacing (docs/dev/DevelopmentPlan.md architecture
    # decision 4): keep advancing the VM while the ring buffer the SDL
    # callback drains from is below the target latency.
    if not paused:
      runFrameSafetyCounter = 0
      while bx1GetBufferedAudioFrames(h) < targetBufferedFrames:
        discard bx1RunFrame(h)
        inc runFrameSafetyCounter
        if runFrameSafetyCounter > 1000:
          # Should be unreachable in normal operation; bail out rather than
          # freeze the UI if the VM ever stops producing audio progress.
          break

    # Drawing runs on its own clock rather than "once per pass through this
    # loop". Neither of the obvious alternatives works: presenting every
    # pass spins as fast as the GPU accepts frames (measured ~170/sec on a
    # 61.94Hz machine, burning a core to show nothing new), and presenting
    # only when the VM advanced gives ~10/sec, because the pacing loop above
    # advances the VM in bursts - the core synthesizes a whole sound_latency
    # window (100ms, ~6 frames) per create_sound call, then nothing until
    # the ring buffer drains. Pacing here on wall time decouples the two,
    # which is also how the original app works (its VM is paced by the
    # DirectSound cursor while WM_PAINT redraws on its own timer).
    let frameTicks = getTicks()
    if frameTicks.float < nextDrawTicks:
      delay(1)
    else:
      nextDrawTicks += FrameIntervalMs
      if nextDrawTicks < frameTicks.float:
        # Fell far enough behind (a stall, or the window was occluded) that
        # catching up would mean a burst of back-to-back presents. Resync
        # to now instead.
        nextDrawTicks = frameTicks.float + FrameIntervalMs
      # Presenting continues while paused (the guest's last frame stays on
      # screen and the status bar stays live); only the VM's own rendering
      # stops, since there is nothing new for it to draw.
      if not paused:
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
      var screenDst = rect(0.cint, 0.cint, ScreenWidth.cint, ScreenHeight.cint)
      renderer.copy(texture, nil, addr screenDst)

      # Status bar: drawn directly into the emulator's own window, not as a
      # separate GUI window - a second floating window is easy to lose
      # behind the main one (confirmed: an earlier attempt placed it
      # off-screen and nobody noticed). Layout and wording mirror the
      # original Windows app's own status bar (winmain.cpp's
      # update_status_bar): "FD:" followed by one lamp per drive, a gap,
      # then "CMT:" and the deck's own message string. All of it comes
      # from the vendored core unmodified. No HDD section: this app has no
      # UI path to mount a hard disk (BluePrint/CLAUDE.md - commercial X1
      # games did not use one), so it would only ever read as idle.
      #
      # The one deliberate departure from the original: the frame rate.
      # The original puts it in the window title ("%s - %d fps (%d %%)");
      # here it sits at the right end of the bar instead, where a title
      # bar the user may not be looking at cannot hide it.
      renderer.setDrawColor(20, 20, 20, 255)
      var barRect = rect(0.cint, ScreenHeight.cint, ScreenWidth.cint, StatusBarHeight.cint)
      discard renderer.fillRect(addr barRect)

      const
        lampW = 14.cint # the original's indicator bitmaps are 14x12
        lampH = 12.cint
        lampY = (ScreenHeight + (StatusBarHeight - lampH.int) div 2).cint
        textY = (ScreenHeight + (StatusBarHeight - ankfont.GlyphHeight) div 2).cint
        labelColor = (200'u8, 200'u8, 200'u8)
        # Three lamp states, matching the original's access_off /
        # access_on / access_green bitmaps. The third is selected by
        # floppy_disk_indicator_color(), which the core raises only for a
        # drive currently configured as 2HD - so a 2D game legitimately
        # never shows it.
        lampOff = (60'u8, 60'u8, 60'u8)
        lampOn = (230'u8, 60'u8, 50'u8)
        lampOn2 = (60'u8, 220'u8, 70'u8)
        tapeOn = (230'u8, 160'u8, 30'u8)

      var x = 6.cint
      x = font.draw(renderer, x, textY, "FD:", labelColor[0], labelColor[1], labelColor[2])
      x += 4
      for drv in 0 ..< 2:
        let (r, g, b) =
          if bx1IsFloppyDiskAccessed(h, drv.cint) == 0: lampOff
          elif bx1FloppyDiskIndicatorColor(h, drv.cint) != 0: lampOn2
          else: lampOn
        renderer.setDrawColor(r, g, b, 255)
        var lampRect = rect(x, lampY, lampW, lampH)
        discard renderer.fillRect(addr lampRect)
        x += lampW + 2
      x += 8

      x = font.draw(renderer, x, textY, "CMT:", labelColor[0], labelColor[1], labelColor[2])
      x += 4
      let (tr, tg, tb) = if bx1IsTapeActive(h) != 0: tapeOn else: labelColor
      font.draw(renderer, x, textY, tapeStatus, tr, tg, tb)

      let fpsText = $fpsDisplay & " fps"
      font.draw(renderer, ScreenWidth.cint - font.width(fpsText) - 6, textY, fpsText,
        labelColor[0], labelColor[1], labelColor[2])

      renderer.present()
      inc drawnFrames

    # Frame rate and tape message are both sampled on a timer rather than
    # every frame: the rate needs a window to average over, and the tape
    # message is a string that has to cross the FFI boundary and be copied.
    # The original app polls its status bar on the same kind of timer
    # (winmain.cpp uses 200ms).
    let nowTicks = getTicks()
    if nowTicks - lastStatusTicks >= StatusPollMs:
      tapeStatus = $bx1GetTapeMessage(h)
      lastStatusTicks = nowTicks
    if nowTicks - lastFpsTicks >= 1000:
      # Drawn frames per second, which is what the original's counter
      # measures too - not the number of VM frames stepped, which the
      # audio-clock pacing above can decouple from this.
      fpsDisplay = int(drawnFrames.float * 1000.0 / float(nowTicks - lastFpsTicks) + 0.5)
      drawnFrames = 0
      lastFpsTicks = nowTicks

  stderr.writeLine "bubix1turboz: main loop exited, saving and shutting down"
  bx1SaveConfig(h, paths.configFilePath().cstring)
  recentfiles.save(paths.recentFilesPath(), recent)

  closeAudioDevice(audioDev)
  font.destroy()
  texture.destroy()
  renderer.destroy()
  sdlWin.destroy()
  sdl2.quit()
  if win != nil:
    win.destroy()
  uing.uninit()
  bx1Destroy(h)

main()
