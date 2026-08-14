## Platform-conventional storage locations for BubiX1turboZ.
##
## macOS only for now (this project's current priority platform - see
## CLAUDE.md). Linux (XDG) and Windows (%APPDATA%) equivalents are future
## work, out of scope until those platforms are targeted.
##
## Nothing is ever written next to the executable (BluePrint: "実行ファイル
## と同じ場所に置くのはNG"). Everything lives under
## `~/Library/Application Support/BubiX1turboZ/`.

import std/os

const appName = "BubiX1turboZ"

proc appSupportDir*(): string =
  ## Base directory: `~/Library/Application Support/BubiX1turboZ/`.
  getHomeDir() / "Library" / "Application Support" / appName

proc romsDir*(): string =
  ## BIOS/ROM files. This is the single `base_dir` passed to `bx1_create`
  ## (the core only resolves paths against one base directory - see
  ## docs/dev/VendorPatches.md, "get_application_path"), so config/state
  ## files below live in *separate* directories rather than alongside it.
  appSupportDir() / "roms"

proc configFilePath*(): string =
  appSupportDir() / "config.ini"

proc recentFilesPath*(): string =
  ## Not part of the core's own config_t (its recent_*_path fields are
  ## never populated by this vendored tree - see the phase 6 notes in
  ## docs/dev/DevelopmentPlan.md). Tracked separately, one path per line.
  appSupportDir() / "recent.txt"

proc hostConfigPath*(): string =
  ## Host-side preferences the core's own config_t cannot hold - see
  ## hostconfig.nim. Kept separate from config.ini so the core stays the
  ## sole owner of that file's format.
  appSupportDir() / "host.ini"

proc statesDir*(): string =
  appSupportDir() / "states"

proc extractedDir*(): string =
  ## Destination for expanded 7z/zip archives (phase 7).
  appSupportDir() / "extracted"

proc scratchDir*(): string =
  ## Working files that are recreated on demand and never worth keeping:
  ## the raw VM blob on its way in or out of a save state, and the
  ## rollback dump `bx1_vm_state_load` needs. Deliberately not under
  ## Application Support - none of it is user data, and the core would
  ## otherwise put such files next to the ROMs (create_local_path).
  getTempDir() / appName

proc stateSlotPath*(slot: int): string =
  ## Slots 0-9; slot -1 is the quick save ⌘S/⌘L writes.
  statesDir() / (if slot < 0: "quick.bx1s" else: "slot" & $slot & ".bx1s")

proc ensureDirsExist*() =
  ## Call once at startup, before bx1_create / load_config.
  createDir(romsDir())
  createDir(statesDir())
  createDir(extractedDir())
  createDir(scratchDir())
