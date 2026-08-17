## Platform-conventional storage locations for BubiX1turboZ.
##
## Nothing is ever written next to the executable (BluePrint: "実行ファイル
## と同じ場所に置くのはNG"). Everything this app owns lives under one base
## directory per platform, named by `appDataDir` below, and the two folders
## that hold things the *user* goes looking for (recordings, screenshots)
## sit in the host's own Music and Pictures folders instead.
##
## This module is host-dependent but not user interface, so it stays out of
## `ui/` - it needs no backend, only the right branch. It is the one place
## outside `ui/` that is allowed to name a platform.

import std/os

const appName = "BubiX1turboZ"

proc appDataDir*(): string =
  ## The single base directory. One directory rather than the config/data
  ## split XDG would suggest, because 7z and zip archives are expanded
  ## "設定ファイルと同じフォルダ" (CLAUDE.md, following Bubilator88) - and
  ## since ROMs, save states and expanded archives are what dominate it,
  ## the data location is the one it is placed at.
  when defined(macosx):
    getHomeDir() / "Library" / "Application Support" / appName
  elif defined(windows):
    # LOCALAPPDATA rather than APPDATA: a roaming profile should not carry
    # ROM images and save states between machines. APPDATA is the fallback
    # for the rare account that has no local one.
    let local = getEnv("LOCALAPPDATA", getEnv("APPDATA"))
    if local.len > 0: local / appName
    else: getHomeDir() / "AppData" / "Local" / appName
  else:
    let xdg = getEnv("XDG_DATA_HOME")
    if xdg.len > 0: xdg / appName
    else: getHomeDir() / ".local" / "share" / appName

proc userMediaDir(xdgName, xdgFallback, macFolder: string): string =
  ## A folder of the user's own, below which this app makes one of its
  ## own: `~/Music/BubiX1turboZ` and the equivalents elsewhere.
  when defined(macosx):
    getHomeDir() / macFolder / appName
  elif defined(windows):
    # The correct call is SHGetKnownFolderPath(FOLDERID_Music /
    # FOLDERID_Pictures); this is where those resolve to on a default
    # profile, and stands in until Windows is actually built.
    getHomeDir() / macFolder / appName
  else:
    # XDG_MUSIC_DIR and XDG_PICTURES_DIR are declared in
    # ~/.config/user-dirs.dirs rather than exported, so they are usually
    # unset in a process's environment; honour them when a session does
    # export them and fall back to the names xdg-user-dirs creates.
    let dir = getEnv(xdgName)
    if dir.len > 0: dir / appName
    else: getHomeDir() / xdgFallback / appName

proc romsDir*(): string =
  ## BIOS/ROM files. This is the single `base_dir` passed to `bx1_create`
  ## (the core only resolves paths against one base directory - see
  ## docs/dev/VendorPatches.md, "get_application_path"), so config/state
  ## files below live in *separate* directories rather than alongside it.
  appDataDir() / "roms"

proc configFilePath*(): string =
  appDataDir() / "config.ini"

proc recentFilesPath*(): string =
  ## Not part of the core's own config_t (its recent_*_path fields are
  ## never populated by this vendored tree - see the phase 6 notes in
  ## docs/dev/DevelopmentPlan.md). Tracked separately, one path per line.
  appDataDir() / "recent.txt"

proc hostConfigPath*(): string =
  ## Host-side preferences the core's own config_t cannot hold - see
  ## hostconfig.nim. Kept separate from config.ini so the core stays the
  ## sole owner of that file's format.
  appDataDir() / "host.ini"

proc statesDir*(): string =
  appDataDir() / "states"

proc extractedDir*(): string =
  ## Destination for expanded 7z/zip archives (phase 7).
  appDataDir() / "extracted"

proc scratchDir*(): string =
  ## Working files that are recreated on demand and never worth keeping:
  ## the raw VM blob on its way in or out of a save state, and the
  ## rollback dump `bx1_vm_state_load` needs. Deliberately not under the
  ## app's data directory - none of it is user data, and the core would
  ## otherwise put such files next to the ROMs (create_local_path).
  getTempDir() / appName

proc stateSlotPath*(slot: int): string =
  ## Slots 0-9; slot -1 is the quick save ⌘S/⌘L writes.
  statesDir() / (if slot < 0: "quick.bx1s" else: "slot" & $slot & ".bx1s")

proc recordingsDir*(): string =
  ## Host > Rec Sound writes here. Not under the app's data directory: a
  ## recording is something the user goes looking for later, so it belongs
  ## in the platform's own audio folder.
  userMediaDir("XDG_MUSIC_DIR", "Music", "Music")

proc screenshotsDir*(): string =
  ## Host > Capture Screen writes here, for the same reason.
  userMediaDir("XDG_PICTURES_DIR", "Pictures", "Pictures")

proc ensureDirsExist*() =
  ## Call once at startup, before bx1_create / load_config.
  ##
  ## `recordingsDir` and `screenshotsDir` are deliberately absent: they sit
  ## in the user's own Music and Pictures folders, and someone who never
  ## records or captures anything should not find empty folders there.
  ## Both are created when something is first written to them.
  createDir(romsDir())
  createDir(statesDir())
  createDir(extractedDir())
  createDir(scratchDir())
