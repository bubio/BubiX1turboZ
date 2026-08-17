## BubiX1turboZ application entry point.
##
## Single window, single-threaded main loop (phase 5 milestone; moving
## emulation to its own thread is a follow-up once this is verified stable
## - see docs/dev/DevelopmentPlan.md phase 5).
##
## Window ownership follows the phase 1.2 spike's proven design (案 B):
## uing owns the application object and the menu bar, SDL2 owns the
## emulation surface. The menus themselves are built as plain AppKit
## objects on top of libui's menu bar (see nativemenu.nim) because libui-ng
## cannot nest menus and the structure this app mirrors is two levels deep;
## libui keeps only the application menu's About and Quit.
##
## Two invariants from that spike are load-bearing and must not be
## reordered:
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

import std/[options, os, strformat, strutils, times]
import uing
import sdl2
import sdl2/audio
import bubix1/core
import bubix1/keymap
import bubix1/paths
import bubix1/cocoamenu
import bubix1/recentfiles
import bubix1/archive
import bubix1/diskset
import bubix1/ankfont
import bubix1/nativemenu
import bubix1/clipboard
import bubix1/hostconfig
import bubix1/filedialog
import bubix1/deflate
import bubix1/fddnoise
import bubix1/savestate
import bubix1/statepicker
import bubix1/capture

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
  # Volume panel geometry. libui-ng cannot size a window to its contents,
  # so the height is built from what one device's group actually occupies
  # on screen: the group title, its two slider rows, and the margins of the
  # group and of the box it sits in.
  VolumeWinWidth = 420
  VolumeGroupHeight = 104
  VolumeGroupGap = 12
  VolumeWinMargin = 12
  VolumeButtonHeight = 32
  # The master group holds one row where a device group holds two.
  VolumeMasterHeight = 68
  # A standard macOS title bar, used only to line one window's content up
  # with another's when all that can be set is a frame corner.
  TitleBarHeight = 32
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
# Screen menu can offer. The Nim sdl2 binding wraps SDL_GetDisplayBounds
# but not this one, so it is declared here; returns 0 on success.
proc sdlGetDisplayUsableBounds(displayIndex: cint, bounds: var Rect): cint
  {.importc: "SDL_GetDisplayUsableBounds", cdecl.}

# Which display a window is on, so the two bounds above can be asked about
# that one rather than about display 0. Not wrapped by the Nim binding
# either; returns a negative value on failure.
proc sdlGetWindowDisplayIndex(window: WindowPtr): cint
  {.importc: "SDL_GetWindowDisplayIndex", cdecl.}

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
    "BIOS ROM not found",
    "BubiX1turboZ needs the X1 turbo Z BIOS ROM to start.\n\n" &
    "Put " & IplRomFileName & " - and the font ROMs FNT0808.X1, " &
    "FNT0816.X1 and FNT1616.X1 - into this folder, then open " &
    "BubiX1turboZ again:\n\n" & dir,
    dir)

