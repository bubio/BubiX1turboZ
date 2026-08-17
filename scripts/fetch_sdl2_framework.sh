#!/bin/bash
# Downloads the official SDL2 binary framework and unpacks it into
# build/frameworks/SDL2.framework.
#
# Why not Homebrew: `brew install sdl2` installs sdl2-compat (an SDL2 shim
# over SDL3), and its bottles - like SDL3's - are built with a deployment
# target equal to the bottle's macOS tag (minos 26.0 as of this writing).
# Copying those dylibs into the .app would silently raise the app's real
# system requirement far above the 13.5 this project targets. The upstream
# SDL2 framework from libsdl-org is universal (x86_64 + arm64), built for
# macOS 10.11 / 11.0, ships ad-hoc signed, and already carries an
# `@rpath/SDL2.framework/Versions/A/SDL2` install name, so it can be copied
# into Contents/Frameworks untouched.
#
# The download is cached: an already-unpacked framework of the pinned
# version is left alone, so this is cheap to call from every build.
#
# Usage: ./scripts/fetch_sdl2_framework.sh
# Result: build/frameworks/SDL2.framework

set -eu
cd "$(dirname "$0")/.."

# Pinned so local and CI builds link the same SDL. Update both lines
# together; the checksum is the release asset's, not the framework's.
SDL2_VERSION=2.32.10
SDL2_DMG_SHA256=4a7ac31640d70214e848f994be8a12849c0f97918a7e6c2e27a40036166d1a7f

DEST=build/frameworks
FRAMEWORK="$DEST/SDL2.framework"
STAMP="$DEST/.sdl2-version"

if [ -d "$FRAMEWORK" ] && [ "$(cat "$STAMP" 2>/dev/null || true)" = "$SDL2_VERSION" ]; then
  echo "SDL2.framework $SDL2_VERSION already present in $DEST"
  exit 0
fi

URL="https://github.com/libsdl-org/SDL/releases/download/release-$SDL2_VERSION/SDL2-$SDL2_VERSION.dmg"
WORK="$(mktemp -d)"
MOUNT="$WORK/mnt"
# hdiutil leaves the image attached if anything below fails.
cleanup() {
  [ -d "$MOUNT" ] && hdiutil detach -quiet "$MOUNT" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

echo "downloading $URL"
curl -fsSL -o "$WORK/SDL2.dmg" "$URL"

actual="$(shasum -a 256 "$WORK/SDL2.dmg" | cut -d' ' -f1)"
if [ "$actual" != "$SDL2_DMG_SHA256" ]; then
  echo "error: checksum mismatch for SDL2-$SDL2_VERSION.dmg" >&2
  echo "  expected $SDL2_DMG_SHA256" >&2
  echo "  actual   $actual" >&2
  exit 1
fi

mkdir -p "$MOUNT"
hdiutil attach -nobrowse -quiet -mountpoint "$MOUNT" "$WORK/SDL2.dmg"

rm -rf "$FRAMEWORK"
mkdir -p "$DEST"
# ditto, not cp: it preserves the framework's symlinks and its ad-hoc code
# signature, which must stay valid for the copy inside the .app.
ditto "$MOUNT/SDL2.framework" "$FRAMEWORK"
echo "$SDL2_VERSION" > "$STAMP"

codesign --verify "$FRAMEWORK"
echo "unpacked $FRAMEWORK ($SDL2_VERSION)"
