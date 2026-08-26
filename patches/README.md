# patches/

Patches against the vendored Common Source Code Project core under `src/core/`.

The core is normally taken from upstream unmodified, and problems are absorbed
in the bridge or in the Nim application layer. A patch lands here only when a
defect is genuinely inside the core and cannot be reached from above. Every
patch must have a matching entry in `docs/dev/DevelopmentPlan.md` explaining
the defect, the evidence for it, and how it was verified.

Re-vendoring the core silently drops these patches, so run
`scripts/apply_core_patches.sh` after every re-import.

## Usage

```sh
scripts/apply_core_patches.sh          # apply every patch not yet applied
scripts/apply_core_patches.sh --check  # report status, change nothing
```

Both forms are idempotent: an already-applied patch is reported and skipped.

## Current patches

| Patch | Affects | Summary |
|---|---|---|
| `0001-x1-display-zpal-slot-routing.patch` | `src/core/vm/x1/display.cpp` | `get_zpal_num()` gated the 8 colour (ASIC palette RAM) fold on `hireso`, so in 200 lines / 80 columns a palette write could never reach the eight `zpal[]` corners the renderer actually reads. Seven of the eight graphics colours stayed at their identity values. Present in upstream and reproducible in the original Windows build. |
| `0002-windows-sdl-common-portability.patch` | `src/core/common.h`, `src/core/common.cpp` | Two upstream `#if` conditions use `_WIN32` as a proxy for "the native win32 OSD, built with MSVC" - true until this project started building the *SDL* OSD directly on Windows with MinGW GCC. (1) `set_application_path()`'s declaration/definition were `#if !defined(_WIN32)`, so the host-supplied ROM/settings directory this app requires (BluePrint: never next to the executable) had no way to reach the core on Windows; `get_application_path()`'s win32 branch (`GetModuleFileName`-derived) is now also excluded when `_USE_SDL` is defined, so a Windows/SDL build falls through to the override-based path instead. (2) `to_upper` (`#ifndef _MSC_VER`, so GCC compiles it where MSVC does not) calls `std::toupper` from `<cctype>`, which the `_WIN32` include branch never pulled in - MSVC's own headers must supply it transitively, GCC's do not. |
| `0003-windows-io-h-guard-collision.patch` | `src/core/vm/io.h` | The header guard `_IO_H_` collides with MinGW's own system `<io.h>` (the CRT header for `_access()` etc.), which `common.h` includes ahead of this file in every translation unit on Windows. The system header's identical guard name made the preprocessor believe this file had already been included, so its body - `class IO` - silently never compiled, leaving every user of `IO` (`vm/x1/x1.cpp` among others) an "incomplete type" error. Renamed to the file-specific `_BX1_VM_IO_H_`. |
| `0004-x1-display-zpalette-reset-leak.patch` | `src/core/vm/x1/display.cpp`, `src/core/vm/x1/display.h` | `DISPLAY::reset()` never restored `zpal[]` (the ASIC 4096 colour palette RAM) to its identity ramp, only `initialize()` did. `zpalette_pc[8..15]` - the 8 colour fold every title reads regardless of `AEN`, see `get_zpal_num()`'s comment - is aliased from the eight `zpal[]` corners by `update_zpalette()`, so a title that never touches the ASIC palette still renders through a stale mapping left by whatever title ran before it in the same session. Loading a new title over "Reset" (menu, or the auto-reset after mounting media) reproduced this reliably: colours from a previous 4096 colour title bled into a following 8 colour title's picture. Extracted the identity-ramp fill (`zpal[]`, `ztpal[]`, `zpalette_tmp[]`, `zpalette_changed`) from `initialize()` into `reset_zpalette()` and call it from both `initialize()` and `reset()`. |

Patches 0002 and 0003 were found and verified while bringing up the Windows
port (bash session, 2026-08-22): `scripts/build_core.sh` failed to compile
`src/bridge/bubix1_api.cpp`, `src/core/vm/x1/x1.cpp` and `src/core/common.cpp`
under the MinGW-w64 toolchain `scripts/fetch_mingw_windows.sh` pins, with the
errors these patches fix. `docs/dev/DevelopmentPlan.md` was not present on
that machine (it is untracked per CLAUDE.md) to record this against; add an
entry there from a checkout that has it.