proc main() =
  paths.ensureDirsExist()

  # Invariant 1: uing before SDL.
  uing.init()

  # After uing.init(), which is what creates NSApp: the alert below is an
  # NSAlert and there is no application object before that point. Before
  # bx1Create, which would otherwise build a machine with no ROM in it.
  if not iplRomPresent():
    reportMissingRom()
    quit 1

  if not sdl2.init(INIT_VIDEO or INIT_AUDIO or INIT_EVENTS):
    fail "SDL_Init failed: " & $getError()

  # Before bx1Create: the FDC loads the drive-noise WAVs as it is built, so
  # anything generated after this point would not be heard until the next
  # launch. See fddnoise.nim.
  fddnoise.ensureFiles(paths.romsDir())

  let h = bx1Create(paths.romsDir().cstring, paths.configFilePath().cstring)
  if h == nil:
    fail "bx1_create failed (place BIOS ROMs in " & paths.romsDir() & ")"
  var recent = recentfiles.load(paths.recentFilesPath())
  var running = true

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
  # separately - see hostconfig.nim. Declared up here because the Host menu
  # is built before the SDL window exists but its actions drive both.
  var hostCfg = hostconfig.load(paths.hostConfigPath())
  var showStatusBar = hostCfg.getBool("ShowStatusBar", true)

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
  # is the only thing that reads it). It still round-trips through the core's
  # config so it persists in config.ini like the original's does.
  var fullSpeed = false
  var skipFrames = 0
  # Set once the Control menu exists, so the status timer can re-sync the
  # one setting the core clears behind our back (see below).
  var romajiItemRef = MenuItemRef(tag: 0)
  var sdlWin: WindowPtr = nil
  var renderer: RendererPtr = nil
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
  # WINDOW_HEIGHT_ASPECT for this machine: 480.
  let aspectHeight = bx1GetAspectHeight(h).int

  proc guestHeight(): int =
    ## The guest picture's height in window points at the current aspect.
    if stretchType == 0: ScreenHeight else: aspectHeight

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
    # Like the original, the list only appears for a mount that actually
    # produced more than one disk; a plain single-disk image gets no section.
    let multiDisk = entries.len > 1
    # Per-file captions only earn their space when the disks came from more
    # than one file, exactly as Bubilator88 shows its image groups.
    let showGroups = multiDisk and groups.len > 1
    setCaptionItems[drv].hidden = not multiDisk
    if multiDisk:
      setCaptionItems[drv].title = driveSource[drv].extractFilename()
    diskSepItems[drv].hidden = not multiDisk
    for i in 0 ..< DiskSlots:
      let show = multiDisk and i < entries.len
      diskItems[drv][i].hidden = not show
      var caption = ""
      if show:
        diskItems[drv][i].title =
          (if showGroups: "  " else: "") & &"{i+1}: " & entries[i].label
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
          index = filedialog.chooseDisk("Select a disk to insert", pickerRows(disks))
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

  var win: Window

  # The only uing Menu left. libui-ng exposes About and Quit exclusively
  # through its Menu API and relocates both into the macOS application
  # menu itself, so one has to exist - but the empty top-level menu it
  # leaves behind on the bar is swept away after win.show() (see
  # cocoamenu.removeTopLevelMenu below). Everything else is built with
  # nativemenu, which can nest.
  let appMenuHost = newMenu "File"
  appMenuHost.addQuitItem(proc (): bool =
    running = false
    if win != nil:
      win.destroy()
      win = nil
    true)
  # libui-ng builds a "Preferences..." item into the application menu
  # unconditionally, as a uiprivMenuItem with no uiMenuItem bound to it -
  # and its click handler calls uiprivImplBug ("Clicked nonexistent
  # uiMenuItem which should be impossible"), which aborts the process
  # (libui/darwin/menu.m:58). So an app that never calls
  # addPreferencesItem, like this one, ships a menu item that kills it.
  # Bind it so it cannot abort, then hide it, since there is no
  # preferences window here for it to open.
  appMenuHost.addPreferencesItem(proc (sender: MenuItem, w: Window) = discard)
  # Without an explicit addAboutItem call, libui-ng still shows the
  # placeholder item but wires no action to it, which Cocoa then reports
  # as permanently disabled (no target-action pair to validate).
  appMenuHost.addAboutItem(proc (sender: MenuItem, w: Window) =
    filedialog.message("BubiX1turboZ " & appVersion,
      "Multi-platform Sharp X1 turbo Z emulator.\n" &
      "Emulation core: Common Source Code Project's eX1turboZ (GPL-2.0-or-later)."))

  # Device and Host menus are built natively after win.show(); see below.

  # A placeholder, not part of the UI. libui-ng will only build a menu bar
  # for a uiWindow created with hasMenubar, and only exposes About/Quit
  # through its Menu API, so one uiWindow has to exist - but it has nothing
  # to show, and libui places it wherever it likes (observed at the very
  # bottom-left corner of the screen). It is shown once so libui finalizes
  # the menu bar, then hidden immediately below; the menu bar itself lives
  # on NSApp, not on this window, so it survives. Nothing is parented to
  # this window any more either - the file dialogs and the About alert are
  # native now (filedialog.nim), precisely so they stop appearing as sheets
  # hanging off this stray window.
  win = newWindow("BubiX1turboZ", 320, 80, true)
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
  win.hide()

  # A botched NSApp modal session from *any* Open/Save dialog (uing's
  # openFile/saveFile - reproduced with the stock File > Open Floppy
  # flow, not specific to phase 7's additions) can otherwise leave every
  # menu item in the app permanently disabled after first use of a
  # dialog. See cocoamenu.m's bx1_menu_disable_autoenable_all for the
  # full mechanism. Must run after win.show() - NSApp has no main menu
  # before that.
  cocoamenu.disableAutoEnableAll()

  # libui-ng put About and Quit into the application menu itself, leaving
  # the Menu they were declared on as an empty top-level entry. Hide it -
  # removing it makes libui's own cleanup miss it and abort at exit.
  cocoamenu.hideTopLevelMenu("File")
  # "" selects the application menu; the title is libui's own ASCII
  # literal, so matching its prefix is stable.
  cocoamenu.setMenuItemHidden("", "Preferences", true)

  # --- Control menu (built natively; see nativemenu.nim) ---
  # Item order, wording and grouping follow the original eX1turboZ's own
  # Control menu (src/res/x1turboz.rc), minus what this port does not have:
  # the three "Debug ... CPU" items and "Close Debugger" (the core's
  # debugger console API is stubbed out here, and a menu that does nothing
  # is worse than no menu), and "Exit" (libui-ng puts Quit in the
  # application menu, where macOS expects it).
  let controlMenu = nativemenu.addMenu("Control")
  controlMenu.addItem("Reset", proc () = resetMachine(), key = "r")
  # The original labels special_reset() "NMI" for this machine; on the X1
  # turbo it is the front-panel NMI button, which is also how a NEW ON
  # reset is triggered.
  controlMenu.addItem("NMI", proc () = bx1SpecialReset(h))
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
  for i, label in ["CPU x1", "CPU x2", "CPU x4", "CPU x8", "CPU x16"]:
    cpuItems[i] = controlMenu.addItem(label, makeCpuAction(i))
  let fullSpeedItem = controlMenu.addItem("Full Speed")
  let driveVmItem = controlMenu.addItem("Drive VM in M1/R/W Cycle")
  controlMenu.addSeparator()

  controlMenu.addItem("Paste", proc () =
    # The original pastes the clipboard through the core's auto key, which
    # replays it as real keystrokes rather than injecting text - so it
    # works with any program running in the guest.
    let text = clipboard.getText()
    if text.len > 0:
      bx1StartAutoKey(h, text.cstring), key = "v")
  controlMenu.addItem("Stop", proc () = bx1StopAutoKey(h))
  let romajiItem = controlMenu.addItem("Romaji to Kana")
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
      fullSpeed: fullSpeed)
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
    if bx1VmStateSave(h, blob.cstring) == 0:
      filedialog.message("Save State", "The machine state could not be captured.")
      return
    try:
      savestate.save(path, blob, currentMeta(), thumbnailPng())
    except CatchableError as e:
      filedialog.message("Save State", e.msg)
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
        stale.add d.image.extractFilename() & " is missing"
        ejectFloppy(drv)
        continue
      driveSet[drv] = set
      driveSource[drv] = d.source
      # Only a drive the core actually accepted is worth waiting on below;
      # one whose image has gone missing would spin out the whole guard.
      if mountAt(drv, index):
        awaiting.add drv
      else:
        stale.add d.image.extractFilename() & " could not be mounted"
      bx1SetFloppyWriteProtected(h, drv.cint, d.writeProtected.cint)
      if d.imageSize > 0:
        let (size, crc) = fileFingerprint(d.image)
        if size != d.imageSize or crc != d.imageCrc32:
          stale.add d.image.extractFilename() & " has changed on disk"
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
      result = "The state was restored, but " & stale.join(", ") & "."

  proc loadStateFrom(path: string) =
    if not fileExists(path):
      return
    var info: StateInfo
    try:
      info = savestate.readInfo(path)
    except CatchableError as e:
      filedialog.message("Load State", e.msg)
      return
    let m = info.meta

    # Everything that can refuse the load is checked before the machine is
    # touched at all, so a rejected state leaves the session running.
    if m.coreStateId != bx1CoreStateId():
      filedialog.message("Load State",
        "This save state was written against a different build of the " &
        "emulation core and can no longer be read.")
      return
    if m.machine != Machine:
      filedialog.message("Load State", "This save state is for a different machine.")
      return
    let ipl = iplFingerprint()
    if m.iplCrc32 != 0 and ipl != 0 and m.iplCrc32 != ipl:
      filedialog.message("Load State",
        "This save state was made with a different IPL ROM. States carry no " &
        "ROM data, so restoring one against another ROM would leave the " &
        "machine in an inconsistent state.")
      return
    # Settings the original reacts to by throwing the VM away and building
    # a new one. This layer replaces device state only and cannot ask for
    # that rebuild at load time (EMU::vm is protected, and the core does it
    # only from its own load_state and from EMU::reset), so a mismatch is
    # refused rather than half-applied.
    var mismatch = ""
    # What the user can do about it, which is not the same for every row:
    # the sound board is reachable through a reset, the rest are not.
    var remedy = "which cannot be changed while the machine is running."
    # Sound type is in this list, not applied like the settings below it:
    # VM's constructor builds a different device chain for each value
    # (x1.cpp:116-125 adds the OPM boards), and VM::process_state checks
    # every device's typeid name against the stream (x1.cpp:1050-1063), so
    # a state from another chain would fail the apply and roll back. Say
    # why up front instead.
    if m.reinit.soundType != vmSoundType():
      mismatch = "sound board"
      remedy = "which this machine is not running. Pick it again in " &
        "Device > Sound, reset the machine (Control > Reset), then load " &
        "the state."
    elif m.reinit.printerType != bx1GetPrinterType(h).int: mismatch = "printer"
    elif m.reinit.serialType != bx1GetSerialType(h).int: mismatch = "serial"
    elif m.reinit.soundFrequency != vmSoundFrequency: mismatch = "sound frequency"
    elif m.reinit.soundLatency != vmSoundLatency: mismatch = "sound latency"
    if mismatch.len > 0:
      filedialog.message("Load State",
        "This save state was made with a different " & mismatch & " setting, " &
        remedy)
      return

    # Everything that can fail without touching the machine happens before
    # anything that changes it: unpacking the blob is pure file work, so a
    # corrupt container must not leave the drives holding the state's disks.
    createDir paths.scratchDir() # $TMPDIR can be reaped under a long session
    let blob = scratch("load.vmst")
    try:
      savestate.extractVm(path, blob)
    except CatchableError as e:
      filedialog.message("Load State", e.msg)
      return

    # The auto key would go on typing into the restored machine; the core's
    # own load_state stops it for the same reason.
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
    let warning = restoreDrives(m)
    let applied =
      bx1VmStateLoad(h, blob.cstring, scratch("rollback.vmst").cstring) != 0
    removeFile(blob)
    bx1MuteSound(h)
    refreshFloppyMenus()
    if not applied:
      # The VM state itself rolled back inside the bridge, but the mounts
      # and settings above did not - say so rather than implying the
      # session is untouched.
      filedialog.message("Load State",
        "This save state could not be applied. The machine kept running " &
        "from where it was, but the drives now hold the state's disks.")
      return
    bx1SetCpuPower(h, m.cpuPower.cint)
    syncCpuItems()
    fullSpeed = m.fullSpeed
    fullSpeedItem.checked = fullSpeed
    bx1SetFullSpeed(h, fullSpeed.cint)
    skipFrames = 0
    if warning.len > 0:
      filedialog.message("Load State", warning)

  proc pickSlot(forSaving: bool): int =
    ## Runs the slot grid. The emulation loop is stopped for as long as it
    ## is up - which, unlike a file dialog, is however long it takes to
    ## look at ten screenshots - so the audio the machine could not produce
    ## meanwhile is dropped on the way out. Without that the loop comes
    ## back chasing a sound clock that ran on without it.
    var cells: seq[SlotCell]
    for slot in 0 ..< StateSlots:
      let info = slotInfo(slot)
      var cell = SlotCell(
        # Bubilator88 numbers its slots from 1 on screen. The files stay
        # slot0..slot9 (paths.stateSlotPath), which nothing but this line
        # and the picker's own indexing ever sees.
        caption: "Slot " & $(slot + 1),
        # Saving overwrites, so every slot is a target; loading needs one
        # with something in it.
        enabled: forSaving or info.isSome)
      if info.isSome:
        let meta = info.get.meta
        cell.detail = meta.savedAt.fromUnix().local().format("MM/dd HH:mm")
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
      if forSaving: "Save State" else: "Load State", cells)
    bx1MuteSound(h)
    skipFrames = 0

  controlMenu.addItem("Quick Save", proc () =
    saveStateTo(paths.stateSlotPath(QuickSlot)), key = "s")
  quickLoadItem = controlMenu.addItem("Quick Load", proc () =
    loadStateFrom(paths.stateSlotPath(QuickSlot)), key = "l")
  # A caption, not an action: what the quick save currently holds, shown
  # the way the FD0/FD1 menus caption their disk lists.
  quickInfoItem = controlMenu.addItem("")
  quickInfoItem.enabled = false
  controlMenu.addSeparator()
  controlMenu.addItem("Save State…", proc () =
    let slot = pickSlot(true)
    if slot >= 0:
      saveStateTo(paths.stateSlotPath(slot)))
  controlMenu.addItem("Load State…", proc () =
    let slot = pickSlot(false)
    if slot >= 0:
      loadStateFrom(paths.stateSlotPath(slot)))
  refreshQuickStateMenu()

  # These three are plain toggles rather than radio groups, so they have to
  # flip their own state - AppKit does not do it for a target/action item.
  # Assigned after creation because each closure refers to its own item.
  fullSpeed = bx1GetFullSpeed(h) != 0
  fullSpeedItem.checked = fullSpeed
  driveVmItem.checked = bx1GetDriveVmInOpecode(h) != 0
  romajiItem.checked = bx1GetRomajiToKana(h) != 0
  nativemenu.setAction(fullSpeedItem, proc () =
    fullSpeedItem.checked = not fullSpeedItem.checked
    fullSpeed = fullSpeedItem.checked
    skipFrames = 0
    bx1SetFullSpeed(h, fullSpeed.cint))
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

  let diskMenu = nativemenu.addMenu("Disk")

  for drv in 0 ..< FloppyDrives:
    let fd = diskMenu.addSubmenu("FD" & $drv)
    fd.addItem("Insert…", makeInsertAction(drv), key = $(drv + 1))
    fd.addItem("Eject", makeEjectAction(drv))
    fd.addItem("Insert Blank 2D Disk…", makeBlankAction(drv, 0))
    fd.addItem("Insert Blank 2DD Disk…", makeBlankAction(drv, 1))
    fd.addItem("Insert Blank 2HD Disk…", makeBlankAction(drv, 2))
    fd.addSeparator()
    writeProtectItems[drv] = fd.addItem("Write Protected")
    let correctTiming = fd.addItem("Correct Timing")
    let ignoreCrc = fd.addItem("Ignore CRC Errors")
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
    # The title's disk list, closing the submenu. Hidden entirely unless the
    # mount produced more than one disk, exactly like the original's bank
    # list - including the separator above it, which would otherwise be left
    # trailing at the end of the menu with nothing under it. Each slot is
    # preceded by its own caption slot, which only shows for the first disk
    # of a file when the disks came from several files - fixed slots cannot
    # be inserted between one another later.
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
  bothMenu.addItem("Insert…", insertBothAction(), key = "3")
  bothMenu.addItem("Eject", proc () =
    for drv in 0 ..< FloppyDrives:
      ejectFloppy(drv))

  diskMenu.addSeparator()
  # One list for the app, not one per drive as the original has: an entry
  # names a title (an archive or playlist as often as a bare image), which
  # is not a per-drive thing. Its own recent.txt, since the core's
  # config_t.recent_*_path fields are never populated by this tree.
  let recentMenu = diskMenu.addSubmenu("Recent Files")
  for i in 0 ..< RecentSlots:
    recentItems[i] = recentMenu.addItem("", makeRecentAction(i))
  recentNoneItem = recentMenu.addItem("None")
  recentNoneItem.enabled = false
  recentMenu.addSeparator()
  recentMenu.addItem("Clear Recent Files", proc () =
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
  let deviceMenu = nativemenu.addMenu("Device")

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

  let keyboardMenu = deviceMenu.addSubmenu("Keyboard")
  keyboardMenu.addRadioGroup(
    @["Keyboard Mode A", "Keyboard Mode B"], @[0, 1], bx1GetKeyboardType(h).int,
    proc (v: cint) = bx1SetKeyboardType(h, v))

  let soundMenu = deviceMenu.addSubmenu("Sound")
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
        filedialog.message("Sound Board",
          "The sound board is chosen while the machine is being built, so " &
          "this takes effect at the next reset (Control > Reset)."))
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
  soundMenu.addToggle("Play FDD Noise",
    proc (): bool = bx1GetSoundNoiseFdd(h) != 0, proc (on: cint) = bx1SetSoundNoiseFdd(h, on))

  let displayMenu = deviceMenu.addSubmenu("Display")
  # "High Resolution" (0) has a genuine glyph rendering fault that the
  # original Windows build shows too, so it is not the default here; see
  # bx1_create and DevelopmentPlan phase 5.
  displayMenu.addRadioGroup(
    @["High Resolution", "Standard"], @[0, 1], bx1GetMonitorType(h).int,
    proc (v: cint) = bx1SetMonitorType(h, v))
  displayMenu.addSeparator()
  displayMenu.addToggle("Scanline",
    proc (): bool = bx1GetScanLine(h) != 0, proc (on: cint) = bx1SetScanLine(h, on))

  # --- Volume window (Host > Volume) ---
  # The original opens a modal dialog of per-device L/R trackbars
  # (IDD_VOLUME in x1turboz.rc). Same idea here, as a uing window built
  # once at startup and shown on demand: repeatedly creating and destroying
  # uiWindows is exactly the pattern that makes libui-ng's teardown
  # complain, and one live hidden window costs nothing.
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
  # Sliders stay indexed by the core's device number, so the rows that are
  # skipped simply leave a nil entry nothing ever touches.
  var volumeL = newSeq[Slider](volumeCount)
  var volumeR = newSeq[Slider](volumeCount)
  let volumeWin = newWindow("Volume", 1, 1, false)
  volumeWin.margined = true
  # Nothing here reads better wider, and dragging the panel smaller than the
  # rows need puts them back on top of each other - libui-ng lets a group
  # shrink past its own contents (see the stretchy note below).
  volumeWin.resizeable = false
  # One group per device rather than one flat grid of anonymous bars: the
  # two sliders of a device are its left and right channel, which a caption
  # sitting beside an unlabelled pair does not say.
  # There is no numeric readout, matching the original's dialog (IDD_VOLUME
  # is trackbars only): libui-ng sizes a grid column to the widest label in
  # it, so a live "-40 dB" that shrinks to "0 dB" would resize the slider
  # beside it on every drag. The slider carries the value as a tooltip
  # instead, which libui-ng gives it by default.
  let volumeBox = newVerticalBox(true)

  # Master and Link L/R are this port's own, not the original's. The core
  # has no master level - volume exists per device only - so the master is
  # mixed in here: what the user set stays in the per-device sliders and in
  # config.ini, and the machine is given the sum, clamped to the range the
  # core accepts. Writing the sum to config instead would bake the
  # attenuation into the stored levels and apply it again next launch.
  var volumeMaster = max(-40, min(0, hostCfg.getInt("VolumeMaster", 0)))
  var volumeLinked = hostCfg.getBool("VolumeLinkLR", false)
  proc setLevel(slider: Slider, level: int) =
    ## Sets a slider from code, and refreshes the tooltip that carries its
    ## value. libui-ng only rewrites that text when the *user* moves the
    ## knob (darwin/slider.m:57), so a knob moved from here would otherwise
    ## sit under the previous number - and the tooltip is the only place
    ## this panel shows a number at all. Re-asserting hasToolTip is what
    ## rewrites it (slider.m:92-98).
    slider.value = level
    slider.hasToolTip = true
  proc volumeMixed(level: int): int = max(-40, min(0, level + volumeMaster))
  proc applyVolume(dev: int) =
    ## Pushes one device's level to the machine, master included. Nothing
    ## is stored: the caller decides whether this was a change worth
    ## remembering (storeVolume) or only a re-application of one.
    bx1ApplyVolume(h, dev.cint, volumeMixed(volumeL[dev].value).cint,
      volumeMixed(volumeR[dev].value).cint)
  proc storeVolume(dev: int) =
    ## Remembers one device's levels as the user set them, then applies the
    ## mixed result. bx1SetVolume also applies what it stores, so the order
    ## matters: the machine must end up holding the mixed value.
    bx1SetVolume(h, dev.cint, volumeL[dev].value.cint, volumeR[dev].value.cint)
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
      if volumeDeviceBuilt(i) and volumeR[i].value != volumeL[i].value:
        volumeR[i].setLevel(volumeL[i].value)
        storeVolume(i)
  proc snap(slider: Slider): int =
    ## The value a slider is worth, with its knob put back on it.
    ##
    ## The range is whole decibels but the control underneath is continuous,
    ## so a knob dragged to -21.8 reports (and applies, and copies to the
    ## other channel) -22 while sitting visibly short of it. Writing the
    ## value back moves the knob onto the step it actually means, which is
    ## also what makes two linked channels line up exactly. Setting a value
    ## from code does not call the handler back (libui-ng only reports user
    ## changes), so this cannot recurse.
    result = slider.value
    slider.setLevel(result)
  proc makeVolumeChanged(dev: int, isLeft: bool): proc (sender: Slider) =
    result = proc (sender: Slider) =
      let level = snap(sender)
      if volumeLinked:
        if isLeft:
          volumeR[dev].setLevel(level)
        else:
          volumeL[dev].setLevel(level)
      storeVolume(dev)
  # Above the devices, since it acts on all of them.
  let masterGroup = newGroup("Master", true)
  let masterRows = newVerticalBox(true)
  let masterRow = newHorizontalBox(true)
  let masterSlider = newSlider(-40 .. 0, proc (sender: Slider) =
    volumeMaster = snap(sender)
    applyAllVolumes())
  masterSlider.setLevel(volumeMaster)
  masterRow.add(newLabel("L+R"))
  masterRow.add(masterSlider, true)
  masterRows.add(masterRow, true)
  masterGroup.child = masterRows
  volumeBox.add(masterGroup, true)

  for i in volumeDevices:
    let group = newGroup($bx1GetSoundDeviceCaption(i.cint), true)
    # Boxes, not a Grid. A grid lays the two channels out just as well, but
    # its darwin backend wraps every cell in a container view of its own,
    # and the second row's containers ended up unreachable to the mouse -
    # the R slider drew correctly and reported itself enabled while no
    # click ever got to it. Boxes put the controls in the group directly.
    let rows = newVerticalBox(true)
    # Range matches the core's own clamp on set_sound_device_volume.
    volumeL[i] = newSlider(-40 .. 0, makeVolumeChanged(i, true))
    volumeR[i] = newSlider(-40 .. 0, makeVolumeChanged(i, false))
    volumeL[i].setLevel(bx1GetVolumeL(h, i.cint).int)
    volumeR[i].setLevel(bx1GetVolumeR(h, i.cint).int)
    for parts in [("L", volumeL[i]), ("R", volumeR[i])]:
      let (channel, slider) = parts
      let row = newHorizontalBox(true)
      row.add(newLabel(channel))
      row.add(slider, true) # stretchy: the slider takes the spare width
      # Stretchy here too, for the reason the groups are stretchy below.
      rows.add(row, true)
    group.child = rows
    # Every group stretchy, so the window's height is shared out evenly.
    # A non-stretchy group is held at a minimum that libui-ng computes too
    # small for two slider rows, and the rows then overlap; only the ones
    # given the leftover height escape that.
    volumeBox.add(group, true)
  let volumeBar = newHorizontalBox(true)
  # One switch for the whole panel rather than one per device: the two
  # channels of a device are almost always wanted at the same level, and a
  # checkbox per group would add a row to every one of them. Ticking it
  # brings every R up to its L there and then, rather than waiting for each
  # to be dragged: a panel that says the channels are linked while showing
  # rows where they visibly are not is the confusing half of both worlds.
  let linkBox = newCheckbox("Link L/R", proc (sender: Checkbox) =
    volumeLinked = sender.checked
    if volumeLinked:
      equalizeChannels())
  linkBox.checked = volumeLinked
  volumeBar.add(linkBox)
  volumeBar.add(newLabel(""), true) # pushes the button to the trailing edge
  # Same as the original's Reset button: back to 0dB, which is the config's
  # own default, and the master with it. Applied straight away because this
  # panel has no OK to apply it at - it edits the running machine live,
  # where the original edited a copy and committed it on OK.
  volumeBar.add(newButton("Reset", proc (sender: Button) =
    volumeMaster = 0
    masterSlider.setLevel(0)
    for i in volumeDevices:
      # Greyed rows are left alone. The original zeroes all seven channels,
      # but nothing here has offered the user a way to change a channel its
      # machine does not have, so this must not write one either - a
      # disabled control that still edits the config is not disabled.
      if volumeDeviceBuilt(i):
        volumeL[i].setLevel(0)
        volumeR[i].setLevel(0)
        storeVolume(i)))
  volumeBox.add(volumeBar)
  volumeWin.child = volumeBox
  proc refreshVolumeAvailability() =
    ## Greys the rows whose board this machine does not have, and un-greys
    ## them when a reset has since built one. Called on every show, not
    ## once: Device > Sound plus Control > Reset changes the answer while
    ## the panel is alive.
    ##
    ## The row stays rather than vanishing: the original lists every channel
    ## of the table unconditionally, and a row that disappears looks like
    ## the app lost the device. Greyed says what the original's own
    ## (commented out) EnableWindow calls were reaching for - the channel
    ## exists, this machine just has no board behind it.
    ##
    ## The sliders are disabled rather than the Group around them - a
    ## disabled Group has no visible effect here - and only once the whole
    ## tree is assembled, since libui-ng pushes an enable state down when a
    ## control is given its parent.
    for i in volumeDevices:
      if volumeDeviceBuilt(i):
        volumeL[i].enable()
        volumeR[i].enable()
      else:
        volumeL[i].disable()
        volumeR[i].disable()
  refreshVolumeAvailability()
  # The machine starts out holding config.ini's per-device levels; a master
  # restored from the host settings has to be mixed into them once here, or
  # it would not be heard until something moved a slider.
  if volumeLinked:
    equalizeChannels()
  applyAllVolumes()
  afterReset = applyAllVolumes
  # Sized here rather than at newWindow, where the children the size has to
  # fit did not exist yet. libui-ng has no "size to fit contents", so the
  # per-device height is measured from what the platform actually lays out
  # (group title, two slider rows, the box's own padding).
  volumeWin.contentSize = (width: VolumeWinWidth,
    height: VolumeMasterHeight + VolumeGroupHeight * volumeDevices.len +
      VolumeGroupGap * (volumeDevices.len + 1) + VolumeButtonHeight +
      VolumeWinMargin * 2)
  volumeWin.onClosing = proc (sender: Window): bool =
    # Hide rather than destroy, and return false so libui-ng does not
    # destroy it either - the same rule the main window follows, for the
    # same reason (uing destroys the window from inside its own
    # "should close" delegate callback, which crashes).
    volumeWin.hide()
    false

  var volumePlaced = false
  proc showVolumeWindow() =
    ## Shows the volume panel, centering it over the emulator window the
    ## first time only - moving it back on every open would undo wherever
    ## the user had put it.
    refreshVolumeAvailability()
    if not volumePlaced and sdlWin != nil:
      volumePlaced = true
      var wx, wy, ww, wh: cint
      sdlWin.getPosition(wx, wy)
      sdlWin.getSize(ww, wh)
      let size = volumeWin.contentSize
      # SDL measures from the top of the display; libui-ng's darwin backend
      # measures from the top of the *visible* frame, i.e. below the menu
      # bar (window.m:269-283), so the two differ by exactly that bar.
      # Single display assumed for the horizontal axis, which is where the
      # two do agree.
      var menuBarHeight = 0
      let display = sdlGetWindowDisplayIndex(sdlWin)
      var full, usable: Rect
      if display >= 0 and getDisplayBounds(display, full) == SdlSuccess and
          sdlGetDisplayUsableBounds(display, usable) == 0:
        menuBarHeight = usable.y.int - full.y.int
      # Both sizes above describe content areas, while the position being
      # set describes a frame corner, so centering one on the other has to
      # step over one title bar. SDL2's Cocoa backend answers
      # SDL_GetWindowBordersSize with "not supported", so the standard one
      # is assumed; getting it wrong only slides the panel a few points.
      let want = (x: wx.int + (ww.int - size.width) div 2,
        y: wy.int + (wh.int - size.height) div 2 - TitleBarHeight - menuBarHeight)
      volumeWin.position = want
      volumeWin.show()
      # The position above is set while the window has never been on screen,
      # where the darwin backend has no NSScreen to measure against and can
      # drop it. Reading back after show() is the only way to tell, and
      # costs one redundant move in the case where it worked.
      let got = volumeWin.position
      if abs(got.x - want.x) > 2 or abs(got.y - want.y) > 2:
        volumeWin.position = want
    else:
      volumeWin.show()

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
  let hostMenu = nativemenu.addMenu("Host")

  # Rec Sound / Stop / Capture Screen. The original routes these through its
  # OSD; this port's OSD has them as empty stubs and the core is not to be
  # modified, so they are done from the host's own copies of the same data -
  # see capture.nim.
  var recSoundItem, recStopItem: MenuItemRef
  recSoundItem = hostMenu.addItem("Rec Sound", proc () =
    # The lock keeps the audio thread out of feedSound while the file is
    # being created underneath it.
    lockAudioDevice(audioDev)
    let path = capture.startSoundRecording(soundRate)
    unlockAudioDevice(audioDev)
    if path.len == 0:
      filedialog.message("Rec Sound",
        "Could not start recording in " & paths.recordingsDir() & ".")
    recSoundItem.enabled = not capture.isSoundRecording()
    recStopItem.enabled = capture.isSoundRecording())
  recStopItem = hostMenu.addItem("Stop", proc () =
    lockAudioDevice(audioDev)
    capture.stopSoundRecording(soundRate)
    unlockAudioDevice(audioDev)
    recSoundItem.enabled = true
    recStopItem.enabled = false)
  # The original greys out whatever is not applicable each time the menu
  # opens; here the two items keep each other in step, and the status timer
  # re-syncs them in case a write error stopped the recording on its own.
  recStopItem.enabled = false
  hostMenu.addItem("Capture Screen", proc () =
    # The core's framebuffer, i.e. the guest's own picture: no status bar,
    # no window scaling, whatever the window happens to look like.
    if capture.saveScreenshot(bx1GetFramebuffer(h), ScreenWidth, ScreenHeight).len == 0:
      filedialog.message("Capture Screen",
        "Could not write a screenshot to " & paths.screenshotsDir() & "."))
  hostMenu.addSeparator()

  # --- Host > Screen ---
  let screenMenu = hostMenu.addSubmenu("Screen")
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
    windowItems.add screenMenu.addItem("Window x" & $n, makeWindowScaleAction(n))
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
  fullscreenItem = screenMenu.addItem("Fullscreen",
    proc () = applyFullscreen(not isFullscreen),
    key = "f", mods = ModCommand or ModControl)
  syncScreenItems()

  screenMenu.addSeparator()
  # The original relabels these two at runtime from the machine's own
  # dimensions ("Window: Aspect Ratio %d:%d", winmain.cpp:2076-2080); same
  # here, from the values the bridge reports.
  screenMenu.addRadioGroup(
    @[&"Window: Aspect Ratio {ScreenWidth}:{ScreenHeight}",
      &"Window: Aspect Ratio {ScreenWidth}:{aspectHeight}"],
    @[0, 1], stretchType,
    proc (v: cint) =
      stretchType = v.int
      bx1SetWindowStretchType(h, v)
      applyWindowLayout())

  screenMenu.addSeparator()
  screenMenu.addRadioGroup(
    @["Fullscreen: Dot By Dot",
      &"Fullscreen: Stretch (Aspect Ratio {ScreenWidth}:{ScreenHeight})",
      &"Fullscreen: Stretch (Aspect Ratio {ScreenWidth}:{aspectHeight})",
      "Fullscreen: Stretch (Fill)"],
    @[0, 1, 2, 3], fullscreenStretch,
    proc (v: cint) =
      fullscreenStretch = v.int
      bx1SetFullscreenStretchType(h, v))

  # --- Host > Sound ---
  let hostSoundMenu = hostMenu.addSubmenu("Sound")
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
    @["Realtime Mix", "Light Weight Mix"], @[1, 0],
    bx1GetSoundStrictRendering(h).int,
    proc (v: cint) = bx1SetSoundStrictRendering(h, v))
  hostSoundMenu.addSeparator()
  # Where the original keeps it: ID_SOUND_VOLUME is inside POPUP "Sound".
  hostSoundMenu.addItem("Volume", proc () = showVolumeWindow())

  hostMenu.addSeparator()
  let statusBarItem = hostMenu.addItem("Show Status Bar")
  statusBarItem.checked = showStatusBar
  statusBarItem.setAction(proc () =
    statusBarItem.checked = not statusBarItem.checked
    showStatusBar = statusBarItem.checked
    applyWindowLayout())

  # libui-ng attaches no keyboard shortcuts to any menu item (phase 1.2);
  # wire up the standard macOS ones by hand. Must happen after win.show()
  # - NSApp has no main menu before that.
  discard cocoamenu.setMenuShortcut("", "Quit", "q")

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
  sdlWin = createWindow("BubiX1turboZ - Screen", SDL_WINDOWPOS_UNDEFINED,
    SDL_WINDOWPOS_UNDEFINED, (ScreenWidth * windowScale).cint,
    (guestHeight() * windowScale).cint + statusBarHeight(), SDL_WINDOW_HIDDEN)
  if sdlWin == nil:
    fail "SDL_CreateWindow failed: " & $getError()
  renderer = createRenderer(sdlWin, -1, Renderer_Accelerated)
  if renderer == nil:
    fail "SDL_CreateRenderer failed: " & $getError()
  sdlWin.showWindow()

  # Logged because the crash above is specific to one backend: if it ever
  # comes back, the first question is which renderer was in use.
  var rendererInfo: RendererInfo
  if renderer.getRendererInfo(addr rendererInfo) == 0:
    echo "renderer: ", $rendererInfo.name
  let texture = renderer.createTexture(SDL_PIXELFORMAT_ARGB8888,
    SDL_TEXTUREACCESS_STREAMING, ScreenWidth, ScreenHeight)
  if texture == nil:
    fail "SDL_CreateTexture failed: " & $getError()
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
  let targetBufferedFrames = cint(soundRate.float * bx1GetActualSoundLatency(h))

  # The status bar prints with the machine's own 8x8 ANK glyphs; see
  # ankfont.nim for why this rather than SDL_ttf. A missing font ROM leaves
  # `ready == false` and every draw becomes a no-op, so the lamps still work.
  var font = ankfont.load(renderer, paths.romsDir())
  if not font.ready:
    stderr.writeLine "bubix1turboz: no 8x8 font ROM in " & paths.romsDir() &
      "; status bar text disabled"

  var runFrameSafetyCounter = 0
  var fpsDisplay = 0
  var drawnFrames = 0
  var lastFpsTicks = getTicks()
  var lastStatusTicks = lastFpsTicks
  const StatusPollMs = 200'u32
  # How long one Full Speed pass may run the VM before returning to the
  # event pump. Long enough that the per-pass overhead is negligible, short
  # enough that menus and keyboard stay responsive.
  const FullSpeedBatchMs = 8'u32
  # X1turboZ runs at FRAMES_PER_SEC 61.94 (vm/x1/x1.h), which is not a whole
  # number of milliseconds - hence a float accumulator rather than an
  # integer interval, so the error does not compound into visible drift.
  const FrameIntervalMs = 1000.0 / 61.94
  var nextDrawTicks = lastFpsTicks.float

  proc drawFrame() =
    ## Renders one frame of the guest's screen plus the status bar.
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

  uing.mainSteps()

  var ev = sdl2.defaultEvent
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
          # A drop is "start this title", so it fills both drives without
          # asking which disk to use - the same choice Bubilator88 makes
          # for its own drop handler.
          loadMedia($raw, bothDrives = true, reset = true)
          sdlFreeStr(raw)
      else:
        discard
    discard uing.mainStep(0)

    # Advance the VM. Normally this is paced by the audio ring buffer
    # (docs/dev/DevelopmentPlan.md architecture decision 4): keep running
    # frames while the buffer the SDL callback drains from is below the
    # target latency. Full Speed removes that limiter.
    runFrameSafetyCounter = 0
    if fullSpeed:
      # The original's Full Speed is not "run the VM faster" as such: it
      # forces winmain.cpp's frame-skip path, which stops advancing the
      # frame-interval accumulator, so the loop never sleeps and never
      # draws - except once per emulated second, so the window does not
      # look frozen. Same shape here, time-boxed per pass so the event
      # pump above still gets to run.
      let batchEnd = getTicks() + FullSpeedBatchMs
      while getTicks() < batchEnd:
        discard bx1RunFrame(h)
        inc skipFrames
        inc runFrameSafetyCounter
        if runFrameSafetyCounter > 2000:
          break
      if skipFrames > 62: # ~FRAMES_PER_SEC of emulated time
        skipFrames = 0
        drawFrame()
        nextDrawTicks = getTicks().float + FrameIntervalMs
    else:
      while bx1GetBufferedAudioFrames(h) < targetBufferedFrames:
        discard bx1RunFrame(h)
        inc runFrameSafetyCounter
        if runFrameSafetyCounter > 1000:
          # Should be unreachable in normal operation; bail out rather than
          # freeze the UI if the VM ever stops producing audio progress.
          break

      # Drawing runs on its own clock rather than "once per pass through
      # this loop". Neither of the obvious alternatives works: presenting
      # every pass spins as fast as the GPU accepts frames (measured
      # ~170/sec on a 61.94Hz machine, burning a core to show nothing new),
      # and presenting only when the VM advanced gives ~10/sec, because the
      # pacing loop above advances the VM in bursts - the core synthesizes
      # a whole sound_latency window (100ms, ~6 frames) per create_sound
      # call, then nothing until the ring buffer drains. Pacing here on
      # wall time decouples the two, which is also how the original app
      # works (its VM is paced by the DirectSound cursor while WM_PAINT
      # redraws on its own timer).
      let frameTicks = getTicks()
      if frameTicks.float < nextDrawTicks:
        delay(1)
      else:
        nextDrawTicks += FrameIntervalMs
        if nextDrawTicks < frameTicks.float:
          # Fell far enough behind (a stall, or the window was occluded)
          # that catching up would mean a burst of back-to-back presents.
          # Resync to now instead.
          nextDrawTicks = frameTicks.float + FrameIntervalMs
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
  bx1SaveConfig(h, paths.configFilePath().cstring)
  recentfiles.save(paths.recentFilesPath(), recent)
  hostCfg.setBool("ShowStatusBar", showStatusBar)
  # The per-device levels live in the core's own config.ini; these two are
  # this port's additions and have nowhere to go there.
  hostCfg.setInt("VolumeMaster", volumeMaster)
  hostCfg.setBool("VolumeLinkLR", volumeLinked)
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
  volumeWin.destroy()
  if win != nil:
    win.destroy()
  uing.uninit()
  bx1Destroy(h)

main()
