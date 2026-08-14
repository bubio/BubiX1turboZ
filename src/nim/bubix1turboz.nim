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

import std/[os, strformat, strutils, times]
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
import bubix1/savestate

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

  # Host-side view settings. These are not in the core's config_t on this
  # platform (config.show_status_bar is Win32-only there), so they persist
  # separately - see hostconfig.nim. Declared up here because the Host menu
  # is built before the SDL window exists but its actions drive both.
  var hostCfg = hostconfig.load(paths.hostConfigPath())
  var showStatusBar = hostCfg.getBool("ShowStatusBar", true)
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

  proc windowHeight(): cint =
    (if showStatusBar: WindowHeight else: ScreenHeight).cint

  proc applyWindowLayout() =
    ## Resizes the window to fit (or drop) the status bar and re-establishes
    ## the renderer's logical size, which is what makes the picture scale to
    ## fill a fullscreen window instead of sitting in one corner.
    if sdlWin == nil:
      return
    sdlWin.setSize(ScreenWidth.cint, windowHeight())
    if renderer != nil:
      discard renderer.setLogicalSize(ScreenWidth.cint, windowHeight())

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
        bx1Reset(h)

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
  controlMenu.addItem("Reset", proc () = bx1Reset(h), key = "r")
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

  # Numbered state slots, like the original's two submenus - no file
  # dialog, just ten fixed files plus the quick save. The format is this
  # app's own (.bx1s, see docs/dev/SaveState.md and savestate.nim), not the
  # core's .sta: that one embeds _MAX_PATH-sized buffers, carries no
  # metadata, and refers to a multi-disk image's banks by bare index.
  # Nothing migrates - any leftover x1turboz.sta* is simply ignored.
  var saveStateItems: array[StateSlots, MenuItemRef]
  var loadStateItems: array[StateSlots, MenuItemRef]
  var quickLoadItem: MenuItemRef

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
        soundType: bx1GetSoundType(h).int,
        printerType: bx1GetPrinterType(h).int,
        serialType: bx1GetSerialType(h).int,
        soundFrequency: bx1GetSoundFrequency(h).int,
        soundLatency: bx1GetSoundLatency(h).int),
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

  proc refreshStateMenus() =
    ## Occupied slots name their title and when they were taken; empty ones
    ## stay listed (the slot number is the point) but cannot be loaded.
    for slot in 0 ..< StateSlots:
      let path = paths.stateSlotPath(slot)
      var caption = "State " & $slot
      var occupied = false
      if fileExists(path):
        try:
          caption &= " - " & savestate.describe(savestate.readInfo(path))
          occupied = true
        except CatchableError:
          caption &= " - (unreadable)"
      saveStateItems[slot].title = caption
      loadStateItems[slot].title = caption
      loadStateItems[slot].enabled = occupied
    quickLoadItem.enabled = fileExists(paths.stateSlotPath(QuickSlot))

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
    refreshStateMenus()

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
    # a new one. This layer replaces device state only and cannot rebuild
    # the VM (EMU::vm is protected; the rebuild lives inside the core's own
    # load_state), so a mismatch is refused rather than half-applied.
    var mismatch = ""
    # Sound type is in this list, not applied like the settings below it:
    # VM's constructor builds a different device chain for each value
    # (x1.cpp:116-125 adds the OPM boards), and VM::process_state checks
    # every device's typeid name against the stream (x1.cpp:1050-1063), so
    # a state from another chain would fail the apply and roll back. Say
    # why up front instead.
    if m.reinit.soundType != bx1GetSoundType(h).int: mismatch = "sound board"
    elif m.reinit.printerType != bx1GetPrinterType(h).int: mismatch = "printer"
    elif m.reinit.serialType != bx1GetSerialType(h).int: mismatch = "serial"
    elif m.reinit.soundFrequency != bx1GetSoundFrequency(h).int: mismatch = "sound frequency"
    elif m.reinit.soundLatency != bx1GetSoundLatency(h).int: mismatch = "sound latency"
    if mismatch.len > 0:
      filedialog.message("Load State",
        "This save state was made with a different " & mismatch & " setting, " &
        "which cannot be changed while the machine is running.")
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

  controlMenu.addItem("Quick Save", proc () =
    saveStateTo(paths.stateSlotPath(QuickSlot)), key = "s")
  quickLoadItem = controlMenu.addItem("Quick Load", proc () =
    loadStateFrom(paths.stateSlotPath(QuickSlot)), key = "l")
  let saveStateMenu = controlMenu.addSubmenu("Save State")
  let loadStateMenu = controlMenu.addSubmenu("Load State")
  proc makeSaveStateAction(slot: int): MenuAction =
    result = proc () = saveStateTo(paths.stateSlotPath(slot))
  proc makeLoadStateAction(slot: int): MenuAction =
    result = proc () = loadStateFrom(paths.stateSlotPath(slot))
  for slot in 0 ..< StateSlots:
    saveStateItems[slot] = saveStateMenu.addItem("State " & $slot,
                                                 makeSaveStateAction(slot))
    loadStateItems[slot] = loadStateMenu.addItem("State " & $slot,
                                                 makeLoadStateAction(slot))
  refreshStateMenus()

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
  # Nested exactly like the original's, with two of its submenus left out:
  # Printer and Serial, whose OSD backends are no-op stubs in this port
  # (DevelopmentPlan 0.6 group C), so every entry would be inert.
  #
  # A small helper covers the four radio groups below. Written as a proc
  # taking the values it needs rather than inline in each loop, for the
  # closure-binding reason documented at makeToggleAction above.
  let deviceMenu = nativemenu.addMenu("Device")

  proc addRadioGroup(menu: nativemenu.Menu, labels: seq[string], values: seq[int],
                     current: int, apply: proc (value: cint) {.closure.}) =
    ## Builds a set of items where clicking one checks it and clears the
    ## rest. `values` are the core's own constants, which are not always a
    ## dense 0..n range (boot device skips several). seq rather than
    ## openArray: the per-item closures below capture them, which Nim does
    ## not allow for an openArray.
    var group = newSeq[MenuItemRef](labels.len)
    proc makeAction(idx: int): MenuAction =
      result = proc () =
        apply(values[idx].cint)
        for j in 0 ..< group.len:
          group[j].checked = (j == idx)
    for i in 0 ..< labels.len:
      group[i] = menu.addItem(labels[i], makeAction(i))
      group[i].checked = (values[i] == current)

  # Boot device. Reaches the guest as DIP switch bits of port 0x1ff0, so it
  # takes effect on the next reset. The original also lists "HARD DISK"
  # (value 7); omitted here, since this app has no way to mount one.
  let bootMenu = deviceMenu.addSubmenu("Boot Device")
  bootMenu.addRadioGroup(
    @["5/3-inch 2D", "5/3-inch 2DD", "5/3-inch 2HD", "8-inch 1S"],
    @[0, 1, 2, 6], bx1GetDriveType(h).int,
    proc (v: cint) = bx1SetDriveType(h, v))

  let keyboardMenu = deviceMenu.addSubmenu("Keyboard")
  keyboardMenu.addRadioGroup(
    @["Keyboard Mode A", "Keyboard Mode B"], @[0, 1], bx1GetKeyboardType(h).int,
    proc (v: cint) = bx1SetKeyboardType(h, v))

  let soundMenu = deviceMenu.addSubmenu("Sound")
  soundMenu.addRadioGroup(
    @["PSG", "CZ-8BS1 x1", "CZ-8BS1 x2"], @[0, 1, 2], bx1GetSoundType(h).int,
    proc (v: cint) = bx1SetSoundType(h, v))
  soundMenu.addSeparator()
  # The drive noise the machine mixes in alongside the synthesized
  # channels. The original's three CMT sources (noise, signal, voice) sit
  # here too, but they are left out for the same reason as the CMT menu
  # above: nothing in this app can put a tape in the deck to hear them.
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
  # Device names come from the core's own sound_device_caption table
  # ("PSG", "CZ-8BS1 #1", "CMT (Signal)", "Noise (FDD)", "Noise (CMT)"),
  # so the labels cannot drift from the channels they control - and the
  # tape ones are recognised by that same caption rather than by index,
  # which the table is free to renumber.
  var volumeDevices: seq[int] # core device indices, CMT ones filtered out
  for i in 0 ..< volumeCount:
    if "CMT" notin $bx1GetSoundDeviceCaption(i.cint):
      volumeDevices.add i
  # Sliders stay indexed by the core's device number, so the rows that are
  # skipped simply leave a nil entry nothing ever touches.
  var volumeL = newSeq[Slider](volumeCount)
  var volumeR = newSeq[Slider](volumeCount)
  let volumeWin = newWindow("Volume", 360, 30 * volumeDevices.len + 40, false)
  volumeWin.margined = true
  let volumeGrid = newGrid(true)
  proc makeVolumeChanged(dev: int): proc (sender: Slider) =
    result = proc (sender: Slider) =
      bx1SetVolume(h, dev.cint, volumeL[dev].value.cint, volumeR[dev].value.cint)
  for row, i in volumeDevices:
    volumeGrid.add(newLabel($bx1GetSoundDeviceCaption(i.cint)), 0, row * 2, 1, 2,
      false, AlignStart, false, AlignCenter)
    # Range matches the core's own clamp on set_sound_device_volume.
    volumeL[i] = newSlider(-40 .. 0, makeVolumeChanged(i))
    volumeR[i] = newSlider(-40 .. 0, makeVolumeChanged(i))
    volumeL[i].value = bx1GetVolumeL(h, i.cint).int
    volumeR[i].value = bx1GetVolumeR(h, i.cint).int
    volumeGrid.add(volumeL[i], 1, row * 2, 1, 1, true, AlignFill, false, AlignCenter)
    volumeGrid.add(volumeR[i], 1, row * 2 + 1, 1, 1, true, AlignFill, false, AlignCenter)
  volumeWin.child = volumeGrid
  volumeWin.onClosing = proc (sender: Window): bool =
    # Hide rather than destroy, and return false so libui-ng does not
    # destroy it either - the same rule the main window follows, for the
    # same reason (uing destroys the window from inside its own
    # "should close" delegate callback, which crashes).
    volumeWin.hide()
    false

  # --- Host menu ---
  # The original's Host menu is mostly Win32 renderer plumbing (Use
  # Direct2D1 / Direct3D9 / DirectInput / Disable Windows 8 DWM) plus video
  # and sound recording, whose OSD backends are stubs here (DevelopmentPlan
  # 0.6 group B). What is left and genuinely works is kept, with the
  # original's wording:
  #
  # * Screen: the original's window/fullscreen pair. Its stretch and rotate
  #   variants need scaling modes this port does not implement.
  # * Volume: the same per-device mixer the original's dialog exposes.
  # * Show Status Bar.
  #
  # Not carried over from the original's Host > Sound submenu: the sample
  # rate and latency choices. The audio device is opened once at the rate
  # the core reports and there is no reopen path, so those items would set
  # a value nothing re-reads.
  let hostMenu = nativemenu.addMenu("Host")
  let screenMenu = hostMenu.addSubmenu("Screen")
  var screenItems: array[2, MenuItemRef]
  var isFullscreen = false
  proc applyFullscreen(on: bool) =
    if sdlWin != nil:
      discard sdlWin.setFullscreen(if on: SDL_WINDOW_FULLSCREEN_DESKTOP else: 0)
    isFullscreen = on
    for j in 0 ..< 2:
      screenItems[j].checked = (j == (if on: 1 else: 0))
  screenItems[0] = screenMenu.addItem("Window x1", proc () = applyFullscreen(false))
  # Carries the shortcut, and toggles rather than only entering fullscreen,
  # so there is always a way back out: in fullscreen the menu bar is only
  # reachable by knowing to push the pointer at the top of the screen, and
  # a user who does not know that is stuck. Ctrl-Cmd-F is what macOS uses
  # for Enter/Exit Full Screen everywhere else.
  #
  # Not the original's Alt+Enter: on this port Option is the X1's GRAPH key
  # (keymap.nim), so that combination belongs to the guest.
  screenItems[1] = screenMenu.addItem("Fullscreen 640x400",
    proc () = applyFullscreen(not isFullscreen),
    key = "f", mods = ModCommand or ModControl)
  screenItems[0].checked = true

  hostMenu.addItem("Volume", proc () = volumeWin.show())
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
    SDL_WINDOWPOS_UNDEFINED, ScreenWidth.cint, windowHeight(), SDL_WINDOW_HIDDEN)
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
  # Everything is drawn in 640x(400[+24]) coordinates and SDL scales that
  # to whatever the window actually is, so fullscreen fills the display
  # instead of leaving the picture in a corner.
  discard renderer.setLogicalSize(ScreenWidth.cint, windowHeight())

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
    renderer.clear()
    var screenDst = rect(0.cint, 0.cint, ScreenWidth.cint, ScreenHeight.cint)
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
      font.draw(renderer, ScreenWidth.cint - font.width(fpsText) - 6, textY, fpsText,
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
  hostconfig.save(paths.hostConfigPath(), hostCfg)

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
