#!/bin/bash
# Development-only build of the Nim application on Linux, linked against
# build/libbubix1core.a (built here if missing) and the system SDL2.
#
# This is NOT the release packaging script - that is scripts/build_linux.sh,
# which produces the AppImage and the .deb. This script exists so the app
# can be iterated on locally without packaging; it shares the actual
# compiler invocation with the release build via scripts/build_nim_app.sh.
#
# Usage: ./scripts/build_app_linux_dev.sh
# Then:  ./build/BubiX1turboZ
#   No arguments: ROMs, config and save states are read from
#   $XDG_DATA_HOME/BubiX1turboZ (or ~/.local/share/BubiX1turboZ - see
#   src/nim/bubix1/paths.nim).

set -eu
cd "$(dirname "$0")/.."

if [ ! -f build/libbubix1core.a ]; then
  ./scripts/build_core.sh
fi

# $ORIGIN: a loose dev binary finds the system SDL2 through the linker's
# default search path anyway, so the rpath only matters for a relocated
# copy; keeping it next-to-binary matches how the AppImage is laid out.
exec ./scripts/build_nim_app.sh build/BubiX1turboZ '$ORIGIN'
