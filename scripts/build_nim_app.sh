#!/bin/bash
# Compiles the Nim application against build/libbubix1core.a and the SDL2
# framework in build/frameworks.
#
# Shared by scripts/build_app_macos_dev.sh (loose binary, run from the repo)
# and scripts/build_macos.sh (binary that ends up inside the .app), which
# differ only in where the executable goes and where it looks for SDL2 at
# run time. Keeping one copy of the compiler invocation means the released
# build and the one iterated on locally cannot drift apart.
#
# Usage: ./scripts/build_nim_app.sh <output-path> <rpath>
#   output-path  where to write the executable
#   rpath        run-time search path for SDL2.framework, e.g.
#                @executable_path/../Frameworks for a bundled binary

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

FRAMEWORKS="$(pwd)/build/frameworks"
if [ ! -d "$FRAMEWORKS/SDL2.framework" ]; then
  echo "error: $FRAMEWORKS/SDL2.framework not found -" \
       "run ./scripts/fetch_sdl2_framework.sh first" >&2
  exit 1
fi

# Matches LSMinimumSystemVersion in the .app's Info.plist and the support
# window stated in README.md. clang reads this from the environment, which
# covers both the C the Nim compiler emits and the link step.
export MACOSX_DEPLOYMENT_TARGET=13.5

# .nimble is the single source of truth for the app version (see its own
# comment); read it here rather than hardcoding it a second time in the
# Nim source, so the About dialog can display it.
APP_VERSION="$(grep '^version' ./*.nimble | sed -E 's/.*"(.*)".*/\1/')"

# --dynlibOverride:SDL2: the Nim sdl2 binding dlopens libSDL2.dylib by
# default, which no longer exists as a standalone file in this setup (SDL2
# lives inside a framework). Resolving the symbols at link time instead is
# what makes -framework SDL2 the whole story.
mise exec -- nim c -d:release --hints:off \
  --dynlibOverride:SDL2 \
  --passC:"-F$FRAMEWORKS -I$FRAMEWORKS/SDL2.framework/Headers -Isrc/bridge" \
  --passL:"-F$FRAMEWORKS -framework SDL2 -Wl,-rpath,$RPATH $(pwd)/$LIB -lc++" \
  --path:src \
  -d:appVersion="$APP_VERSION" \
  -o:"$OUT" \
  src/nim/bubix1turboz.nim

echo "built $OUT"
