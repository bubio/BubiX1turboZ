#!/bin/bash
# Compiles the Nim application against build/libbubix1core.a and SDL2.
#
# Shared by the dev and release build scripts of each platform so the
# released build and the one iterated on locally cannot drift apart:
#   macOS  build_app_macos_dev.sh / build_macos.sh   (SDL2.framework)
#   Linux  build_app_linux_dev.sh / build_linux.sh   (system libSDL2)
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
if [ "$(uname -s)" = "Darwin" ]; then
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
  PASSC="-F$FRAMEWORKS -I$FRAMEWORKS/SDL2.framework/Headers -Isrc/bridge"
  PASSL="-F$FRAMEWORKS -framework SDL2 -Wl,-rpath,$RPATH $(pwd)/$LIB -lc++"
else
  # Linux: SDL2 from the system (pkg-config), the C++ core and its standard
  # library resolved at link time. The GTK backends under bubix1/ui/linux
  # carry their own pkg-config flags, so nothing GTK is named here. -ldl and
  # -lpthread cover the core's OSD threads and the sdl2 binding's dlopen.
  # The rpath is single-quoted: Nim runs the link command through a shell,
  # which would otherwise expand $ORIGIN to nothing and leave the AppImage
  # unable to find its bundled SDL2.
  PASSC="$(pkg-config --cflags sdl2) -Isrc/bridge"
  PASSL="$(pwd)/$LIB $(pkg-config --libs sdl2) -Wl,-rpath,'$RPATH' -lstdc++ -lm -ldl -lpthread"
fi

mise exec -- nim c -d:release --hints:off \
  --dynlibOverride:SDL2 \
  --passC:"$PASSC" \
  --passL:"$PASSL" \
  --path:src \
  -d:appVersion="$APP_VERSION" \
  -o:"$OUT" \
  src/nim/bubix1turboz.nim

echo "built $OUT"
