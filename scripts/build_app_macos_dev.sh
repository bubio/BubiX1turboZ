#!/bin/bash
# Development-only build of the Nim application, linked against
# build/libbubix1core.a (run scripts/build_core.sh first).
#
# This is NOT the release packaging script (that is scripts/build_macos.sh,
# added in phase 9 - .app bundle, icon, dmg). This script exists so the app
# can be iterated on locally without going through CI or a full bundle.
#
# Usage: ./scripts/build_app_macos_dev.sh
# Then:  ./build/BubiX1turboZ <rom_dir> [d88_path]
#   rom_dir is a temporary positional arg until phase 6's path module
#   (~/Library/Application Support/BubiX1turboZ/roms) replaces it.

set -eu
cd "$(dirname "$0")/.."

LIB=build/libbubix1core.a
if [ ! -f "$LIB" ]; then
  echo "error: $LIB not found - run ./scripts/build_core.sh first" >&2
  exit 1
fi

SDL_CFLAGS="$(sdl2-config --cflags)"

# .nimble is the single source of truth for the app version (see its own
# comment); read it here rather than hardcoding it a second time in the
# Nim source, so the About dialog can display it.
APP_VERSION="$(grep '^version' *.nimble | sed -E 's/.*"(.*)".*/\1/')"

mise exec -- nim c -d:release --hints:off \
  --dynlibOverride:SDL2 \
  --passC:"$SDL_CFLAGS -Isrc/bridge" \
  --passL:"-L/opt/homebrew/lib -lSDL2 $(pwd)/$LIB -lc++" \
  --path:src \
  -d:appVersion="$APP_VERSION" \
  -o:build/BubiX1turboZ \
  src/nim/bubix1turboz.nim

echo "built build/BubiX1turboZ"
