#!/bin/bash
# Development-only build of the Nim application, linked against
# build/libbubix1core.a (run scripts/build_core.sh first).
#
# This is NOT the release packaging script - that is scripts/build_macos.sh,
# which produces the .app bundle and the dmg. This script exists so the app
# can be iterated on locally without going through CI or a full bundle; it
# shares the actual compiler invocation with the release build via
# scripts/build_nim_app.sh, and differs only in linking SDL2 from
# build/frameworks in place rather than from inside a bundle.
#
# Usage: ./scripts/build_app_macos_dev.sh
# Then:  ./build/BubiX1turboZ
#   No arguments: ROMs, config and save states are read from
#   ~/Library/Application Support/BubiX1turboZ (see src/nim/bubix1/paths.nim).

set -eu
cd "$(dirname "$0")/.."

./scripts/fetch_sdl2_framework.sh
exec ./scripts/build_nim_app.sh build/BubiX1turboZ "$(pwd)/build/frameworks"
