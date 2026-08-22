#!/bin/bash
# Downloads the official SDL2 MinGW-w64 development package and unpacks it
# into build/toolchain/sdl2-windows.
#
# Same SDL2 release as scripts/fetch_sdl2_framework.sh pins for macOS
# (2.32.10), so the two platforms run the same SDL. The package bundles
# SDL2.dll itself (bin/), the import library and headers to build against
# (lib/, include/) - everything scripts/build_nim_app.sh's Windows branch
# and scripts/build_windows.sh (which bundles the dll) need.
#
# The download is cached: an already-unpacked package of the pinned
# version is left alone, so this is cheap to call from every build.
#
# Usage: ./scripts/fetch_sdl2_windows.sh
# Result: build/toolchain/sdl2-windows/x86_64-w64-mingw32/{bin,include,lib}

set -eu
cd "$(dirname "$0")/.."

# Pinned so local and CI builds link the same SDL. Update both lines
# together; the checksum is the release asset's own.
SDL2_VERSION=2.32.10
SDL2_ZIP_SHA256=f15cff5fca62ec9381a016ef1d42a95c638cd72d2f226ba5781c76fe43dbd1ac

DEST=build/toolchain/sdl2-windows
STAMP="$DEST/.sdl2-version"

if [ -d "$DEST/x86_64-w64-mingw32" ] && \
    [ "$(cat "$STAMP" 2>/dev/null || true)" = "$SDL2_VERSION" ]; then
  echo "SDL2 $SDL2_VERSION (mingw) already present in $DEST"
  exit 0
fi

URL="https://github.com/libsdl-org/SDL/releases/download/release-$SDL2_VERSION/SDL2-devel-$SDL2_VERSION-mingw.zip"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "downloading $URL"
curl -fsSL -o "$WORK/sdl2.zip" "$URL"

actual="$(sha256sum "$WORK/sdl2.zip" | cut -d' ' -f1)"
if [ "$actual" != "$SDL2_ZIP_SHA256" ]; then
  echo "error: checksum mismatch for SDL2-devel-$SDL2_VERSION-mingw.zip" >&2
  echo "  expected $SDL2_ZIP_SHA256" >&2
  echo "  actual   $actual" >&2
  exit 1
fi

rm -rf "$DEST"
mkdir -p "$DEST"
unzip -q "$WORK/sdl2.zip" -d "$WORK/extracted"
mv "$WORK/extracted/SDL2-$SDL2_VERSION"/* "$DEST"/

echo "$SDL2_VERSION" > "$STAMP"
echo "unpacked $DEST ($SDL2_VERSION)"
