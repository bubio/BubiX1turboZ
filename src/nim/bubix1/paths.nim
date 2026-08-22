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

# KNOWNFOLDERID GUIDs for userMediaDir below (FOLDERID_Music,
# FOLDERID_Pictures), byte-swapped from their canonical string form into a
# GUID struct's little-endian Data1/Data2/Data3 layout. Declared
# unconditionally (they are inert data on every other platform) so the one
# Windows-only call site does not need its own `when`.
const
  FolderIdMusic: array[16, uint8] = [
    0x71'u8, 0xd5'u8, 0xd8'u8, 0x4b'u8, 0x19'u8, 0x6d'u8, 0xd3'u8, 0x48'u8,
    0xbe'u8, 0x97'u8, 0x42'u8, 0x22'u8, 0x20'u8, 0x08'u8, 0x0e'u8, 0x43'u8]
  FolderIdPictures: array[16, uint8] = [
    0x30'u8, 0x81'u8, 0xe2'u8, 0x33'u8, 0x1e'u8, 0x4e'u8, 0x76'u8, 0x46'u8,
    0x83'u8, 0x5a'u8, 0x98'u8, 0x39'u8, 0x5c'u8, 0x3b'u8, 0xc3'u8, 0xbb'u8]

when defined(windows):
  import std/widestrs

  proc shGetKnownFolderPath(rfid: pointer, flags: uint32,
    token: pointer, path: pointer): int32
    {.importc: "SHGetKnownFolderPath", stdcall, dynlib: "shell32".}
    ## `rfid`/`path` are untyped pointers rather than the real KNOWNFOLDERID*
    ## / PWSTR* so that MinGW's stricter -Wincompatible-pointer-types (an
    ## error there, not a warning) does not reject the array[16, uint8] /
    ## WideCString this app passes them as - a real REFKNOWNFOLDERID has no
    ## Nim-side equivalent worth declaring for the one call site below.
    ## `dynlib` alone, no `header`: matches ui/windows/hostlang.nim's own
    ## Win32 call, and sidesteps needing windows.h included first.
  proc coTaskMemFree(p: pointer)
    {.importc: "CoTaskMemFree", stdcall, dynlib: "ole32".}

  proc knownFolder(guid: array[16, uint8]): string =
    ## "" if the call fails - a profile without the folder redirected
    ## anywhere unusual should not, but userMediaDir below falls back to a
    ## fixed path rather than trust that absolutely.
    var wpath: WideCString
    if shGetKnownFolderPath(unsafeAddr guid, 0, nil, addr wpath) == 0 and
        wpath != nil:
      result = $wpath
      coTaskMemFree(cast[pointer](wpath))

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

proc userMediaDir(xdgName, xdgFallback, macFolder: string,
                  winGuid: array[16, uint8]): string =
  ## A folder of the user's own, below which this app makes one of its
  ## own: `~/Music/BubiX1turboZ` and the equivalents elsewhere.
  when defined(macosx):
    getHomeDir() / macFolder / appName
  elif defined(windows):
    # SHGetKnownFolderPath, not a fixed "%USERPROFILE%\Music": either
    # folder can be redirected elsewhere (a different drive, a synced
    # location), and the display name is localized on a non-English
    # Windows besides.
    let known = knownFolder(winGuid)
    (if known.len > 0: known else: getHomeDir() / macFolder) / appName
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
  userMediaDir("XDG_MUSIC_DIR", "Music", "Music", FolderIdMusic)

proc screenshotsDir*(): string =
  ## Host > Capture Screen writes here, for the same reason.
  userMediaDir("XDG_PICTURES_DIR", "Pictures", "Pictures", FolderIdPictures)

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
