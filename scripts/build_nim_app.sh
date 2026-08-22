#!/bin/bash
# Compiles the Nim application against build/libbubix1core.a and SDL2.
#
# Shared by the dev and release build scripts of each platform so the
# released build and the one iterated on locally cannot drift apart:
#   macOS    build_app_macos_dev.sh / build_macos.sh     (SDL2.framework)
#   Linux    build_app_linux_dev.sh / build_linux.sh     (system libSDL2)
#   Windows  build_app_windows_dev.sh / build_windows.sh (fetched SDL2 mingw devel)
# They differ only in where the executable goes and where it looks for SDL2
# at run time.
#
# Usage: ./scripts/build_nim_app.sh <output-path> <rpath>
#   output-path  where to write the executable
#   rpath        run-time search path for SDL2, passed to the linker as-is:
#                @executable_path/../Frameworks for a bundled macOS binary,
#                $ORIGIN or $ORIGIN/../lib for a Linux one

set -eu
cd "$(dirname "$0")/.."

if [ $# -ne 2 ]; then
  echo "usage: $0 <output-path> <rpath>" >&2
  exit 1
fi
OUT="$1"
RPATH="$2"

LIB=build/libbubix1core.a
if [ ! -f "$LIB" ]; then
  echo "error: $LIB not found - run ./scripts/build_core.sh first" >&2
  exit 1
fi

# .nimble is the single source of truth for the app version (see its own
# comment); read it here rather than hardcoding it a second time in the
# Nim source, so the About dialog can display it.
APP_VERSION="$(grep '^version' ./*.nimble | sed -E 's/.*"(.*)".*/\1/')"

# --dynlibOverride:SDL2: the Nim sdl2 binding dlopens libSDL2 by default.
# Resolving its symbols at link time instead lets a single -framework SDL2
# (macOS) / -lSDL2 (Linux) be the whole story, so the run-time search path
# below is the only thing that decides where SDL2 is found.
NIM_CMD=(mise exec -- nim)
case "$(uname -s)" in
  Darwin)
    FRAMEWORKS="$(pwd)/build/frameworks"
    if [ ! -d "$FRAMEWORKS/SDL2.framework" ]; then
      echo "error: $FRAMEWORKS/SDL2.framework not found -" \
           "run ./scripts/fetch_sdl2_framework.sh first" >&2
      exit 1
    fi
    # Matches LSMinimumSystemVersion in the .app's Info.plist and the
    # support window stated in README.md. clang reads this from the
    # environment, which covers both the C the Nim compiler emits and the
    # link step.
    export MACOSX_DEPLOYMENT_TARGET=13.5
    PASSC="-F$FRAMEWORKS -I$FRAMEWORKS/SDL2.framework/Headers -Isrc/bridge"
    PASSL="-F$FRAMEWORKS -framework SDL2 -Wl,-rpath,$RPATH $(pwd)/$LIB -lc++"
    ;;
  MINGW*|MSYS*)
    # Windows: SDL2 and zlib.h from the fetched packages (no system SDL2,
    # no system zlib - see fetch_sdl2_windows.sh and deflate.nim); SDL2.dll
    # travels beside the executable (see build_app_windows_dev.sh /
    # build_windows.sh, which copy it) while the MinGW runtime is linked in
    # statically (see PASSL below).
    # mise cannot install nim here (see install_nim_windows.sh's own
    # comment for why), so both nim and the MinGW-w64 gcc it shells out to
    # come from the two fetched toolchains this project pins instead of
    # mise or PATH.
    if [ ! -f build/toolchain/nim-windows/env.sh ]; then
      ./scripts/install_nim_windows.sh
    fi
    if [ ! -f build/toolchain/mingw-windows/env.sh ]; then
      ./scripts/fetch_mingw_windows.sh
    fi
    ./scripts/fetch_sdl2_windows.sh
    . build/toolchain/nim-windows/env.sh
    . build/toolchain/mingw-windows/env.sh
    export PATH="$MINGW_BIN_DIR:$PATH"
    NIM_CMD=("$NIM_BIN_DIR/nim.exe")
    # pwd -W, not pwd: nim.exe spawns gcc.exe directly (no MSYS layer to
    # rewrite a POSIX-style /c/... argument for it), and Git Bash's own
    # auto-conversion of such arguments embedded in a longer flag like
    # -I/c/... is unreliable - confirmed empirically (one -I in a flag
    # string this way survived exec untranslated, the next didn't; MinGW's
    # gcc then reads /c/... as C:\c\... on the current drive and fails
    # with "No such file or directory"). The drive-letter form pwd -W
    # prints has no such ambiguity.
    WIN_ROOT="$(pwd -W)"
    SDL2_DIR="$WIN_ROOT/build/toolchain/sdl2-windows/x86_64-w64-mingw32"
    ZLIB_DIR="$WIN_ROOT/build/toolchain/zlib-windows"
    # -include windows.h: force-includes it ahead of every other header in
    # every compiled file, GCC's own mechanism for exactly this problem.
    # ui/windows/*.nim's {.header.} pragmas for commctrl.h/wingdi.h/gdiplus.h
    # need windows.h's typedefs (LONG, CALLBACK, ...) already visible, and
    # relying on Nim to emit its own #include lines in the right order
    # per-file was not reliable enough to trust (confirmed empirically).
    PASSC="-include windows.h -I$SDL2_DIR/include -I$SDL2_DIR/include/SDL2 -I$ZLIB_DIR -I$WIN_ROOT/src/bridge"

    # The exe cannot start without this manifest linked in (comctl32 v6 -
    # see assets/windows/app.manifest's own comment).
    # fetch_mingw_windows.sh disables GCC's own default-manifest.o (see its
    # comment) so this is the only one that reaches the link - two
    # manifests linked together fails outright ("multiple non-default
    # manifests"), it does not just prefer one.
    RES_OBJ="$WIN_ROOT/build/app-resource.o"
    "$MINGW_BIN_DIR/windres.exe" \
      -I "$WIN_ROOT/assets/windows" \
      "$WIN_ROOT/assets/windows/app.rc" -O coff -o "$RES_OBJ"

    # RPATH is unused on Windows - the loader finds SDL2.dll beside the exe
    # (or on PATH) with no linker-level search path to set, unlike an ELF
    # rpath or a macOS install name. libgcc/libstdc++/libwinpthread are
    # statically linked in instead of shipped as DLLs - the fetched MinGW
    # toolchain carries static archives for all three (winlibs' posix-
    # threads build) - so SDL2.dll is the only runtime piece that still
    # travels beside the exe (see build_app_windows_dev.sh / build_windows.sh).
    # A blanket -static was tried first and rejected: it also forces static
    # resolution of the Win32 import libraries SDL2 and this app need
    # (winmm, ole32, oleaut32, cfgmgr32, ...), most of which are never
    # named on this command line, so the link fails outright. -static-libgcc
    # covers libgcc (gcc's own driver logic honours it because gcc, not this
    # script, is the one appending -lgcc); libstdc++ and libwinpthread are
    # named explicitly below, so the same driver flag would not affect them
    # - they get their own -Wl,-Bstatic/-Bdynamic bracket instead, placed
    # after -lSDL2 so ld still resolves SDL2 the normal (dynamic-import-
    # library) way.
    # -mwindows: GUI subsystem, so Windows does not attach a console window
    # when the exe is launched (this app has no CLI, and errors already
    # reach the user through dialogs - see bubix1turboz.nim's own comment
    # on resolveOrWarn). -Wl,--entry=mainCRTStartup keeps the ordinary
    # main-based CRT entry point explicit regardless of subsystem, after
    # GCC's own default was once seen to flip to the WinMain-based one for
    # reasons not run down (a build that linked cleanly, changed in no way
    # related to entry point selection, then failed with "undefined
    # reference to WinMain" on an unchanged recompile - see git
    # history/session notes around this line if it recurs and is worth
    # investigating further).
    PASSL="-mwindows -Wl,--entry=mainCRTStartup -static-libgcc $WIN_ROOT/$LIB $RES_OBJ -L$SDL2_DIR/lib -lSDL2 -Wl,-Bstatic -lstdc++ -lwinpthread -Wl,-Bdynamic"
    ;;
  *)
    # Linux: SDL2 from the system (pkg-config), the C++ core and its
    # standard library resolved at link time. The GTK backends under
    # bubix1/ui/linux carry their own pkg-config flags, so nothing GTK is
    # named here. -ldl and -lpthread cover the core's OSD threads and the
    # sdl2 binding's dlopen. The rpath is single-quoted: Nim runs the link
    # command through a shell, which would otherwise expand $ORIGIN to
    # nothing and leave the AppImage unable to find its bundled SDL2.
    PASSC="$(pkg-config --cflags sdl2) -Isrc/bridge"
    PASSL="$(pwd)/$LIB $(pkg-config --libs sdl2) -Wl,-rpath,'$RPATH' -lstdc++ -lm -ldl -lpthread"
    ;;
esac

"${NIM_CMD[@]}" c -d:release --hints:off \
  --dynlibOverride:SDL2 \
  --passC:"$PASSC" \
  --passL:"$PASSL" \
  --path:src \
  -d:appVersion="$APP_VERSION" \
  -o:"$OUT" \
  src/nim/bubix1turboz.nim

echo "built $OUT"
