#!/bin/bash
# Downloads a pinned MinGW-w64 GCC (winlibs.com's redistributable build) and
# unpacks it into build/toolchain/mingw-windows.
#
# The official Nim Windows zip (scripts/install_nim_windows.sh) does not
# bundle a C compiler - checked directly, no gcc.exe anywhere under it, only
# in older Nim releases - so this is a second, independent download. Pinned
# the same way as every other fetched toolchain piece in this project
# (scripts/fetch_sdl2_framework.sh, scripts/fetch_sdl2_windows.sh): an exact
# version and a checksum, so local and CI builds compile with the same GCC.
#
# posix threads / SEH exceptions / UCRT: SEH is the only exception model
# x86_64 Windows supports for correct unwinding through system DLLs; UCRT
# needs no redistributable on Windows 10/11, which is this project's floor
# (CLAUDE.md, README). "posix" (not "win32") threads is what lets libstdc++
# use std::thread, which the C++ core does not need but Nim's own runtime
# assumes is available.
#
# Usage: ./scripts/fetch_mingw_windows.sh
# Result: build/toolchain/mingw-windows/bin/{gcc,g++,ar}.exe, and
#         build/toolchain/mingw-windows/env.sh exporting MINGW_BIN_DIR.

set -eu
cd "$(dirname "$0")/.."

MINGW_RELEASE_TAG=16.2.0posix-14.0.0-ucrt-r1
MINGW_ASSET=winlibs-x86_64-posix-seh-gcc-16.2.0-mingw-w64ucrt-14.0.0-r1.zip
MINGW_ZIP_SHA256=c1f52294597c0b73786b2a78eb5d176d89226d2f21875eab75e783a8b1cefcc4

DEST=build/toolchain/mingw-windows
STAMP="$DEST/.mingw-version"
ENV_FILE="$DEST/env.sh"

if [ -f "$STAMP" ] && [ "$(cat "$STAMP" 2>/dev/null || true)" = "$MINGW_RELEASE_TAG" ] \
    && [ -f "$ENV_FILE" ]; then
  echo "mingw-w64 $MINGW_RELEASE_TAG already present in $DEST"
  exit 0
fi

URL="https://github.com/brechtsanders/winlibs_mingw/releases/download/$MINGW_RELEASE_TAG/$MINGW_ASSET"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "downloading $URL"
curl -fsSL -o "$WORK/mingw.zip" "$URL"

actual="$(sha256sum "$WORK/mingw.zip" | cut -d' ' -f1)"
if [ "$actual" != "$MINGW_ZIP_SHA256" ]; then
  echo "error: checksum mismatch for $MINGW_ASSET" >&2
  echo "  expected $MINGW_ZIP_SHA256" >&2
  echo "  actual   $actual" >&2
  exit 1
fi

rm -rf "$DEST"
mkdir -p "$DEST"
unzip -q "$WORK/mingw.zip" -d "$WORK/extracted"
# The zip wraps everything in a single "mingw64" directory.
mv "$WORK/extracted/mingw64"/* "$DEST"/

# GCC's own *endfile link spec unconditionally links
# x86_64-w64-mingw32/lib/default-manifest.o into every non-shared build
# (`%:if-exists(default-manifest.o%s)` - see `gcc -dumpspecs`), and this
# build of ld has no -Wl,--no-default-manifest to tell it to prefer this
# app's own manifest instead (build_nim_app.sh links one in) - the two
# together fail the link outright ("multiple non-default manifests").
# Renaming it out of gcc's search path is the one working fix found: `-B`
# to shadow it with a same-named replacement was tried first and broke the
# CRT object selection instead (missing WinMain, missing RTTI symbols).
# Safe here because this is this project's own pinned, private copy of the
# toolchain, not a shared system install.
DEFAULT_MANIFEST="$DEST/x86_64-w64-mingw32/lib/default-manifest.o"
if [ -f "$DEFAULT_MANIFEST" ]; then
  mv "$DEFAULT_MANIFEST" "$DEFAULT_MANIFEST.disabled"
fi

echo "MINGW_BIN_DIR='$(cd "$DEST/bin" && pwd)'" > "$ENV_FILE"
echo "$MINGW_RELEASE_TAG" > "$STAMP"
echo "unpacked $DEST ($MINGW_RELEASE_TAG)"
