#!/bin/bash
# Development-only build of the Nim application on Windows, linked against
# build/libbubix1core.a (built here if missing) and the fetched SDL2 mingw
# devel package.
#
# This is NOT the release packaging script - that is scripts/build_windows.sh,
# which produces the installable zip. This script exists so the app can be
# iterated on locally without packaging; it shares the actual compiler
# invocation with the release build via scripts/build_nim_app.sh.
#
# Must run under a bash that reports itself as MINGW*/MSYS* to uname -s (Git
# Bash or an MSYS2 shell) - the shell the rest of this project's scripts
# already assume, and the one build_core.sh/build_nim_app.sh branch on.
#
# Usage: ./scripts/build_app_windows_dev.sh
# Then:  build/BubiX1turboZ.exe (this script stages SDL2.dll beside it -
#        without it Windows refuses to start the exe at all, with
#        STATUS_DLL_NOT_FOUND. libgcc/libstdc++/libwinpthread are linked
#        statically into the exe - see build_nim_app.sh.)
#   No arguments: ROMs, config and save states are read from
#   %LOCALAPPDATA%\BubiX1turboZ (see src/nim/bubix1/paths.nim).

set -eu
cd "$(dirname "$0")/.."

if [ ! -f build/libbubix1core.a ]; then
  ./scripts/build_core.sh
fi
if [ ! -f build/toolchain/mingw-windows/env.sh ]; then
  ./scripts/fetch_mingw_windows.sh
fi

./scripts/build_nim_app.sh build/BubiX1turboZ.exe ''

SDL2_BIN_DIR="$(pwd)/build/toolchain/sdl2-windows/x86_64-w64-mingw32/bin"
cp "$SDL2_BIN_DIR/SDL2.dll" build/SDL2.dll
