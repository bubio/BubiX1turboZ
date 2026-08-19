## BubiX1turboZ application entry point.
##
## Single window, two threads. The machine runs on `emulationLoop`; this
## thread pumps events, drives the menus and presents finished frames. The
## split is what lets a menu stay open or a modal dialog wait on the user -
## both of which park this thread inside AppKit indefinitely - without the
## guest stopping and the audio device running dry.
##
## They meet only inside the emulation core, and never at the same time:
## every `bx1_*` call takes the core's recursive VM lock (the `vm_lock`
## guard in src/bridge/bubix1_api.cpp), so no call site here has to
## remember to lock. The two exceptions are the audio device's own thread,
## which has a mutex of its own and must never wait for a frame, and this
## file's `drawFrame`, which holds the lock explicitly across a pair of
## calls rather than each of them.
##
## SDL2 owns the application object, the event pump and the emulation
## surface; everything the host platform draws around it - the menu bar,
## the file dialogs, the volume panel, the save-state picker - is built as
## plain AppKit objects under `bubix1/`. Phase 1.2's 案 B put a GUI library
## (uing/libui-ng) between this file and AppKit for the menu bar and the
## volume panel, but every other piece of UI had already had to go around
## it, and what remained was paid for with a hidden placeholder window and
## a list of crash-avoidance workarounds; it was removed rather than ported
## to the other platforms three times over. See DevelopmentPlan phase 1.2.
##
## One ordering rule survives that change: `sdl2.init` creates `NSApp`, so
## nothing may put anything on screen - not even an error alert - before it
## has run. The menu bar is installed afterwards, replacing SDL's own (see
## nativemenu.m for what that is worth).
##
## Every way of quitting ends at `setRunning(false)`, which unwinds the
## loops on both threads and lets the saves at the bottom of `main` run
## once the emulation thread has been joined. The Quit item calls it
## directly; the Dock's Quit, the Apple Event a logout sends and SIGTERM
## all arrive as `QuitEvent` instead, because SDL subclasses
## `NSApplication` and overrides `-terminate:` to post `SDL_QUIT` rather
## than terminate (verified with `otool -oV`: `SDLApplication` overrides
## exactly `-terminate:` and `-sendEvent:`).
##
## `applicationShouldTerminate:` is therefore never called in this app -
## AppKit only sends it from the `-terminate:` that SDL replaced - so the
## application delegate is not where shutdown can be hooked here. Leaving
## the Quit item on `running = false` rather than on `-[NSApp terminate:]`
## also keeps it expressible on the platforms that have no such selector.
##
## Menu policy follows BluePrint/DevelopmentPlan 0.5: the core still has
## USE_FLOPPY_DISK=4 and USE_HARD_DISK, but only floppy drives 1-2 and no
## HDD are exposed here - feature reduction happens at this layer, not in
## the core.

import std/[atomics, options, os, strformat, strutils, times]
import sdl2
import sdl2/audio
import bubix1/core
import bubix1/keymap
import bubix1/paths
import bubix1/recentfiles
import bubix1/archive
import bubix1/diskset
import bubix1/ankfont
import bubix1/hostconfig
import bubix1/deflate
import bubix1/fddnoise
import bubix1/savestate
import bubix1/capture
import bubix1/i18n
# Everything that talks to the host's windowing system. These are the only
# imports here with a platform behind them; see bubix1/ui/README.md.
import bubix1/ui/nativemenu
import bubix1/ui/clipboard
import bubix1/ui/filedialog
import bubix1/ui/statepicker
import bubix1/ui/volumepanel

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
  # Fixed slots for a drive's disk list. Matches diskset.MaxBanks (and so the
  # core's MAX_D88_BANKS); unused slots are hidden, not shown. An archive
  # holding more images than this lists only the first ones in the menu, but
  # the Insert chooser enumerates all of them, so none become unreachable.
  DiskSlots = diskset.MaxBanks
  # The core is built with USE_FLOPPY_DISK=4, but BluePrint calls for two
  # drives in the UI (commercial X1 titles never needed more). Reducing the
  # feature here rather than in the core is the standing policy - see
  # docs/dev/DevelopmentPlan.md 0.5.
  FloppyDrives = 2
  # Save state slots, plus the quick save ⌘S/⌘L uses. Same count as the
  # original's Save/Load State submenus.
  StateSlots = 10
  QuickSlot = -1
  # What the application menu and the About box call this app. Not read
  # from the bundle: the dev build is a bare binary with no bundle to ask.
  AppName = "BubiX1turboZ"
  # CONFIG_NAME in vm/x1/x1.h. Recorded in a save state so one taken on
  # another machine of this family cannot be loaded here by accident.
  Machine = "x1turboz"
  # .nimble is the single source of truth for the app version; the build
  # script reads it and passes it in via -d so it isn't hardcoded twice.
  # The fallback only matters for ad-hoc `nim c` runs outside the script.
  appVersion {.strdefine.} = "0.0.0-dev"

# SDL_DROPFILE hands ownership of `event.drop.file` to the caller; the
# Nim sdl2 binding does not wrap SDL_free itself (see its DropEventObj
# doc comment), so it is declared directly here.
proc sdlFreeStr(mem: cstring) {.importc: "SDL_free", cdecl.}

# The screen area minus whatever the desktop reserves (the menu bar and the
# Dock on macOS). Used to decide how many "Window xN" scales the Host >
# Screen menu can offer, and to check that a remembered window position is
# still on a screen. The Nim sdl2 binding wraps SDL_GetDisplayBounds but
# not this one, so it is declared here; returns 0 on success.
proc sdlGetDisplayUsableBounds(displayIndex: cint, bounds: var Rect): cint
  {.importc: "SDL_GetDisplayUsableBounds", cdecl.}

proc windowPosOnScreen(x, y: cint): bool =
  ## Whether a remembered window origin still lands somewhere the user can
  ## reach. The display layout can differ from the run that saved it - an
  ## external screen unplugged, a resolution changed - so the position is
  ## checked both before it is restored and before it is written back,
  ## rather than trusting the file. Usable rather than full bounds: the
  ## menu bar occupies the top of the primary display, and a window
  ## restored underneath it would be awkward to drag back out.
  for i in 0 ..< getNumVideoDisplays():
    var bounds: Rect
    if sdlGetDisplayUsableBounds(i, bounds) != 0:
      continue
    if x >= bounds.x and y >= bounds.y and
       x < bounds.x + bounds.w and y < bounds.y + bounds.h:
      return true
  false

const
  ## How SDL samples the guest texture when it is drawn at a size other than
  ## its own. These are SDL_ScaleMode values (SDL 2.0.12 and later);
  ## SDL_ScaleModeBest is left out deliberately - it only means anisotropic
  ## filtering on the Direct3D backends and resolves to linear everywhere
  ## else, so on this app's Metal renderer it would be a menu entry that
  ## changes nothing.
  ScaleModeNearest = 0.cint
  ScaleModeLinear = 1.cint

# Set per texture rather than through the SDL_RENDER_SCALE_QUALITY hint: the
# hint is only read when a texture is created, so switching filters at
# runtime would mean rebuilding the guest texture, and it would apply to the
# status bar's 8x8 glyph texture as well. The Nim sdl2 binding does not wrap
# this call, so it is declared here; returns 0 on success.
proc sdlSetTextureScaleMode(texture: TexturePtr, scaleMode: cint): cint
  {.importc: "SDL_SetTextureScaleMode", cdecl.}

# --- State shared with the emulation thread ---------------------------------
#
# The VM runs on a thread of its own (see `emulationLoop`), so that a menu
# being held open or a modal dialog waiting on the user - both of which
# park the application's own thread inside AppKit for as long as they
# like - no longer stop the machine and starve the audio device.
#
# What crosses between the two threads is only this: two flags and a
# handle. Everything else the emulation thread touches lives behind
# `bx1_*`, and every one of those calls takes the VM lock (see the vm_lock
# guard in src/bridge/bubix1_api.cpp), so the two threads are never inside
# the core at the same time.
#
# The flags are wrapped in accessors so that reading one still looks like
# reading a variable at the fifty-odd places that do; only the definition
# here knows they are atomic.
var
  emuHandle: Bx1Handle
    ## Written once before the thread starts, read by it thereafter.
  emuTargetFrames: cint
    ## How much audio the pacing loop keeps queued. Same.
  runningFlag: Atomic[bool]
  fullSpeedFlag: Atomic[bool]
  drawPending: Atomic[bool]
    ## Set by the application's thread when it wants a fresh picture, and
    ## acted on by the emulation thread at its next frame boundary. See
    ## `emulationLoop` for why the rendering cannot happen anywhere else.
  parkRequested: Atomic[bool]
    ## Asks the emulation thread to stop advancing the machine and wait.
    ## Set only through `withMachineParked` below.
  parked: Atomic[bool]
    ## The emulation thread's answer: it is out of the core and idling.
  emuThread: Thread[void]

proc running(): bool = runningFlag.load(moRelaxed)
proc setRunning(value: bool) = runningFlag.store(value, moRelaxed)
  ## Every way of quitting calls this; the loops on both threads unwind.

proc fullSpeed(): bool = fullSpeedFlag.load(moRelaxed)
proc setFullSpeed(value: bool) = fullSpeedFlag.store(value, moRelaxed)

const ParkWaitMs = 500'u32
  ## How long to wait for the emulation thread to acknowledge a park before
  ## going ahead regardless. Generously above the few milliseconds it takes
  ## to finish the pass it is in.

template withMachineParked(body: untyped) =
  ## Runs `body` as the only thread driving the machine.
  ##
  ## The VM lock alone is not enough for this. It makes the two threads
  ## take turns, which is right for a single call but not for a sequence
  ## that has to be one indivisible step - a state load is settings, then
  ## remounts, then the state blob on top, and a frame emulated between
  ## any two of those is a frame the machine should never have run. It
  ## also lets this thread call `bx1RunFrame` itself (`restoreDrives`
  ## needs to, to land the core's deferred disk inserts) without the
  ## emulation thread driving `EMU::run` at the same time.
  parkRequested.store(true, moRelaxed)
  # `emuThread.running` covers the window before the thread exists at all,
  # and the deadline covers the emulation thread being stuck inside the
  # core: the point of parking is to keep a sequence indivisible, which is
  # never worth freezing the application's own thread over. Going ahead
  # without the acknowledgement loses that guarantee but nothing else -
  # every bx1_* call still takes the VM lock.
  let parkDeadline = getTicks() + ParkWaitMs
  while running() and emuThread.running and getTicks() < parkDeadline and
        not parked.load(moAcquire):
    delay(1)
  try:
    body
  finally:
    parkRequested.store(false, moRelaxed)


const FullSpeedBatchMs = 8'u32
  ## How long one Full Speed pass may run the VM before looking at the
  ## flags again. Long enough that the per-pass overhead is negligible,
  ## short enough that turning Full Speed off feels immediate.

proc yieldToUi(): bool =
  ## Stands aside for a millisecond if the application's thread is holding
  ## the VM lock or waiting for it, and says whether it did.
  ##
  ## Called only from between frames, where this thread holds no lock of
  ## its own, so everyone `bx1VmLockUsers` counts is someone else. The
  ## point is that the lock is a plain pthread mutex and not fair: with
  ## nothing but `bx1RunFrame` in the way - Full Speed unlocks and relocks
  ## a few hundred thousand times a second - the waiting thread was
  ## measured stuck for the better part of a second at a time, which is
  ## the whole of the UI (menus, input, drawing) not responding. Sleeping
  ## here rather than merely yielding is what actually hands the lock over:
  ## a yield leaves this thread runnable and it wins the race again.
  ##
  ## Only the Full Speed pass needs this. The audio-clock loop below stops
  ## on the ring buffer every few frames anyway, and it is the path with a
  ## real-time deadline to keep - a millisecond given away there comes out
  ## of the audio the device is about to ask for.
  result = bx1VmLockUsers() > 0
  if result:
    delay(1)

proc emulationLoop() {.thread.} =
  ## Advances the machine, and nothing else. Drawing, the event pump and
  ## every menu action stay on the application's own thread.
  ##
  ## Normally the pace is set by the audio ring buffer (DevelopmentPlan
  ## architecture decision 4): keep running frames while the buffer the
  ## SDL callback drains from is below the target latency, then wait. That
  ## makes the audio device the clock, which is the only clock in the
  ## system that runs at exactly the rate the guest's sound was sampled at.
  ##
  ## Nothing here allocates: this thread never touches a Nim string, seq or
  ## ref, only the flags above and the C bridge.
  while running():
    if parkRequested.load(moRelaxed):
      # Out of the core and staying out until the application's thread is
      # done with the machine; see `withMachineParked`.
      parked.store(true, moRelease)
      while running() and parkRequested.load(moRelaxed):
        delay(1)
      parked.store(false, moRelaxed)
      continue
    if fullSpeed():
      # Full Speed is not "run the VM faster" as such - it is the original
      # app's frame-skip path, which stops advancing the frame-interval
      # accumulator so nothing ever waits. Time-boxed per pass so that
      # switching it off is noticed promptly.
      let batchEnd = getTicks() + FullSpeedBatchMs
      var guardCount = 0
      while getTicks() < batchEnd and not parkRequested.load(moRelaxed):
        if yieldToUi():
          break
        if bx1RunFrame(emuHandle) > 0 and drawPending.exchange(false, moRelaxed):
          bx1DrawScreen(emuHandle)
        inc guardCount
        if guardCount > 2000:
          break
    else:
      var guardCount = 0
      while running() and not parkRequested.load(moRelaxed) and
            bx1GetBufferedAudioFrames(emuHandle) < emuTargetFrames:
        if bx1RunFrame(emuHandle) > 0 and drawPending.exchange(false, moRelaxed):
          bx1DrawScreen(emuHandle)
        inc guardCount
        if guardCount > 1000:
          # Should be unreachable in normal operation; bail out rather than
          # spin forever if the VM ever stops producing audio progress.
          break

    # Rendering happens on this thread, immediately after a frame the core
    # says it advanced - which is the only moment the picture is whole.
    # `DISPLAY::event_frame` wipes the machine's line buffers at the start
    # of every frame and `draw_line` refills them as the raster descends
    # (vm/x1/display.cpp), so a `bx1_draw_screen` that lands anywhere else
    # returns a picture blank below wherever the raster had got to. The VM
    # lock cannot help: it makes the two threads take turns, and taking a
    # turn mid-frame is precisely the problem. So the application's thread
    # asks for a picture (drawPending) and reads whichever one this thread
    # last left in the core's buffer. It is also what the original app
    # does - win32/winmain.cpp draws in the same iteration as emu->run().
    if not fullSpeed():
      # The audio buffer is full: there is nothing to do until the device
      # has drained some of it. A millisecond is far below the latency
      # window (100ms) and keeps this thread off a core it does not need.
      delay(1)

proc fail(msg: string) =
  stderr.writeLine "bubix1turboz: " & msg
  quit 1

const IplRomFileName = "IPLROM.X1T"
  ## The one file the machine cannot be built without - `x1.h`'s
  ## IPL_ROM_FILE_NAME. Everything else the core looks for either has a
  ## fallback (the font ROMs) or switches it to a working mode when absent
  ## (SUBROM/KBDROM select the pseudo sub-CPU).

proc iplRomPresent(): bool =
  ## Matched case-insensitively: the core spells the name in upper case
  ## while ROM sets ship it as `IPLROM.x1t`. macOS's default APFS is
  ## case-insensitive, so this only matters on a case-sensitive volume -
  ## but there it decides between running and a black screen.
  for kind, path in walkDir(paths.romsDir()):
    if kind in {pcFile, pcLinkToFile} and
        path.extractFilename.toUpperAscii == IplRomFileName:
      return true
  false

proc reportMissingRom() =
  ## Shown instead of starting: without the BIOS ROM the emulator draws
  ## nothing but a black window, which says nothing about what is wrong or
  ## where to fix it. The folder exists by now (ensureDirsExist), so the
  ## alert can offer to open it - it lives inside ~/Library, where the
  ## Finder gives no easy way to navigate by hand.
  let dir = paths.romsDir()
  stderr.writeLine "bubix1turboz: " & IplRomFileName & " not found in " & dir
  filedialog.missingRom(
    tr(msgBiosMissingTitle),
    trf(msgBiosMissingBody, IplRomFileName, dir),
    dir)

proc main() =
  paths.ensureDirsExist()

  # Host-side preferences the emulation core cannot hold - see hostconfig.nim.
  # Read first thing, before anything can put a word on screen: the alert
  # below is the earliest piece of UI there is, and the language it speaks
  # is one of the settings in here.
  var hostCfg = hostconfig.load(paths.hostConfigPath())
  var uiLanguage = hostCfg.getStr("UILanguage", "auto")
  i18n.setLanguage(uiLanguage)

  # Creates NSApp, which nothing that shows a window or an alert can do
  # without. Nothing here needs a ROM, so it can come first.
  if not sdl2.init(INIT_VIDEO or INIT_AUDIO or INIT_EVENTS):
    fail "SDL_Init failed: " & $getError()

  # After SDL_Init for the application object the alert below needs, and
  # before bx1Create, which would otherwise build a machine with no ROM.
  if not iplRomPresent():
    reportMissingRom()
    quit 1

  # Before bx1Create: the FDC loads the drive-noise WAVs as it is built, so
  # anything generated after this point would not be heard until the next
  # launch. See fddnoise.nim.
  fddnoise.ensureFiles(paths.romsDir())

  let h = bx1Create(paths.romsDir().cstring, paths.configFilePath().cstring)
  if h == nil:
    fail "bx1_create failed (place BIOS ROMs in " & paths.romsDir() & ")"
  var recent = recentfiles.load(paths.recentFilesPath())
  setRunning(true)

  proc vmSoundType(): int =
    ## The sound board the running VM was built with.
    ##
    ## `config.sound_type` is writable at any time but VM's constructor is
    ## the only thing that reads it (x1.cpp:76), so once Device > Sound has
    ## been used `bx1GetSoundType` reports a board this machine may not
    ## have. It stops being a lie at the next reset, which is where
    ## EMU::reset() rebuilds the VM for exactly this set of settings
    ## (emu.cpp:281-311) - and asking each time rather than caching once at
    ## startup is what keeps this correct across that rebuild. Anything
    ## reasoning about the live device chain (the save state's reinit
    ## metadata, the guard that refuses a state built from another chain,
    ## the Volume panel's greyed rows) must come here.
    bx1GetVmSoundType(h).int
  # Same reasoning for the sample rate and latency, and for the same two
  # readers: EMU takes both in its constructor and never re-reads them, so
  # once Host > Sound has been used, config holds a value the running
  # machine is not using. A save state's metadata must describe the machine
  # that produced it, and its load guard must compare against the machine
  # that would receive it - neither may consult config.
  let vmSoundFrequency = bx1GetSoundFrequency(h).int
  let vmSoundLatency = bx1GetSoundLatency(h).int

  # Host-side view settings. These are not in the core's config_t on this
  # platform (config.show_status_bar is Win32-only there), so they persist
  # in hostCfg above. Read up here because the Host menu is built before
  # the SDL window exists but its actions drive both.
  var showStatusBar = hostCfg.getBool("ShowStatusBar", true)
  # 0 = nearest neighbour, 1 = bilinear. Nearest stays the default: the X1
  # draws text and graphics on exact pixel boundaries, and linear filtering
  # blurs glyphs at any non-integer window size (phase 5 user decision).
  # Bilinear is offered because that blur is what some players want from a
  # stretched fullscreen picture.
  var scaleQuality = clamp(hostCfg.getInt("ScaleQuality", 0), 0, 1)

  # Assigned once the Volume panel exists, further down. A reset can rebuild
  # the VM (see vmSoundType above), and the core hands the new one the
  # per-device levels straight out of config - without the master volume
  # this layer mixes into them. Everything that resets the machine goes
  # through resetMachine() so that mix is put back.
  var afterReset: proc () {.closure.} = nil
  proc resetMachine() =
    bx1Reset(h)
    if afterReset != nil:
      afterReset()
  # Full Speed is a host-loop concept, not a core setting: config.full_speed
  # has no reader anywhere in the vendored core (the original's winmain.cpp
  # is the only thing that reads it), and config.cpp does not save or load
  # it either. It is still kept there so that the core holds one copy of
  # the setting rather than this layer holding a second one; every launch
  # starts with it off.
  setFullSpeed(false)
  # Set once the Control menu exists, so the status timer can re-sync the
  # one setting the core clears behind our back (see below).
  var romajiItemRef = MenuItemRef(tag: 0)
  var sdlWin: WindowPtr = nil
  var renderer: RendererPtr = nil
  # Created further down, but declared here because Host > Screen is built
  # before that point and its filter items set the scale mode on it.
  var screenTexture: TexturePtr = nil
  # Opened further down, but declared here because Host > Rec Sound is built
  # before that point and has to lock the device it records from.
  var audioDev: AudioDeviceID = 0
  # The rate the core actually synthesizes at, which is also the rate a
  # recording is written at. Not config.sound_frequency: X1turboZ overrides
  # that table's 48000Hz slot to 62500Hz.
  let soundRate = bx1GetActualSoundRate(h).int

  # --- Screen layout (the original's Host > Screen) ---
  # All three settings live in the core's config so they persist in
  # config.ini under the original's own key names ([Screen] WindowMode,
  # WindowStretchType, FullScreenStretchType), even though nothing inside
  # this build of the core ever reads them - only its win32 OSD did.
  #
  # windowScale is 1-based ("Window x1") where config.window_mode is 0-based.
  var windowScale = max(1, bx1GetWindowMode(h).int + 1)
  # 0 = the machine's real 640x400 pixels, 1 = the 640x480 that reproduces
  # the X1's non-square CRT pixels. 0 stays the default (phase 5 user
  # decision: the stretched picture reads as distorted on a modern display);
  # this only makes the original's other choice reachable.
  var stretchType = clamp(bx1GetWindowStretchType(h).int, 0, 1)
  var fullscreenStretch = clamp(bx1GetFullscreenStretchType(h).int, 0, 3)
  var isFullscreen = false
  # Where the window stood when the app last quit. Position only: its size
  # follows windowScale, which the core's own config.ini already carries.
  # Presence of the keys is what marks a position as remembered - a
  # negative coordinate is perfectly legal for a window on a display left
  # of, or above, the primary one, so no numeric value can serve as
  # "unset". Both are re-read from the window itself once it exists.
  let hasSavedWindowPos = hostCfg.getStr("WindowX", "").len > 0 and
                          hostCfg.getStr("WindowY", "").len > 0
  var windowX = hostCfg.getInt("WindowX", 0).cint
  var windowY = hostCfg.getInt("WindowY", 0).cint
  # WINDOW_HEIGHT_ASPECT for this machine: 480.
  let aspectHeight = bx1GetAspectHeight(h).int

  proc guestHeight(): int =
    ## The guest picture's height in window points at the current aspect.
    if stretchType == 0: ScreenHeight else: aspectHeight

  proc applyScaleQuality() =
    ## Pushes the current filter to the guest texture. A no-op before the
    ## texture exists; the texture applies it itself once created.
    if screenTexture != nil:
      discard sdlSetTextureScaleMode(screenTexture,
        if scaleQuality == 1: ScaleModeLinear else: ScaleModeNearest)

  proc statusBarHeight(): cint =
    (if showStatusBar: StatusBarHeight else: 0).cint

  proc applyWindowLayout() =
    ## Sizes the window to exactly fit the picture, at the current scale and
    ## aspect, plus the status bar. No renderer logical size is set: each of
    ## the fullscreen stretch modes needs its own destination rectangle, so
    ## drawFrame works in real window points and computes that itself.
    if sdlWin == nil:
      return
    sdlWin.setSize((ScreenWidth * windowScale).cint,
                   (guestHeight() * windowScale).cint + statusBarHeight())

  proc maxWindowScale(): int =
    ## How many "Window xN" items Host > Screen offers. The original builds
    ## up to MAX_WINDOW=10 and lists only the scales that fit the desktop
    ## (winmain.cpp:2044). Same rule, but measured against the taller 640:480
    ## aspect so that switching aspect can never leave the window larger than
    ## the display.
    result = 1
    var bounds: Rect
    if sdlGetDisplayUsableBounds(0, bounds) != 0:
      return
    for n in 2 .. 10:
      if (ScreenWidth * n).cint <= bounds.w and
         (aspectHeight * n).cint + StatusBarHeight <= bounds.h:
        result = n
      else:
        break

  proc guestRect(areaW, areaH: cint): Rect =
    ## Where the guest picture goes within the area above the status bar.
    ##
    ## Windowed, that area is already exactly the right size, so the picture
    ## fills it. Fullscreen, it is one of the original's four stretch modes
    ## (config.fullscreen_stretch_type, win32/osd_screen.cpp:230-268).
    if not isFullscreen:
      return rect(0, 0, areaW, areaH)
    case fullscreenStretch
    of 0:
      # Dot by dot: the machine's real pixels, centred, never scaled - so
      # 640x400 even when the window aspect above is set to 640:480.
      let w = min(ScreenWidth.cint, areaW)
      let h = min(ScreenHeight.cint, areaH)
      rect((areaW - w) div 2, (areaH - h) div 2, w, h)
    of 1, 2:
      # As large as fits while keeping 640:400 (1) or 640:480 (2).
      let ratioH = if fullscreenStretch == 1: ScreenHeight else: aspectHeight
      var w = areaW
      var h = cint(areaW.int * ratioH div ScreenWidth)
      if h > areaH:
        h = areaH
        w = cint(areaH.int * ScreenWidth div ratioH)
      rect((areaW - w) div 2, (areaH - h) div 2, w, h)
    else:
      # Fill: ignore the aspect ratio entirely.
      rect(0, 0, areaW, areaH)

  # Handles for the parts of the FD0/FD1 menus that change while running.
  # They are filled in after win.show() (there is no menu bar before that),
  # so the helpers below are written to be safe when called earlier, during
  # the pre-menu part of startup.
  var recentItems: array[RecentSlots, MenuItemRef]
  var recentNoneItem: MenuItemRef
  var setCaptionItems: array[FloppyDrives, MenuItemRef]
  var groupCaptionItems: array[FloppyDrives, array[DiskSlots, MenuItemRef]]
  var diskItems: array[FloppyDrives, array[DiskSlots, MenuItemRef]]
  var diskSepItems: array[FloppyDrives, MenuItemRef]
  var writeProtectItems: array[FloppyDrives, MenuItemRef]
  var menusBuilt = false

  # Every disk the user's last mount request resolved to, per drive, plus
  # which of them is currently in. Both drives normally hold the same set
  # and differ only in the index, which is what makes "swap to disk 3" a
  # menu click: the entry already carries the (path, bank) to re-open.
  # See diskset.nim for why playlists are flattened into this too.
  var driveSet: array[FloppyDrives, DiskSet]
  var driveIndex: array[FloppyDrives, int] = [-1, -1] # -1: nothing inserted
  # What the user actually opened - the archive or playlist, not the image
  # extracted out of it - shown as the caption above the disk list.
  var driveSource: array[FloppyDrives, string]

  proc refreshFloppyMenu(drv: int) =
    ## Brings one drive submenu's variable parts back in line with the
    ## machine: the disk list and the write-protect state. Mirrors the
    ## original's update_floppy_disk_menu (winmain.cpp), which rebuilds the
    ## same tail of the same menu on every open.
    if not menusBuilt:
      return
    let entries = driveSet[drv].entries
    let groups = driveSet[drv].groups
    # The original hides this list unless the mount produced more than one
    # disk (update_floppy_disk_menu, winmain.cpp: `bank_num > 1`), which
    # leaves a single-disk mount with nothing in the menu naming what is in
    # the drive. Shown from one disk up instead: the checked entry is how
    # this app answers "what is loaded", and a menu that goes blank for the
    # commonest case answers it nowhere.
    let hasDisks = entries.len > 0
    # The mount's own caption stays a multi-disk affair: with one disk it
    # would only repeat the entry directly beneath it.
    let multiDisk = entries.len > 1
    # Per-file captions only earn their space when the disks came from more
    # than one file, exactly as Bubilator88 shows its image groups.
    let showGroups = multiDisk and groups.len > 1
    setCaptionItems[drv].hidden = not multiDisk
    if multiDisk:
      setCaptionItems[drv].title = driveSource[drv].extractFilename()
    diskSepItems[drv].hidden = not hasDisks
    for i in 0 ..< DiskSlots:
      let show = hasDisks and i < entries.len
      diskItems[drv][i].hidden = not show
      var caption = ""
      if show:
        # The position number tells two disks of a set apart; a lone disk
        # has nothing to be told apart from, so it is named plainly.
        diskItems[drv][i].title =
          (if showGroups: "  " else: "") &
          (if multiDisk: &"{i+1}: " else: "") & entries[i].label
        diskItems[drv][i].checked = (driveIndex[drv] == i)
        if showGroups:
          for g in groups:
            if g.start == i:
              caption = g.name
              break
      groupCaptionItems[drv][i].hidden = caption.len == 0
      if caption.len > 0:
        groupCaptionItems[drv][i].title = caption

    let inserted = bx1IsFloppyDiskInserted(h, drv.cint) != 0
    writeProtectItems[drv].enabled = inserted
    writeProtectItems[drv].checked = inserted and bx1GetFloppyWriteProtected(h, drv.cint) != 0

  proc refreshRecentMenu() =
    ## One shared list for the whole app, rather than the per-drive lists
    ## the original keeps: an entry names a title, not a drive, and picking
    ## one starts that title in both drives.
    if not menusBuilt:
      return
    for i in 0 ..< RecentSlots:
      let show = i < recent.len
      recentItems[i].hidden = not show
      if show:
        recentItems[i].title = recent[i].extractFilename()
    recentNoneItem.hidden = recent.len > 0

  proc refreshFloppyMenus() =
    for drv in 0 ..< FloppyDrives:
      refreshFloppyMenu(drv)
    refreshRecentMenu()

  proc rememberRecent(path: string) =
    recent = recentfiles.pushFront(recent, path)
    refreshRecentMenu()

  proc mountAt(drv, index: int): bool =
    ## Inserts one disk of the set the drive is already holding. Swapping
    ## between them is just this call with a different index: the core takes
    ## the (path, bank) pair straight from the entry.
    let entries = driveSet[drv].entries
    if index < 0 or index >= entries.len:
      return false
    result = bx1OpenFloppy(h, drv.cint,
                           entries[index].path.cstring, entries[index].bank.cint) != 0
    if result:
      driveIndex[drv] = index
    refreshFloppyMenu(drv)

  proc ejectFloppy(drv: int) =
    bx1CloseFloppy(h, drv.cint)
    driveSet[drv] = DiskSet()
    driveIndex[drv] = -1
    driveSource[drv] = ""
    refreshFloppyMenu(drv)

  # There used to be a syncDrivesFromCore() here, re-reading EMU::d88_file
  # after a state load because the core's own .sta restored its record of
  # what was mounted. This app's states do not: the drives are restored
  # from the state's own metadata by restoreDrives() below, which knows the
  # archive a disk came from - something the core never records.

  proc pickerRows(s: DiskSet): seq[string] =
    ## One line per disk for the Insert chooser, carrying what Bubilator88's
    ## sheet shows: position, name, medium, and whether it is write
    ## protected. The leading number also keeps the lines distinct, which
    ## NSPopUpButton requires (see filedialog.m); it counts from 1 to match
    ## the same disks as the drive menu numbers them.
    for i, e in s.entries:
      var row = &"{i+1}: " & e.label
      let medium = diskset.mediaLabel(e.mediaType)
      if medium.len > 0:
        row.add "  " & medium
      if e.writeProtected:
        row.add "  🔒"
      result.add row

  proc resolveOrWarn(path: string): seq[string] =
    # Catches OSError as well as IOError: archive.nim reaches the filesystem
    # through getFileInfo/createDir/removeDir/moveDir, all of which raise
    # OSError, and OSError is not an IOError - so an unreadable or
    # just-deleted archive would escape an IOError-only handler and take the
    # app down instead of printing the warning this proc exists for.
    try:
      result = archive.resolveMedia(path)
    except CatchableError as e:
      stderr.writeLine "bubix1turboz: " & e.msg
      result = @[]

  proc floppyImagesOf(path: string): seq[string] =
    ## The disk images one mount request resolves to, in order.
    ##
    ## Tapes are dropped rather than mounted: nothing in this app opens the
    ## CMT deck (see where the menus are built), so a dropped .tap/.cmt -
    ## or a .wav that merely happens to sit next to the disks inside an
    ## archive - must not reach it either.
    for p in resolveOrWarn(path):
      if archive.classify(p) == archive.mkFloppy:
        result.add p

  proc loadMedia(path: string, startDrive = 0, bothDrives = false, reset = false) =
    ## Single entry point for anything that can end up in a drive: a bare
    ## disk image, a 7z/zip archive, or an m3u/m3u8 playlist. Every way of
    ## inserting a disk goes through here - FD0/FD1's Insert, their Recent
    ## entries, and drag & drop - so a game in an archive is opened exactly
    ## like a bare .d88, with no separate "open archive" action to pick
    ## between (the same single-action model Bubilator88 uses).
    ##
    ## Whatever the input resolves to becomes one flat list of disks (see
    ## diskset.nim), which both drives keep so that any disk of the title
    ## can be swapped in later from either menu.
    ##
    ## `bothDrives` picks between the two mount modes Bubilator88 offers:
    ## filling FD0 and FD1 with the title's first two disks (what a 2-disk
    ## game wants, and what a drop does), or putting a single chosen disk
    ## into `startDrive` - asking which one when there is a choice.
    ##
    ## `reset` distinguishes the callers further: dropping a file on the
    ## window boots it (BluePrint line 32), while inserting one from the
    ## menu leaves the running machine alone, so swapping disks mid-game
    ## does not throw the session away.
    var mounted = false
    let disks = diskset.build(floppyImagesOf(path))
    if disks.entries.len > 0:
      if bothDrives:
        for drv in 0 ..< FloppyDrives:
          if drv < disks.entries.len:
            driveSet[drv] = disks
            driveSource[drv] = path
            if mountAt(drv, drv):
              mounted = true
          else:
            # A one-disk title must not leave the previous game's disk
            # sitting in FD1, which is why this ejects rather than skips.
            ejectFloppy(drv)
      else:
        var index = 0
        if disks.entries.len > 1:
          index = filedialog.chooseDisk(tr(msgSelectDiskTitle), pickerRows(disks))
          if index < 0:
            return # cancelled: leave the drive, and Recent, untouched
        let drv = min(startDrive, FloppyDrives - 1)
        driveSet[drv] = disks
        driveSource[drv] = path
        if mountAt(drv, index):
          mounted = true
    # `mounted` means "the core accepted at least one image", not "the image
    # was valid" - bx1_open_floppy cannot tell us the latter (see its
    # comment), so a corrupt file still lands in Recent. The original
    # records history on open the same way, without validating first.
    if mounted:
      # The archive/playlist itself is what the user thinks of as "the
      # game" and what they will look for again in Recent Files - not
      # the extracted cache path or an individual disk inside it.
      rememberRecent(path)
      if reset:
        resetMachine()

  proc loadTape(path: string) {.used.} =
    ## The CMT deck's equivalent of loadMedia: takes an archive, a playlist
    ## or a bare tape image and plays the first tape it finds. Deliberately
    ## ignores any disk images in the same archive rather than reusing
    ## loadMedia, so opening a tape can never swap a disk out from under a
    ## running game.
    ##
    ## Currently unreferenced: the CMT menu that called it was removed
    ## (see the note where the menus are built). Kept, and marked `used`,
    ## so the deck can be re-exposed without rewriting this.
    for p in resolveOrWarn(path):
      if archive.classify(p) == archive.mkTape and bx1OpenTape(h, p.cstring, 1) != 0:
        rememberRecent(path)
        return

  # --- Application menu ---
  # Installing a bar of our own discards the one SDL builds for itself
  # (an app menu plus Window and View menus this app has no use for). Its
  # Quit item goes straight to -[NSApp terminate:], which would skip the
  # bx1SaveConfig/recentfiles.save at the end of main; the item below
  # leaves through the same `running = false` as every other exit.
  #
  # Only the items this app actually offers are here - there is no
  # Preferences window, so there is no Preferences item.
  let appMenu = nativemenu.installMenuBar(AppName)
  appMenu.addItem(trf(msgAppMenuAbout, AppName), proc () =
    filedialog.message(AppName & " " & appVersion, tr(msgAboutBody)))
  appMenu.addSeparator()
  appMenu.addStandardItem(tr(msgAppMenuServices), siServices)
  appMenu.addSeparator()
  # The shortcuts macOS puts on these are part of the platform, so they are
  # given the standard ones rather than any of this app's choosing.
  appMenu.addStandardItem(trf(msgAppMenuHide, AppName), siHide, "h")
  appMenu.addStandardItem(tr(msgAppMenuHideOthers), siHideOthers, "h",
    ModCommand or ModOption)
  appMenu.addStandardItem(tr(msgAppMenuShowAll), siShowAll)
  appMenu.addSeparator()
  appMenu.addItem(trf(msgAppMenuQuit, AppName), proc () = setRunning(false), "q")

  # --- Control menu (built natively; see nativemenu.nim) ---
  # Item order, wording and grouping follow the original eX1turboZ's own
  # Control menu (src/res/x1turboz.rc), minus what this port does not have:
  # the three "Debug ... CPU" items and "Close Debugger" (the core's
  # debugger console API is stubbed out here, and a menu that does nothing
  # is worse than no menu), and "Exit" (macOS expects Quit in the
  # application menu, which is where this app puts it).
  let controlMenu = nativemenu.addMenu(tr(msgMenuControl))
  controlMenu.addItem(tr(msgReset), proc () = resetMachine(), key = "r")
  # The original labels special_reset() "NMI" for this machine; on the X1
  # turbo it is the front-panel NMI button, which is also how a NEW ON
  # reset is triggered.
  controlMenu.addItem(tr(msgNmi), proc () = bx1SpecialReset(h))
  controlMenu.addSeparator()

  # CPU speed multiplier: a radio group, so each item clears the others.
  var cpuItems: array[5, MenuItemRef]
  proc syncCpuItems() =
    let cur = bx1GetCpuPower(h)
    for i in 0 ..< cpuItems.len:
      cpuItems[i].checked = (i.cint == cur)
  proc makeCpuAction(idx: int): MenuAction =
    result = proc () =
      bx1SetCpuPower(h, idx.cint)
      syncCpuItems()
  # The multipliers are the original's own 1/2/4/8/16, built from one
  # message rather than five so a translation cannot renumber them.
  for i, factor in [1, 2, 4, 8, 16]:
    cpuItems[i] = controlMenu.addItem(trf(msgCpuPower, factor), makeCpuAction(i))
  let fullSpeedItem = controlMenu.addItem(tr(msgFullSpeed))
  let driveVmItem = controlMenu.addItem(tr(msgDriveVmInOpecode))
  controlMenu.addSeparator()

  controlMenu.addItem(tr(msgPaste), proc () =
    # The original pastes the clipboard through the core's auto key, which
    # replays it as real keystrokes rather than injecting text - so it
    # works with any program running in the guest.
    let text = clipboard.getText()
    if text.len > 0:
      bx1StartAutoKey(h, text.cstring), key = "v")
  controlMenu.addItem(tr(msgStopPaste), proc () = bx1StopAutoKey(h))
  let romajiItem = controlMenu.addItem(tr(msgRomajiToKana))
  romajiItemRef = romajiItem
  controlMenu.addSeparator()

  # Save states. The format is this app's own (.bx1s, see
  # docs/dev/SaveState.md and savestate.nim), not the core's .sta: that one
  # embeds _MAX_PATH-sized buffers, carries no metadata, and refers to a
  # multi-disk image's banks by bare index. Nothing migrates - any leftover
  # x1turboz.sta* is simply ignored.
  #
  # The UI follows Bubilator88 (Views/SaveStateSheetView.swift): a quick
  # save pair on ⌘S/⌘L with a caption showing what is in it, and two items
  # that open a grid of thumbnails - a state is worth choosing by what it
  # looks like, which a menu of ten numbered items cannot show.
  var quickLoadItem: MenuItemRef
  var quickInfoItem: MenuItemRef

  proc scratch(name: string): string =
    paths.scratchDir() / name

  proc iplFingerprint(): uint32 =
    ## CRC32 of the IPL ROM the core loaded. A save state contains no ROM
    ## data at all (MEMORY::process_state saves ram/extram only), so this
    ## is the only way to notice one being restored against another BIOS.
    ## Reads the same two names, in the same order and length, as
    ## MEMORY::initialize() does.
    ## Matched without regard to case: the core reaches the file through
    ## the filesystem's own matching (a ROM set shipping IPLROM.x1t boots
    ## fine on macOS), and a name this missed would silently turn the
    ## check below into a no-op rather than fail loudly.
    const IplSize = 0x8000 # IPL_ROM_FILE_SIZE, vm/x1/x1.h
    for name in ["IPLROM.X1T", "IPL.ROM"]:
      for found in walkFiles(paths.romsDir() / "*"):
        if cmpIgnoreCase(found.extractFilename(), name) != 0:
          continue
        try:
          var data = readFile(found)
          if data.len > IplSize:
            data.setLen IplSize
          return deflate.crc32(data)
        except CatchableError:
          return 0
    0

  proc fileFingerprint(path: string): (int, uint32) =
    ## Size and CRC32 of a disk image, recorded so a load can tell the user
    ## the file behind a restored drive is not the one the state was made
    ## with - the state's own copy of the disk still restores fine.
    try:
      let data = readFile(path)
      (data.len, deflate.crc32(data))
    except CatchableError:
      (0, 0'u32)

  proc thumbnailPng(): seq[byte] =
    ## Half-scale snapshot of the frame already on screen (640x400 ->
    ## 320x200). Nearest-neighbour: the source is a 1:1 emulator frame, so
    ## dropping every other pixel is what a downscale of it looks like
    ## anyway, and it keeps this off the save path's critical timing.
    # Held across the read for the same reason drawFrame holds it: the
    # emulation thread may be rendering into this buffer right now.
    bx1Lock(h)
    defer: bx1Unlock(h)
    let fb = bx1GetFramebuffer(h)
    let w = bx1GetScreenWidth(h).int
    let ht = bx1GetScreenHeight(h).int
    if fb == nil or w < 2 or ht < 2:
      return @[]
    let tw = w div 2
    let th = ht div 2
    var rgb = newSeq[byte](tw * th * 3)
    for y in 0 ..< th:
      for x in 0 ..< tw:
        let px = fb[(y * 2) * w + x * 2] # ARGB8888, alpha unused
        let o = (y * tw + x) * 3
        rgb[o] = byte(px shr 16)
        rgb[o + 1] = byte(px shr 8)
        rgb[o + 2] = byte(px)
    try:
      deflate.encodePng(tw, th, rgb)
    except CatchableError:
      @[] # a state without a thumbnail is still a valid state

  proc currentMeta(): StateMeta =
    result = StateMeta(
      savedAt: getTime().toUnix(),
      producer: "BubiX1turboZ " & appVersion,
      coreStateId: bx1CoreStateId(),
      machine: Machine,
      iplCrc32: iplFingerprint(),
      reinit: ReinitConfig(
        soundType: vmSoundType(),
        printerType: bx1GetPrinterType(h).int,
        serialType: bx1GetSerialType(h).int,
        soundFrequency: vmSoundFrequency,
        soundLatency: vmSoundLatency),
      runtime: RuntimeConfig(
        monitorType: bx1GetMonitorType(h).int,
        driveType: bx1GetDriveType(h).int),
      cpuPower: bx1GetCpuPower(h).int,
      fullSpeed: fullSpeed())
    for drv in 0 ..< FloppyDrives:
      result.runtime.correctDiskTiming.add bx1GetCorrectDiskTiming(h, drv.cint) != 0
      result.runtime.ignoreDiskCrc.add bx1GetIgnoreDiskCrc(h, drv.cint) != 0
      let index = driveIndex[drv]
      if index < 0 or index >= driveSet[drv].entries.len:
        result.drives.add DriveState(occupied: false)
      else:
        let e = driveSet[drv].entries[index]
        let (size, crc) = fileFingerprint(e.path)
        result.drives.add DriveState(
          occupied: true,
          source: (if driveSource[drv].len > 0: driveSource[drv] else: e.path),
          image: e.path, bank: e.bank, label: e.label,
          imageSize: size, imageCrc32: crc,
          writeProtected: bx1GetFloppyWriteProtected(h, drv.cint) != 0)
    for d in result.drives:
      if d.occupied:
        result.title = d.source.extractFilename().changeFileExt("")
        break

  proc slotInfo(slot: int): Option[StateInfo] =
    ## What a slot holds, or nothing when it is empty or unreadable. A file
    ## this build cannot parse is treated as empty rather than reported:
    ## the picker shows it as a slot free to write over, which is what it
    ## effectively is.
    let path = paths.stateSlotPath(slot)
    if fileExists(path):
      try:
        return some(savestate.readInfo(path))
      except CatchableError:
        discard
    none(StateInfo)

  proc refreshQuickStateMenu() =
    ## The quick save is the only state the menu itself describes; the
    ## numbered slots are described by the picker, which reads them fresh
    ## every time it opens.
    let info = slotInfo(QuickSlot)
    quickLoadItem.enabled = info.isSome
    quickInfoItem.hidden = info.isNone
    if info.isSome:
      quickInfoItem.title = savestate.describe(info.get)

  proc saveStateTo(path: string) =
    createDir paths.scratchDir() # $TMPDIR can be reaped under a long session
    let blob = scratch("save.vmst")
    # Both halves of the snapshot come from a machine that is standing
    # still, so the thumbnail is the picture of the frame the state was
    # taken at rather than of whatever the emulation thread has reached by
    # the time the PNG is encoded.
    var captured = false
    var thumbnail: seq[byte]
    withMachineParked:
      captured = bx1VmStateSave(h, blob.cstring) != 0
      if captured:
        thumbnail = thumbnailPng()
    if not captured:
      filedialog.message(tr(msgSaveStateTitle), tr(msgStateCaptureFailed))
      return
    try:
      savestate.save(path, blob, currentMeta(), thumbnail)
    except CatchableError as e:
      filedialog.message(tr(msgSaveStateTitle), e.msg)
    finally:
      removeFile(blob)
    refreshQuickStateMenu()

  proc restoreDrives(m: StateMeta): string =
    ## Puts the disks the state was taken with back in the drives, through
    ## the ordinary mount path, and returns a warning for the caller to
    ## show (empty when there is nothing to report).
    ##
    ## The core inserts a disk about half an emulated second after being
    ## asked to (EMU::open_floppy_disk ejects first, so the guest notices
    ## the swap), and that deferred insert reads the image file into the
    ## drive - which would overwrite the disk contents the VM state is
    ## about to restore. Hence the wait below: let every insert land
    ## first, then apply the state on top. The frames this runs are
    ## thrown away by that same state, so they cost nothing but time.
    # Each entry is a whole sentence rather than a fragment to be glued into
    # one: which part of "X is missing" is the subject and which the verb
    # differs by language, so the joining has to happen between sentences.
    var stale: seq[string]
    var awaiting: seq[int]
    for drv in 0 ..< FloppyDrives:
      if drv >= m.drives.len or not m.drives[drv].occupied:
        ejectFloppy(drv)
        continue
      let d = m.drives[drv]
      # Rebuild the title's disk list from what the user originally opened
      # so the menu offers every disk again. Re-resolving is what makes
      # the labels and per-file grouping come back identical; if the
      # archive or playlist is gone, the image alone still mounts.
      var set = diskset.build(floppyImagesOf(d.source))
      var index = -1
      for i, e in set.entries:
        if e.path == d.image and e.bank == d.bank:
          index = i
          break
      if index < 0:
        set = diskset.build([d.image])
        index = (if d.bank < set.entries.len: d.bank else: 0)
      if set.entries.len == 0:
        stale.add trf(msgDiskMissing, d.image.extractFilename())
        ejectFloppy(drv)
        continue
      driveSet[drv] = set
      driveSource[drv] = d.source
      # Only a drive the core actually accepted is worth waiting on below;
      # one whose image has gone missing would spin out the whole guard.
      if mountAt(drv, index):
        awaiting.add drv
      else:
        stale.add trf(msgDiskNotMounted, d.image.extractFilename())
      bx1SetFloppyWriteProtected(h, drv.cint, d.writeProtected.cint)
      if d.imageSize > 0:
        let (size, crc) = fileFingerprint(d.image)
        if size != d.imageSize or crc != d.imageCrc32:
          stale.add trf(msgDiskChanged, d.image.extractFilename())
    var pending = true
    var guard = 0
    while pending and guard < 300:
      pending = false
      for drv in awaiting:
        if bx1IsFloppyDiskInserted(h, drv.cint) == 0:
          pending = true
      if pending:
        discard bx1RunFrame(h)
        inc guard
    if stale.len > 0:
      result = tr(msgStateRestoredWithIssues) & "\n" & stale.join("\n")

  proc loadStateFrom(path: string) =
    if not fileExists(path):
      return
    var info: StateInfo
    try:
      info = savestate.readInfo(path)
    except CatchableError as e:
      filedialog.message(tr(msgLoadStateTitle), e.msg)
      return
    let m = info.meta

    # Everything that can refuse the load is checked before the machine is
    # touched at all, so a rejected state leaves the session running.
    if m.coreStateId != bx1CoreStateId():
      filedialog.message(tr(msgLoadStateTitle), tr(msgStateCoreMismatch))
      return
    if m.machine != Machine:
      filedialog.message(tr(msgLoadStateTitle), tr(msgStateMachineMismatch))
      return
    let ipl = iplFingerprint()
    if m.iplCrc32 != 0 and ipl != 0 and m.iplCrc32 != ipl:
      filedialog.message(tr(msgLoadStateTitle), tr(msgStateIplMismatch))
      return
    # Settings the original reacts to by throwing the VM away and building
    # a new one. This layer replaces device state only and cannot ask for
    # that rebuild at load time (EMU::vm is protected, and the core does it
    # only from its own load_state and from EMU::reset), so a mismatch is
    # refused rather than half-applied.
    # The setting that differs, as a phrase that goes into the message
    # below, plus the whole message when this one has a remedy of its own -
    # which the sound board does (a reset) and the rest do not. Two
    # messages rather than one sentence with a swappable tail: what can be
    # done about it is not a clause that can be lifted out of a Japanese
    # sentence and put back into another.
    var mismatch = ""
    var mismatchMessage = ""
    # Sound type is in this list, not applied like the settings below it:
    # VM's constructor builds a different device chain for each value
    # (x1.cpp:116-125 adds the OPM boards), and VM::process_state checks
    # every device's typeid name against the stream (x1.cpp:1050-1063), so
    # a state from another chain would fail the apply and roll back. Say
    # why up front instead.
    if m.reinit.soundType != vmSoundType():
      mismatchMessage = tr(msgStateSoundBoardMismatch)
    elif m.reinit.printerType != bx1GetPrinterType(h).int:
      mismatch = tr(msgSettingPrinter)
    elif m.reinit.serialType != bx1GetSerialType(h).int:
      mismatch = tr(msgSettingSerial)
    elif m.reinit.soundFrequency != vmSoundFrequency:
      mismatch = tr(msgSettingSoundFrequency)
    elif m.reinit.soundLatency != vmSoundLatency:
      mismatch = tr(msgSettingSoundLatency)
    if mismatch.len > 0:
      mismatchMessage = trf(msgStateSettingMismatch, mismatch)
    if mismatchMessage.len > 0:
      filedialog.message(tr(msgLoadStateTitle), mismatchMessage)
      return

    # Everything that can fail without touching the machine happens before
    # anything that changes it: unpacking the blob is pure file work, so a
    # corrupt container must not leave the drives holding the state's disks.
    createDir paths.scratchDir() # $TMPDIR can be reaped under a long session
    let blob = scratch("load.vmst")
    try:
      savestate.extractVm(path, blob)
    except CatchableError as e:
      filedialog.message(tr(msgLoadStateTitle), e.msg)
      return

    # From here the machine is this thread's alone: the settings, the
    # remounts and the state blob have to land as one step, and
    # restoreDrives runs frames itself, which the emulation thread must
    # not be doing at the same time.
    var warning = ""
    var applied = false
    withMachineParked:
      # The auto key would go on typing into the restored machine; the
      # core's own load_state stops it for the same reason.
      bx1StopAutoKey(h)
      # Devices read these from the global config as they run rather than
      # storing them in their state, so they have to be in place first.
      bx1SetMonitorType(h, m.runtime.monitorType.cint)
      bx1SetDriveType(h, m.runtime.driveType.cint)
      for drv in 0 ..< FloppyDrives:
        if drv < m.runtime.correctDiskTiming.len:
          bx1SetCorrectDiskTiming(h, drv.cint, m.runtime.correctDiskTiming[drv].cint)
        if drv < m.runtime.ignoreDiskCrc.len:
          bx1SetIgnoreDiskCrc(h, drv.cint, m.runtime.ignoreDiskCrc[drv].cint)
      warning = restoreDrives(m)
      applied =
        bx1VmStateLoad(h, blob.cstring, scratch("rollback.vmst").cstring) != 0
      removeFile(blob)
      # What is still queued was produced by the machine this state has
      # just replaced, so it belongs to nothing any more.
      bx1MuteSound(h)
    refreshFloppyMenus()
    if not applied:
      # The VM state itself rolled back inside the bridge, but the mounts
      # and settings above did not - say so rather than implying the
      # session is untouched.
      filedialog.message(tr(msgLoadStateTitle), tr(msgStateApplyFailed))
      return
    bx1SetCpuPower(h, m.cpuPower.cint)
    syncCpuItems()
    setFullSpeed(m.fullSpeed)
    fullSpeedItem.checked = fullSpeed()
    bx1SetFullSpeed(h, fullSpeed().cint)
    if warning.len > 0:
      filedialog.message(tr(msgLoadStateTitle), warning)

  proc pickSlot(forSaving: bool): int =
    ## Runs the slot grid.
    ##
    ## Nothing is done to the sound on the way out. It used to drop what
    ## the ring held, from when the machine ran on this thread and so
    ## stood still for as long as the picker was up; the machine has a
    ## thread of its own now and keeps playing behind the picker, so there
    ## is nothing stale to drop - and dropping it silenced an ordinary
    ## Save State.
    var cells: seq[SlotCell]
    for slot in 0 ..< StateSlots:
      let info = slotInfo(slot)
      var cell = SlotCell(
        # Bubilator88 numbers its slots from 1 on screen. The files stay
        # slot0..slot9 (paths.stateSlotPath), which nothing but this line
        # and the picker's own indexing ever sees.
        caption: trf(msgSlotCaption, slot + 1),
        # Saving overwrites, so every slot is a target; loading needs one
        # with something in it.
        enabled: forSaving or info.isSome)
      if info.isSome:
        let meta = info.get.meta
        cell.detail = meta.savedAt.fromUnix().local().format(tr(msgStateDateFormat))
        cell.disks = meta.title
        # The title comes from the file the user opened, so it is the
        # better label; a disk's own name (raw D88 bytes, decoded on the
        # AppKit side) only stands in when there is no file name to show.
        if cell.disks.len == 0:
          for d in meta.drives:
            if d.occupied and d.label.len > 0:
              cell.disks = d.label
              break
        cell.thumbnail = savestate.readThumbnail(paths.stateSlotPath(slot))
      cells.add cell
    result = statepicker.choose(
      tr(if forSaving: msgSaveStateTitle else: msgLoadStateTitle), cells)

  controlMenu.addItem(tr(msgQuickSave), proc () =
    saveStateTo(paths.stateSlotPath(QuickSlot)), key = "s")
  quickLoadItem = controlMenu.addItem(tr(msgQuickLoad), proc () =
    loadStateFrom(paths.stateSlotPath(QuickSlot)), key = "l")
  # A caption, not an action: what the quick save currently holds, shown
  # the way the FD0/FD1 menus caption their disk lists.
  quickInfoItem = controlMenu.addItem("")
  quickInfoItem.enabled = false
  controlMenu.addSeparator()
  controlMenu.addItem(tr(msgSaveStateDots), proc () =
    let slot = pickSlot(true)
    if slot >= 0:
      saveStateTo(paths.stateSlotPath(slot)))
  controlMenu.addItem(tr(msgLoadStateDots), proc () =
    let slot = pickSlot(false)
    if slot >= 0:
      loadStateFrom(paths.stateSlotPath(slot)))
  refreshQuickStateMenu()

  # These three are plain toggles rather than radio groups, so they have to
  # flip their own state - AppKit does not do it for a target/action item.
  # Assigned after creation because each closure refers to its own item.
  setFullSpeed(bx1GetFullSpeed(h) != 0)
  fullSpeedItem.checked = fullSpeed()
  driveVmItem.checked = bx1GetDriveVmInOpecode(h) != 0
  romajiItem.checked = bx1GetRomajiToKana(h) != 0
  nativemenu.setAction(fullSpeedItem, proc () =
    fullSpeedItem.checked = not fullSpeedItem.checked
    setFullSpeed(fullSpeedItem.checked)
    bx1SetFullSpeed(h, fullSpeed().cint))
  nativemenu.setAction(driveVmItem, proc () =
    driveVmItem.checked = not driveVmItem.checked
    bx1SetDriveVmInOpecode(h, driveVmItem.checked.cint))
  nativemenu.setAction(romajiItem, proc () =
    romajiItem.checked = not romajiItem.checked
    bx1SetRomajiToKana(h, romajiItem.checked.cint))
  syncCpuItems()

  # --- Disk menu ---
  # One menu for the whole floppy subsystem, with a submenu per drive -
  # Bubilator88's structure (Bubilator88App.swift's DiskCommands) rather
  # than the original's one top-level menu per drive. What each drive holds
  # is a property of that drive, but "open a title" and "the titles I opened
  # recently" are not, and the original's layout has to duplicate them.
  #
  # Each drive submenu keeps the original's own wording and order
  # (src/res/x1turboz.rc) plus the tail its update_floppy_disk_menu builds
  # at runtime. Only two drives, per BluePrint; the original's FD2/FD3 and
  # all four HD menus are not built.
  proc makeInsertAction(drv: int): MenuAction =
    # One Insert for every supported format. A 7z/zip archive or an
    # m3u/m3u8 playlist is opened with exactly the same action as a bare
    # .d88 - loadMedia works out which it is - rather than through a
    # separate "open archive" item the user would have to choose between.
    result = proc () =
      let path = filedialog.openFile(filedialog.DiskExtensions)
      if path.len > 0:
        loadMedia(path, startDrive = drv)
  proc insertBothAction(): MenuAction =
    ## Bubilator88's "Drive 1&2" mount, which is how a 2-disk game is
    ## normally started: no chooser, first disk in FD0, second in FD1.
    result = proc () =
      let path = filedialog.openFile(filedialog.DiskExtensions)
      if path.len > 0:
        loadMedia(path, bothDrives = true)
  proc makeEjectAction(drv: int): MenuAction =
    result = proc () = ejectFloppy(drv)
  proc makeBlankAction(drv, mediaType: int): MenuAction =
    ## Stays inside the drive submenu, as in the original: a blank disk is
    ## made in order to put it in a particular drive, so the drive is part
    ## of the request rather than something to infer. (Bubilator88 has one
    ## Create Blank Disk at the top and picks the first free drive itself.)
    result = proc () =
      let path = filedialog.saveFile(filedialog.BlankDiskExtensions, "blank.d88")
      if path.len > 0 and bx1CreateBlankFloppyDisk(h, path.cstring, mediaType.cint) != 0:
        driveSet[drv] = diskset.build([path])
        driveSource[drv] = path
        discard mountAt(drv, 0)
  proc makeDiskAction(drv, index: int): MenuAction =
    result = proc () = discard mountAt(drv, index)
  proc makeRecentAction(idx: int): MenuAction =
    result = proc () =
      if idx < recent.len:
        # An entry names a title, not a disk in a drive, so reopening one
        # starts it the way a drop does: first two disks across both drives,
        # with no chooser in between.
        loadMedia(recent[idx], bothDrives = true)
  proc makeToggleAction(item: MenuItemRef, drv: int,
                        setter: proc (h: Bx1Handle, drv, enabled: cint) {.cdecl.}): MenuAction =
    ## A per-drive check item that flips its own state (AppKit does not do
    ## that for a target/action item) and pushes the new value to the core.
    result = proc () =
      item.checked = not item.checked
      setter(h, drv.cint, item.checked.cint)

  let diskMenu = nativemenu.addMenu(tr(msgMenuDisk))

  for drv in 0 ..< FloppyDrives:
    let fd = diskMenu.addSubmenu("FD" & $drv)
    fd.addItem(tr(msgInsertDots), makeInsertAction(drv), key = $(drv + 1))
    fd.addItem(tr(msgEject), makeEjectAction(drv))
    # The medium names are the same words in every language, so they are a
    # parameter of one message rather than three messages of their own.
    for mediaType, medium in ["2D", "2DD", "2HD"]:
      fd.addItem(trf(msgInsertBlankDisk, medium), makeBlankAction(drv, mediaType))
    fd.addSeparator()
    writeProtectItems[drv] = fd.addItem(tr(msgWriteProtected))
    let correctTiming = fd.addItem(tr(msgCorrectTiming))
    let ignoreCrc = fd.addItem(tr(msgIgnoreCrcErrors))
    # Self-toggling check items: their closures refer to the item itself,
    # which does not exist while addItem is running, so the action is
    # attached afterwards - and it has to be built by a proc call rather
    # than written inline here. A `let` scoped to this for-loop body is a
    # single binding shared by every closure the loop creates, so written
    # inline, FD0's toggle would silently drive FD1's item (observed: the
    # checkmark never appeared on FD0 because the click was flipping FD1).
    # This is the same trap DevelopmentPlan phase 7 records; proc
    # parameters get a fresh binding per call.
    writeProtectItems[drv].setAction(
      makeToggleAction(writeProtectItems[drv], drv, bx1SetFloppyWriteProtected))
    correctTiming.checked = bx1GetCorrectDiskTiming(h, drv.cint) != 0
    correctTiming.setAction(makeToggleAction(correctTiming, drv, bx1SetCorrectDiskTiming))
    ignoreCrc.checked = bx1GetIgnoreDiskCrc(h, drv.cint) != 0
    ignoreCrc.setAction(makeToggleAction(ignoreCrc, drv, bx1SetIgnoreDiskCrc))
    # The title's disk list, closing the submenu. Hidden entirely while the
    # drive holds nothing - including the separator above it, which would
    # otherwise be left trailing at the end of the menu with nothing under
    # it. From one disk up it shows, which is where this departs from the
    # original's bank list; see refreshFloppyMenu. Each slot is preceded by
    # its own caption slot, which only shows for the first disk of a file
    # when the disks came from several files - fixed slots cannot be
    # inserted between one another later.
    diskSepItems[drv] = fd.addSeparator()
    setCaptionItems[drv] = fd.addItem("")
    setCaptionItems[drv].enabled = false # a caption, not an action
    for i in 0 ..< DiskSlots:
      groupCaptionItems[drv][i] = fd.addItem("")
      groupCaptionItems[drv][i].enabled = false
      diskItems[drv][i] = fd.addItem("", makeDiskAction(drv, i))

  diskMenu.addSeparator()
  # Both drives at once, the way a 2-disk game is normally started. Its own
  # submenu rather than an item in FD0's, so that nothing under FD<n> ever
  # acts on the other drive.
  let bothMenu = diskMenu.addSubmenu("FD0 & FD1")
  bothMenu.addItem(tr(msgInsertDots), insertBothAction(), key = "3")
  bothMenu.addItem(tr(msgEject), proc () =
    for drv in 0 ..< FloppyDrives:
      ejectFloppy(drv))

  diskMenu.addSeparator()
  # A disk mounted out of an archive lives under paths.extractedDir(), so
  # whatever a game saves onto it is written into this app's own storage -
  # a place the user has no reason to look in and every reason not to
  # trust, since a cache entry goes away when its archive changes. This is
  # the way out of it. Bubilator88 answers the same problem the same way
  # (Export Cached Disks…); see archive.exportCache.
  diskMenu.addItem(tr(msgExportExtractedDots), proc () =
    let dest = filedialog.chooseFolder(tr(msgExportChooseFolder))
    if dest.len == 0:
      return
    try:
      let done = archive.exportCache(dest)
      if done.archives == 0:
        filedialog.message(tr(msgExportTitle), tr(msgExportNothing))
      else:
        filedialog.message(tr(msgExportTitle),
          trf(msgExportDone, $done.files, $done.archives))
    except CatchableError as e:
      filedialog.message(tr(msgExportTitle), trf(msgExportFailed, e.msg)))

  diskMenu.addSeparator()
  # One list for the app, not one per drive as the original has: an entry
  # names a title (an archive or playlist as often as a bare image), which
  # is not a per-drive thing. Its own recent.txt, since the core's
  # config_t.recent_*_path fields are never populated by this tree.
  let recentMenu = diskMenu.addSubmenu(tr(msgRecentFiles))
  for i in 0 ..< RecentSlots:
    recentItems[i] = recentMenu.addItem("", makeRecentAction(i))
  recentNoneItem = recentMenu.addItem(tr(msgRecentNone))
  recentNoneItem.enabled = false
  recentMenu.addSeparator()
  recentMenu.addItem(tr(msgClearRecentFiles), proc () =
    recent = @[]
    refreshRecentMenu())

  # No CMT menu. The deck (open/eject, the transport buttons, the waveform
  # shaper) is fully wired through the bridge and stays in the build, but
  # none of it has ever been exercised against a real tape image, so the
  # menu that opened it is left out rather than shipped untested. Only the
  # entry point is gone; loadTape and the bx1_tape_* bindings remain.

  menusBuilt = true
  refreshFloppyMenus()

  # --- Device menu ---
  # Nested like the original's, with three of its submenus left out:
  #
  # * Printer and Serial, whose OSD backends are no-op stubs in this port
  #   (DevelopmentPlan 0.6 group C), so every entry would be inert.
  # * Boot Device. `config.drive_type` no longer configures any drive: the
  #   branch that did is commented out in the vendored core itself
  #   (x1.cpp:481-492), which leaves every drive initialized as 2D/300rpm
  #   and lets the guest re-type them from the inserted medium through
  #   ports 0xffe/0xfff (floppy.cpp:72-90). All the setting still does is
  #   supply DIP switch bits at 0x1ff0, which no commercial title needs
  #   changed. The value itself stays reachable - a save state restores it
  #   (see loadState above) - only the menu that offered it is gone.
  #
  # A small helper covers the four radio groups below. Written as a proc
  # taking the values it needs rather than inline in each loop, for the
  # closure-binding reason documented at makeToggleAction above.
  let deviceMenu = nativemenu.addMenu(tr(msgMenuDevice))

  proc addRadioGroup(menu: nativemenu.Menu, labels: seq[string], values: seq[int],
                     current: int, apply: proc (value: cint) {.closure.}) =
    ## Builds a set of items where clicking one checks it and clears the
    ## rest. `values` are the core's own constants, kept explicit rather
    ## than derived from the item index so a group whose constants are not
    ## a dense 0..n range still works. seq rather than openArray: the
    ## per-item closures below capture them, which Nim does not allow for
    ## an openArray.
    var group = newSeq[MenuItemRef](labels.len)
    proc makeAction(idx: int): MenuAction =
      result = proc () =
        apply(values[idx].cint)
        for j in 0 ..< group.len:
          group[j].checked = (j == idx)
    for i in 0 ..< labels.len:
      group[i] = menu.addItem(labels[i], makeAction(i))
      group[i].checked = (values[i] == current)

  let keyboardMenu = deviceMenu.addSubmenu(tr(msgKeyboard))
  keyboardMenu.addRadioGroup(
    @[tr(msgKeyboardModeA), tr(msgKeyboardModeB)], @[0, 1], bx1GetKeyboardType(h).int,
    proc (v: cint) = bx1SetKeyboardType(h, v))

  let soundMenu = deviceMenu.addSubmenu(tr(msgSound))
  # The OPM boards are added by VM's constructor, which copies
  # config.sound_type into a member once (x1.cpp:76) and never rereads it,
  # so a change here cannot reach the machine that is running. It reaches
  # the next one: the original applies such a change by throwing the VM
  # away and building a new one, and EMU::reset() does exactly that when it
  # finds config.sound_type has moved since the build (emu.cpp:281-311).
  # So the wait is one reset, not one launch - Control > Reset is enough,
  # and quitting works only because the setting is in config.ini by then
  # (bx1SaveConfig writes Control/SoundType, config.cpp:199 and 453).
  # Comparing against what the VM was built with rather than against the
  # previous choice means going back to the original board says nothing.
  soundMenu.addRadioGroup(
    @["PSG", "CZ-8BS1 x1", "CZ-8BS1 x2"], @[0, 1, 2], vmSoundType(),
    proc (v: cint) =
      bx1SetSoundType(h, v)
      if v.int != vmSoundType():
        filedialog.message(tr(msgSoundBoardTitle), tr(msgSoundBoardBody)))
  soundMenu.addSeparator()
  # The drive noise the machine mixes in alongside the synthesized
  # channels, played from WAVs this app generates at startup rather than
  # ships (fddnoise.nim). Unlike the sound board above, this one is live:
  # MB8877::update_config re-applies the mute to all three noise players
  # (mb8877.cpp:1695-1706). The original's three CMT sources (noise,
  # signal, voice) sit here too, but they are left out for the same reason
  # as the CMT menu above: nothing in this app can put a tape in the deck
  # to hear them.
  proc addToggle(menu: nativemenu.Menu, label: string, get: proc (): bool {.closure.},
                 set: proc (on: cint) {.closure.}) =
    ## A check item that flips its own state (AppKit does not) and pushes
    ## the new value into the core.
    let item = menu.addItem(label)
    item.checked = get()
    item.setAction(proc () =
      item.checked = not item.checked
      set(item.checked.cint))
  soundMenu.addToggle(tr(msgPlayFddNoise),
    proc (): bool = bx1GetSoundNoiseFdd(h) != 0, proc (on: cint) = bx1SetSoundNoiseFdd(h, on))

  let displayMenu = deviceMenu.addSubmenu(tr(msgDisplay))
  # "High Resolution" (0) has a genuine glyph rendering fault that the
  # original Windows build shows too, so it is not the default here; see
  # bx1_create and DevelopmentPlan phase 5.
  displayMenu.addRadioGroup(
    @[tr(msgHighResolution), tr(msgStandard)], @[0, 1], bx1GetMonitorType(h).int,
    proc (v: cint) = bx1SetMonitorType(h, v))
  displayMenu.addSeparator()
  displayMenu.addToggle(tr(msgScanline),
    proc (): bool = bx1GetScanLine(h) != 0, proc (on: cint) = bx1SetScanLine(h, on))

  # --- Volume window (Host > Volume) ---
  # The original opens a modal dialog of per-device L/R trackbars
  # (IDD_VOLUME in x1turboz.rc). Same idea here, as a window built once at
  # startup and shown on demand, which edits the running machine live where
  # the original edited a copy and committed it on OK. The panel itself is
  # AppKit (volumepanel.nim); what it reports is turned into levels here,
  # which is the only side that can see the VM.
  let volumeCount = bx1GetSoundVolumeCount().int
  let printerType = bx1GetPrinterType(h).int
  # Device names come from the core's own sound_device_caption table
  # ("PSG", "CZ-8BS1 #1", "CZ-8BS1 #2", "JAST SOUND", "CMT (Signal)",
  # "Noise (FDD)", "Noise (CMT)"), so the labels cannot drift from the
  # channels they control - and the tape ones are recognised by that same
  # caption rather than by index, which the table is free to renumber.
  #
  # JAST SOUND (channel 3) is left out for a reason of the same kind: it is
  # the printer port's 8-bit PCM, which VM::set_sound_device_volume only
  # reaches at printer_type 3 (x1.cpp:676), and this port has no printer UI
  # and no default that selects it - the channel can never exist here.
  var volumeDevices: seq[int] # core device indices, absent ones filtered out
  for i in 0 ..< volumeCount:
    if "CMT" in $bx1GetSoundDeviceCaption(i.cint): continue
    if i == 3 and printerType != 3: continue
    volumeDevices.add i

  proc volumeDeviceBuilt(device: int): bool =
    ## Whether the running machine actually has the channel behind a slider.
    ## VM::set_sound_device_volume is a hardcoded index switch
    ## (x1.cpp:664-695), so asking by index here is exactly as stable as the
    ## core: channel 1 is the first OPM board, channel 2 the second. The
    ## question is put to `vmSoundType()`, the board count the VM was built
    ## with, and not to the live config value - a board picked in Device >
    ## Sound only arrives at the next reset, so until then the config says
    ## one thing and the machine these sliders talk to says another.
    case device
    of 1: vmSoundType() >= 1
    of 2: vmSoundType() >= 2
    else: true

  # Master and Link L/R are this port's own, not the original's. The core
  # has no master level - volume exists per device only - so the master is
  # mixed in here: what the user set stays in the per-device sliders and in
  # config.ini, and the machine is given the sum, clamped to the range the
  # core accepts. Writing the sum to config instead would bake the
  # attenuation into the stored levels and apply it again next launch.
  var volumeMaster = max(-40, min(0, hostCfg.getInt("VolumeMaster", 0)))
  var volumeLinked = hostCfg.getBool("VolumeLinkLR", false)
  proc volumeMixed(level: int): int = max(-40, min(0, level + volumeMaster))
  proc applyVolume(dev: int) =
    ## Pushes one device's level to the machine, master included. Nothing
    ## is stored: the caller decides whether this was a change worth
    ## remembering (storeVolume) or only a re-application of one.
    bx1ApplyVolume(h, dev.cint,
      volumeMixed(volumepanel.level(dev, ChannelL)).cint,
      volumeMixed(volumepanel.level(dev, ChannelR)).cint)
  proc storeVolume(dev: int) =
    ## Remembers one device's levels as the user set them, then applies the
    ## mixed result. bx1SetVolume also applies what it stores, so the order
    ## matters: the machine must end up holding the mixed value.
    bx1SetVolume(h, dev.cint, volumepanel.level(dev, ChannelL).cint,
      volumepanel.level(dev, ChannelR).cint)
    applyVolume(dev)
  proc applyAllVolumes() =
    for i in volumeDevices:
      if volumeDeviceBuilt(i):
        applyVolume(i)
  proc equalizeChannels() =
    ## Brings every R channel onto its L. Run when the link is switched on
    ## and once at startup if it was on when the app last quit - the levels
    ## come back from config.ini as the two numbers they are, so without
    ## this the panel could open showing rows the link says are equal and
    ## they visibly are not.
    for i in volumeDevices:
      if volumeDeviceBuilt(i) and
          volumepanel.level(i, ChannelR) != volumepanel.level(i, ChannelL):
        volumepanel.setLevel(i, ChannelR, volumepanel.level(i, ChannelL))
        storeVolume(i)

  volumepanel.setOnChange(proc (device, channel, value: int) =
    if device == volumepanel.Master:
      volumeMaster = value
      applyAllVolumes()
    else:
      if volumeLinked:
        let other = if channel == ChannelL: ChannelR else: ChannelL
        volumepanel.setLevel(device, other, value)
      storeVolume(device))
  # One switch for the whole panel rather than one per device: the two
  # channels of a device are almost always wanted at the same level, and a
  # checkbox per group would add a row to every one of them. Ticking it
  # brings every R up to its L there and then, rather than waiting for each
  # to be dragged: a panel that says the channels are linked while showing
  # rows where they visibly are not is the confusing half of both worlds.
  volumepanel.setOnLink(proc (linked: bool) =
    volumeLinked = linked
    if volumeLinked:
      equalizeChannels())
  # Same as the original's Reset button: back to 0dB, which is the config's
  # own default, and the master with it.
  volumepanel.setOnReset(proc () =
    volumeMaster = 0
    volumepanel.setLevel(volumepanel.Master, ChannelL, 0)
    for i in volumeDevices:
      # Greyed rows are left alone. The original zeroes all seven channels,
      # but nothing here has offered the user a way to change a channel its
      # machine does not have, so this must not write one either - a
      # disabled control that still edits the config is not disabled.
      if volumeDeviceBuilt(i):
        volumepanel.setLevel(i, ChannelL, 0)
        volumepanel.setLevel(i, ChannelR, 0)
        storeVolume(i))

  volumepanel.begin(tr(msgVolume), tr(msgVolumeMaster), tr(msgVolumeLinkLR),
    tr(msgReset))
  volumepanel.setLevel(volumepanel.Master, ChannelL, volumeMaster)
  volumepanel.setLinked(volumeLinked)
  for i in volumeDevices:
    volumepanel.addDevice(i, $bx1GetSoundDeviceCaption(i.cint))
    volumepanel.setLevel(i, ChannelL, bx1GetVolumeL(h, i.cint).int)
    volumepanel.setLevel(i, ChannelR, bx1GetVolumeR(h, i.cint).int)
  volumepanel.finish()

  proc refreshVolumeAvailability() =
    ## Greys the rows whose board this machine does not have, and un-greys
    ## them when a reset has since built one. Called on every show, not
    ## once: Device > Sound plus Control > Reset changes the answer while
    ## the panel is alive.
    for i in volumeDevices:
      volumepanel.setDeviceEnabled(i, volumeDeviceBuilt(i))
  refreshVolumeAvailability()
  # The machine starts out holding config.ini's per-device levels; a master
  # restored from the host settings has to be mixed into them once here, or
  # it would not be heard until something moved a slider.
  if volumeLinked:
    equalizeChannels()
  applyAllVolumes()
  afterReset = applyAllVolumes

  proc showVolumeWindow() =
    refreshVolumeAvailability()
    volumepanel.show()

  # --- Host menu ---
  # Item order and wording follow the original (x1turboz.rc IDR_MENU1 >
  # POPUP "Host"). The five of its entries that are not here, and why, are
  # recorded in docs/dev/HostMenu.md:
  #
  # * Rec Movie 60/30/15fps - no video encoder, and none that is portable.
  # * Filter (RGB Filter / None) - the original's filter only does anything
  #   on a buffer that has already been scaled up by an integer factor
  #   (win32/osd_screen.cpp:617), so at this port's default 1x it would be
  #   an item that visibly does nothing. It is also not the same thing as
  #   Device > Display > Scanline, which is the VM's own.
  # * Screen > Rotate - no X1 title needs a rotated screen.
  # * Input (Joystick #1/#2, Joystick To Keyboard) - all three are binding
  #   dialogs, and joystick input is not wired up yet.
  # * Use Direct2D1 / Direct3D9 / Use DirectInput / Disable Windows 8 DWM -
  #   Win32 renderer and input backends with no counterpart here.
  #
  # Wait Vsync is left out for a different reason than the rest of that
  # group: SDL does have a vsync present (SDL_RENDERER_PRESENTVSYNC), but
  # blocking on the display's 60Hz would fight the wall-clock 61.94Hz
  # pacing the draw loop below runs on.
  let hostMenu = nativemenu.addMenu(tr(msgMenuHost))

  # Rec Sound / Stop / Capture Screen. The original routes these through its
  # OSD; this port's OSD has them as empty stubs and the core is not to be
  # modified, so they are done from the host's own copies of the same data -
  # see capture.nim.
  var recSoundItem, recStopItem: MenuItemRef
  recSoundItem = hostMenu.addItem(tr(msgRecSound), proc () =
    # The lock keeps the audio thread out of feedSound while the file is
    # being created underneath it.
    lockAudioDevice(audioDev)
    let path = capture.startSoundRecording(soundRate)
    unlockAudioDevice(audioDev)
    if path.len == 0:
      filedialog.message(tr(msgRecSound),
        trf(msgRecSoundFailed, paths.recordingsDir()))
    recSoundItem.enabled = not capture.isSoundRecording()
    recStopItem.enabled = capture.isSoundRecording())
  recStopItem = hostMenu.addItem(tr(msgRecStop), proc () =
    lockAudioDevice(audioDev)
    capture.stopSoundRecording(soundRate)
    unlockAudioDevice(audioDev)
    recSoundItem.enabled = true
    recStopItem.enabled = false)
  # The original greys out whatever is not applicable each time the menu
  # opens; here the two items keep each other in step, and the status timer
  # re-syncs them in case a write error stopped the recording on its own.
  recStopItem.enabled = false
  hostMenu.addItem(tr(msgCaptureScreen), proc () =
    # The core's framebuffer, i.e. the guest's own picture: no status bar,
    # no window scaling, whatever the window happens to look like.
    bx1Lock(h)
    let written = capture.saveScreenshot(bx1GetFramebuffer(h), ScreenWidth,
                                         ScreenHeight)
    bx1Unlock(h)
    if written.len == 0:
      filedialog.message(tr(msgCaptureScreen),
        trf(msgCaptureScreenFailed, paths.screenshotsDir())))
  hostMenu.addSeparator()

  # --- Host > Screen ---
  let screenMenu = hostMenu.addSubmenu(tr(msgScreen))
  var windowItems: seq[MenuItemRef]
  var fullscreenItem: MenuItemRef

  proc syncScreenItems() =
    for i in 0 ..< windowItems.len:
      windowItems[i].checked = (not isFullscreen) and (i + 1 == windowScale)
    fullscreenItem.checked = isFullscreen

  proc applyFullscreen(on: bool) =
    if sdlWin != nil:
      discard sdlWin.setFullscreen(if on: SDL_WINDOW_FULLSCREEN_DESKTOP else: 0)
    isFullscreen = on
    if not on:
      # Leaving fullscreen restores whatever window scale is selected: SDL
      # keeps the pre-fullscreen size, which may predate a scale change made
      # while fullscreen.
      applyWindowLayout()
    syncScreenItems()

  proc makeWindowScaleAction(scale: int): MenuAction =
    ## Per-item rather than one shared closure, for the binding reason
    ## documented at addRadioGroup above.
    result = proc () =
      windowScale = scale
      bx1SetWindowMode(h, cint(scale - 1))
      if isFullscreen:
        applyFullscreen(false) # picking a window size means leaving fullscreen
      else:
        applyWindowLayout()
        syncScreenItems()

  for n in 1 .. maxWindowScale():
    windowItems.add screenMenu.addItem(trf(msgWindowScale, n),
      makeWindowScaleAction(n))
  # The original lists one item per display mode it enumerated
  # ("Fullscreen 640x400" and so on) because entering fullscreen there
  # changes the display's resolution. On macOS that is not how fullscreen
  # works, so this is a single desktop-fullscreen item.
  #
  # It toggles rather than only entering fullscreen, so there is always a
  # way back out: in fullscreen the menu bar is only reachable by knowing to
  # push the pointer at the top of the screen. Ctrl-Cmd-F is what macOS uses
  # for Enter/Exit Full Screen everywhere else - not the original's
  # Alt+Enter, since Option is the X1's GRAPH key here (keymap.nim).
  fullscreenItem = screenMenu.addItem(tr(msgFullscreen),
    proc () = applyFullscreen(not isFullscreen),
    key = "f", mods = ModCommand or ModControl)
  syncScreenItems()

  screenMenu.addSeparator()
  # The original relabels these two at runtime from the machine's own
  # dimensions ("Window: Aspect Ratio %d:%d", winmain.cpp:2076-2080); same
  # here, from the values the bridge reports.
  screenMenu.addRadioGroup(
    @[trf(msgWindowAspect, ScreenWidth, ScreenHeight),
      trf(msgWindowAspect, ScreenWidth, aspectHeight)],
    @[0, 1], stretchType,
    proc (v: cint) =
      stretchType = v.int
      bx1SetWindowStretchType(h, v)
      applyWindowLayout())

  screenMenu.addSeparator()
  screenMenu.addRadioGroup(
    @[tr(msgFullscreenDotByDot),
      trf(msgFullscreenStretchAspect, ScreenWidth, ScreenHeight),
      trf(msgFullscreenStretchAspect, ScreenWidth, aspectHeight),
      tr(msgFullscreenStretchFill)],
    @[0, 1, 2, 3], fullscreenStretch,
    proc (v: cint) =
      fullscreenStretch = v.int
      bx1SetFullscreenStretchType(h, v))

  screenMenu.addSeparator()
  # The original's Host > Filter offers the core's own USE_SCREEN_FILTER
  # modes, which this build does not implement (the OSD side is a stub).
  # These two are SDL's own texture scaling modes instead, which is the
  # whole of what it offers: there is no bicubic filter in SDL2.
  screenMenu.addRadioGroup(
    @[tr(msgFilterNearest), tr(msgFilterBilinear)],
    @[0, 1], scaleQuality,
    proc (v: cint) =
      scaleQuality = v.int
      applyScaleQuality())

  # --- Host > Sound ---
  let hostSoundMenu = hostMenu.addSubmenu(tr(msgSound))
  # Sample rate and latency are stored and take effect at the next launch.
  # That is not a shortcoming of this port: EMU reads both in its
  # constructor to size the buffer create_sound() fills and never again
  # (EMU::update_config only forwards to the VM, and EMU::reset()'s
  # reinitialize path reuses the rate it already has - emu.cpp:313), so the
  # original's own menu behaves exactly the same way.
  #
  # The seventh entry is 62500Hz, not the table's 48000Hz: x1.h overrides
  # that slot for this machine, and the original's own resource file says
  # 62500Hz too.
  hostSoundMenu.addRadioGroup(
    @["2000Hz", "4000Hz", "8000Hz", "11025Hz",
      "22050Hz", "44100Hz", "62500Hz", "96000Hz"],
    @[0, 1, 2, 3, 4, 5, 6, 7], bx1GetSoundFrequency(h).int,
    proc (v: cint) = bx1SetSoundFrequency(h, v))
  hostSoundMenu.addSeparator()
  hostSoundMenu.addRadioGroup(
    @["50msec", "100msec", "200msec", "300msec", "400msec"],
    @[0, 1, 2, 3, 4], bx1GetSoundLatency(h).int,
    proc (v: cint) = bx1SetSoundLatency(h, v))
  hostSoundMenu.addSeparator()
  # This one is live: the VM's event scheduler reads it on every mix
  # (vm/event.cpp:502).
  hostSoundMenu.addRadioGroup(
    @[tr(msgRealtimeMix), tr(msgLightWeightMix)], @[1, 0],
    bx1GetSoundStrictRendering(h).int,
    proc (v: cint) = bx1SetSoundStrictRendering(h, v))
  hostSoundMenu.addSeparator()
  # Where the original keeps it: ID_SOUND_VOLUME is inside POPUP "Sound".
  hostSoundMenu.addItem(tr(msgVolume), proc () = showVolumeWindow())

  hostMenu.addSeparator()
  let statusBarItem = hostMenu.addItem(tr(msgShowStatusBar))
  statusBarItem.checked = showStatusBar
  statusBarItem.setAction(proc () =
    statusBarItem.checked = not statusBarItem.checked
    showStatusBar = statusBarItem.checked
    applyWindowLayout())

  # --- Host > Language ---
  # The UI language, which the app normally takes from the host (see
  # i18n.nim). This is the override, for the case the host's language and
  # the one the user wants to read software in are not the same - a common
  # enough combination that leaving it to a hand-edited settings file would
  # be leaving it unreachable.
  #
  # It stores a preference and says so: every menu title was read out of the
  # catalog while the menu bar was being built, and nothing rebuilds it, so
  # a language switched here arrives at the next launch. Retitling every
  # item in place is possible (nativemenu keeps a handle on each) but would
  # have to be kept in step with every future menu by hand.
  let languageMenu = hostMenu.addSubmenu(tr(msgLanguage))
  languageMenu.addRadioGroup(
    @[tr(msgLanguageAuto), tr(msgLanguageEnglish), tr(msgLanguageJapanese)],
    @[0, 1, 2],
    (case uiLanguage.toLowerAscii()
     of "en": 1
     of "ja": 2
     else: 0),
    proc (v: cint) =
      let chosen = (case v
                    of 1: "en"
                    of 2: "ja"
                    else: "auto")
      if chosen != uiLanguage:
        uiLanguage = chosen
        filedialog.message(tr(msgLanguageChangedTitle), tr(msgLanguageChangedBody)))

  # Nearest-neighbor scaling for everything created from here on, the status
  # bar's glyph texture included: the 8x8 ANK font is a bitmap and linear
  # filtering (SDL's default for the accelerated renderer) blurs it at any
  # non-integer window size. The guest picture overrides this per texture
  # from Host > Screen - see applyScaleQuality.
  discard setHint("SDL_RENDER_SCALE_QUALITY", "0")

  # Native 640x400, not the core's own WINDOW_HEIGHT_ASPECT=480 (which
  # stretches the picture to approximate the X1's non-square CRT pixels,
  # like the original Windows app's default window does). Per user
  # feedback the stretched look reads as distorted on a modern display;
  # this project prioritizes a clean, square-pixel picture over
  # replicating that CRT-accurate aspect ratio.
  # Prefer Metal explicitly rather than taking whatever SDL ranks first.
  # Crash reports from this app show SIGBUS inside SDL's Cocoa OpenGL path
  # (-[SDL3View updateLayer] -> ScheduleContextUpdates ->
  # +[NSOpenGLContext currentContext], jumping to a poisoned pointer)
  # within a third of a second of launch. Nothing here wants OpenGL - the
  # renderer only blits one streaming texture - and Metal is present on
  # every Mac this project targets (macOS 13.5+), so the simplest fix is
  # to not have that code path available to be taken. SDL falls back on
  # its own if the hint names a driver it cannot provide.
  discard setHint("SDL_RENDER_DRIVER", "metal")

  # Created hidden and shown only once the renderer exists. AppKit can
  # otherwise display the window's backing layer in the window between
  # SDL_CreateWindow and SDL_CreateRenderer, i.e. while the view has no
  # renderer backing it yet - which is exactly the state the crash above
  # happens in.
  # The application's name alone: this is the only window the user works
  # in, so naming what it shows would only repeat what the app is.
  # Restored where the last run left it, unless there is no remembered
  # position or it no longer falls on any screen - then SDL places the
  # window itself.
  let restorePos = hasSavedWindowPos and windowPosOnScreen(windowX, windowY)
  sdlWin = createWindow("BubiX1turboZ",
    (if restorePos: windowX else: SDL_WINDOWPOS_UNDEFINED.cint),
    (if restorePos: windowY else: SDL_WINDOWPOS_UNDEFINED.cint),
    (ScreenWidth * windowScale).cint,
    (guestHeight() * windowScale).cint + statusBarHeight(), SDL_WINDOW_HIDDEN)
  if sdlWin == nil:
    fail "SDL_CreateWindow failed: " & $getError()
  renderer = createRenderer(sdlWin, -1, Renderer_Accelerated)
  if renderer == nil:
    fail "SDL_CreateRenderer failed: " & $getError()
  sdlWin.showWindow()
  # Whatever SDL made of the request above is the position to remember from
  # here on, so that a run which never moves the window still writes back a
  # position it actually had.
  sdlWin.getPosition(windowX, windowY)

  # Logged because the crash above is specific to one backend: if it ever
  # comes back, the first question is which renderer was in use.
  var rendererInfo: RendererInfo
  if renderer.getRendererInfo(addr rendererInfo) == 0:
    echo "renderer: ", $rendererInfo.name
  let texture = renderer.createTexture(SDL_PIXELFORMAT_ARGB8888,
    SDL_TEXTUREACCESS_STREAMING, ScreenWidth, ScreenHeight)
  if texture == nil:
    fail "SDL_CreateTexture failed: " & $getError()
  screenTexture = texture
  applyScaleQuality()
  # Alpha comes back as 0 from the core (see docs/dev/DevelopmentPlan.md
  # 1.4); blending it would make the whole picture transparent.
  discard texture.setTextureBlendMode(BlendMode_None)
  # SDL2 starts with text input enabled on most platforms, but say so
  # explicitly: without TextInput events the Romaji to Kana option would
  # leave the guest with no keyboard at all (see the TextInput handler).
  startTextInput()
  # Deliberately no SDL_RenderSetLogicalSize: drawing happens in real window
  # points so that guestRect above can place the picture itself, which is
  # what the four fullscreen stretch modes need.

  # Audio: must open at the core's *actual* rate, not a requested one
  # (X1turboZ overrides the "48000Hz" table slot to 62500Hz - see
  # bx1_get_actual_sound_rate's doc comment); soundRate is read at the top
  # of main, where the Host menu can reach it too.
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
    # Host > Rec Sound writes the whole buffer, underrun silence included:
    # the file is meant to be what came out of the speakers, not a
    # gap-closed edit of it. A no-op unless a recording is running.
    capture.feedSound(stream, framesWanted.int)
  desired.userdata = cast[pointer](h)
  var obtained: AudioSpec
  audioDev = openAudioDevice(nil, 0.cint, addr desired, addr obtained, 0)
  if audioDev == 0:
    fail "SDL_OpenAudioDevice failed: " & $getError()
  echo &"audio device opened at {obtained.freq}Hz (requested {soundRate}Hz)"
  pauseAudioDevice(audioDev, 0)

  # How much audio the pacing loop keeps queued. Derived from the latency
  # the core was *built* with, not from config.sound_latency as it stands
  # now: create_sound() synthesizes one whole latency window per call, so a
  # target that disagrees with it makes the loop overshoot by that ratio.
  # A Host > Sound > latency change only reaches the core at the next
  # launch, so it must not move this.
  emuTargetFrames = cint(soundRate.float * bx1GetActualSoundLatency(h))

  # The machine gets a thread of its own from here on. Started only once
  # everything it reads is in place - the handle, the pacing target, and an
  # audio device already playing, since an unopened device would leave the
  # ring buffer full and the pacing loop with nothing to do.
  emuHandle = h
  # So the first pass renders something rather than presenting the blank
  # buffer the core allocated.
  drawPending.store(true, moRelaxed)
  createThread(emuThread, emulationLoop)

  # The status bar prints with the machine's own 8x8 ANK glyphs; see
  # ankfont.nim for why this rather than SDL_ttf. A missing font ROM leaves
  # `ready == false` and every draw becomes a no-op, so the lamps still work.
  var font = ankfont.load(renderer, paths.romsDir())
  if not font.ready:
    stderr.writeLine "bubix1turboz: no 8x8 font ROM in " & paths.romsDir() &
      "; status bar text disabled"

  var fpsDisplay = 0
  var drawnFrames = 0
  var lastFpsTicks = getTicks()
  var lastStatusTicks = lastFpsTicks
  const StatusPollMs = 200'u32
  # X1turboZ runs at FRAMES_PER_SEC 61.94 (vm/x1/x1.h), which is not a whole
  # number of milliseconds - hence a float accumulator rather than an
  # integer interval, so the error does not compound into visible drift.
  const FrameIntervalMs = 1000.0 / 61.94
  const FullSpeedDrawIntervalMs = 100.0
    ## Ten pictures a second while Full Speed is on: enough for the user to
    ## follow what the machine is doing, few enough that the emulation
    ## thread keeps the lock nearly all of the time.
  var nextDrawTicks = lastFpsTicks.float

  proc drawFrame() =
    ## Renders one frame of the guest's screen plus the status bar.
    ##
    ## The picture itself is rendered by the emulation thread (see
    ## `emulationLoop`); this copies whatever it last left in the core's
    ## buffer, under the lock so that a render cannot be in progress
    ## while the copy runs.
    bx1Lock(h)
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
    bx1Unlock(h)
    # Ask for the next one now rather than just before the next copy, so
    # that the emulation thread has the whole frame interval to produce it
    # and the picture is never a frame behind.
    drawPending.store(true, moRelaxed)

    # The drawable's real size in points. Windowed it is what
    # applyWindowLayout set; fullscreen it is the display's.
    var outW = (ScreenWidth * windowScale).cint
    var outH = (guestHeight() * windowScale).cint + statusBarHeight()
    discard renderer.getRendererOutputSize(addr outW, addr outH)
    let barH = statusBarHeight()
    let areaH = max(0.cint, outH - barH)

    # Black, not the last colour the status bar drew with: in the
    # dot-by-dot and aspect-preserving fullscreen modes this is what fills
    # the border around the picture.
    renderer.setDrawColor(0, 0, 0, 255)
    renderer.clear()
    var screenDst = guestRect(outW, areaH)
    renderer.copy(texture, nil, addr screenDst)

    # Status bar: drawn directly into the emulator's own window, not as a
    # separate GUI window - a second floating window is easy to lose
    # behind the main one (confirmed: an earlier attempt placed it
    # off-screen and nobody noticed). Layout and wording mirror the
    # original Windows app's own status bar (winmain.cpp's
    # update_status_bar): "FD:" followed by one lamp per drive. All of it
    # comes from the vendored core unmodified. No HDD section: this app has
    # no UI path to mount a hard disk (BluePrint/CLAUDE.md - commercial X1
    # games did not use one), so it would only ever read as idle. The
    # original's "CMT:" section is left out for the same reason - no tape
    # can be inserted here, so it would only ever read as empty.
    #
    # The one deliberate departure from the original: the frame rate.
    # The original puts it in the window title ("%s - %d fps (%d %%)");
    # here it sits at the right end of the bar instead, where a title
    # bar the user may not be looking at cannot hide it.
    if showStatusBar:
      renderer.setDrawColor(20, 20, 20, 255)
      var barRect = rect(0.cint, areaH, outW, barH)
      discard renderer.fillRect(addr barRect)

      const
        lampW = 14.cint # the original's indicator bitmaps are 14x12
        lampH = 12.cint
        labelColor = (200'u8, 200'u8, 200'u8)
        # Three lamp states, matching the original's access_off /
        # access_on / access_green bitmaps. The third is selected by
        # floppy_disk_indicator_color(), which the core raises only for a
        # drive currently configured as 2HD - so a 2D game legitimately
        # never shows it.
        lampOff = (60'u8, 60'u8, 60'u8)
        lampOn = (230'u8, 60'u8, 50'u8)
        lampOn2 = (60'u8, 220'u8, 70'u8)

      # The bar keeps its height in points whatever the window scale is -
      # scaling 8x8 glyphs up with the picture would make the text huge.
      let lampY = areaH + (barH - lampH) div 2
      let textY = areaH + (barH - ankfont.GlyphHeight.cint) div 2

      var x = 6.cint
      x = font.draw(renderer, x, textY, "FD:", labelColor[0], labelColor[1], labelColor[2])
      x += 4
      for drv in 0 ..< FloppyDrives:
        let (r, g, b) =
          if bx1IsFloppyDiskAccessed(h, drv.cint) == 0: lampOff
          elif bx1FloppyDiskIndicatorColor(h, drv.cint) != 0: lampOn2
          else: lampOn
        renderer.setDrawColor(r, g, b, 255)
        var lampRect = rect(x, lampY, lampW, lampH)
        discard renderer.fillRect(addr lampRect)
        x += lampW + 2

      let fpsText = $fpsDisplay & " fps"
      font.draw(renderer, outW - font.width(fpsText) - 6, textY, fpsText,
        labelColor[0], labelColor[1], labelColor[2])

    renderer.present()
    inc drawnFrames

  var ev = sdl2.defaultEvent
  while running():
    while pollEvent(ev):
      case ev.kind
      of QuitEvent:
        setRunning(false)
      of KeyDown:
        let vk = keymap.toVk(ev.key.keysym.scancode)
        if vk != 0:
          bx1KeyDown(h, vk, ev.key.repeat.cint)
      of KeyUp:
        let vk = keymap.toVk(ev.key.keysym.scancode)
        if vk != 0:
          bx1KeyUp(h, vk)
      of TextInput:
        # The character a keystroke produced, forwarded alongside the
        # physical key above - the same pairing Win32 does with WM_KEYDOWN
        # and WM_CHAR. The core ignores this unless Romaji to Kana is on,
        # and when it is on this is the only way ordinary keys reach the
        # guest at all: EMU::key_down stops forwarding them and expects
        # key_char to feed the auto key instead. Without it, switching that
        # option on makes the keyboard go completely dead.
        for i in 0 ..< ev.text.text.len:
          let ch = ev.text.text[i].int
          if ch == 0:
            break
          # SDL delivers UTF-8; the core's auto key table is ASCII/JIS X
          # 0201, so anything multi-byte has no key to map to anyway.
          if ch < 0x80:
            bx1KeyChar(h, ch.cint)
      of WindowEvent:
        case ev.window.event
        of WindowEvent_Close:
          setRunning(false)
        of WindowEvent_Moved:
          # Only while the window is a window: on macOS the transition out
          # of fullscreen is animated, so moves carrying the fullscreen
          # origin can still arrive after isFullscreen has gone false.
          if not isFullscreen:
            windowX = ev.window.data1
            windowY = ev.window.data2
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
          # A drop is "start this title", so it fills both drives without
          # asking which disk to use - the same choice Bubilator88 makes
          # for its own drop handler.
          loadMedia($raw, bothDrives = true, reset = true)
          sdlFreeStr(raw)
      else:
        discard

    # Present. The machine itself is advanced on its own thread (see
    # `emulationLoop`); all this loop decides is when a finished frame is
    # worth putting on the screen.
    #
    # Drawing runs on a wall clock rather than "whenever the VM advanced".
    # Neither of the obvious alternatives works: presenting every pass
    # spins as fast as the GPU accepts frames (measured ~170/sec on a
    # 61.94Hz machine, burning a core to show nothing new), and presenting
    # once per emulated frame gives ~10/sec, because the emulation thread
    # advances in bursts - the core synthesizes a whole sound_latency
    # window (100ms, ~6 frames) per create_sound call, then nothing until
    # the ring buffer drains. This is also how the original app works: its
    # VM is paced by the DirectSound cursor while WM_PAINT redraws on a
    # timer of its own.
    #
    # Full Speed draws less often, because the point of it is to give the
    # machine every cycle the host has and each present costs the
    # emulation thread its turn at the VM lock. Not much less often,
    # though: at one draw a second the picture is indistinguishable from a
    # frozen one, and Full Speed is something the user watches to see how
    # far the machine has got.
    let drawInterval =
      if fullSpeed(): FullSpeedDrawIntervalMs
      else: FrameIntervalMs
    let frameTicks = getTicks()
    # The next draw is resynced whenever it is more than one interval away
    # in *either* direction. Behind, because catching up on a stall (or an
    # occluded window) would mean a burst of back-to-back presents. Ahead,
    # because switching Full Speed off leaves a deadline set a whole second
    # from now, and waiting it out would freeze the picture just as the
    # user asked to watch it again.
    if abs(nextDrawTicks - frameTicks.float) > drawInterval:
      nextDrawTicks = frameTicks.float
    if frameTicks.float < nextDrawTicks:
      delay(1)
    else:
      nextDrawTicks += drawInterval
      drawFrame()

    # Status is sampled on a timer rather than every frame, the way the
    # original app polls its own status bar (winmain.cpp uses 200ms).
    let nowTicks = getTicks()
    if nowTicks - lastStatusTicks >= StatusPollMs:
      # The FD menus are refreshed on this timer because a disk change
      # does not take effect immediately: swapping into an occupied drive
      # makes the core eject and finish the insert about half a second
      # later, so anything derived from "is a disk inserted" (the Write
      # Protected item) would otherwise stay stale until the next click.
      refreshFloppyMenus()
      # EMU::reset() and EMU::special_reset() both clear config.romaji_to_kana
      # themselves, so Reset or NMI silently turns this off underneath the
      # menu. The original re-derives its checkmarks every time a menu is
      # opened; this timer serves the same purpose.
      if romajiItemRef.tag != 0:
        romajiItemRef.checked = bx1GetRomajiToKana(h) != 0
      # Rec Sound / Stop keep each other in step when clicked, but a
      # recording can also end on its own (a write that fails, e.g. a full
      # disk), so re-derive both from the recorder itself.
      let recording = capture.isSoundRecording()
      recSoundItem.enabled = not recording
      recStopItem.enabled = recording
      lastStatusTicks = nowTicks
    if nowTicks - lastFpsTicks >= 1000:
      # Drawn frames per second, which is what the original's counter
      # measures too - not the number of VM frames stepped, which the
      # audio-clock pacing above can decouple from this.
      fpsDisplay = int(drawnFrames.float * 1000.0 / float(nowTicks - lastFpsTicks) + 0.5)
      drawnFrames = 0
      lastFpsTicks = nowTicks

  stderr.writeLine "bubix1turboz: main loop exited, saving and shutting down"
  # Before anything is written or freed: the emulation thread is still
  # inside the core, and `running` is what tells it to leave. It checks
  # that between frames, so this returns within a frame's worth of work.
  joinThread(emuThread)
  bx1SaveConfig(h, paths.configFilePath().cstring)
  recentfiles.save(paths.recentFilesPath(), recent)
  hostCfg.setBool("ShowStatusBar", showStatusBar)
  hostCfg.setInt("ScaleQuality", scaleQuality)
  # "auto", "en" or "ja" - read back at the very start of the next launch,
  # before anything can put a word on screen.
  hostCfg.setStr("UILanguage", uiLanguage)
  # The per-device levels live in the core's own config.ini; these two are
  # this port's additions and have nowhere to go there.
  hostCfg.setInt("VolumeMaster", volumeMaster)
  hostCfg.setBool("VolumeLinkLR", volumeLinked)
  # Checked once more on the way out: the guard on WindowEvent_Moved cannot
  # catch a move that lands off-screen for the *next* run, and an
  # unreachable position is worse than none at all - leaving the keys as
  # they were means the next launch falls back to SDL's own placement.
  if windowPosOnScreen(windowX, windowY):
    hostCfg.setInt("WindowX", windowX.int)
    hostCfg.setInt("WindowY", windowY.int)
  hostconfig.save(paths.hostConfigPath(), hostCfg)

  # Before the device closes: stopSoundRecording has to write the header's
  # length fields, and the audio thread must not be inside feedSound while
  # it does.
  lockAudioDevice(audioDev)
  capture.stopSoundRecording(soundRate)
  unlockAudioDevice(audioDev)
  closeAudioDevice(audioDev)
  font.destroy()
  texture.destroy()
  renderer.destroy()
  sdlWin.destroy()
  sdl2.quit()
  bx1Destroy(h)

main()
