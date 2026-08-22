#!/bin/bash
# Release build for Windows: static core -> Nim application -> a portable
# zip (exe, SDL2.dll, LICENSE). libgcc/libstdc++/libwinpthread are linked
# statically into the exe (see build_nim_app.sh), so SDL2.dll is the only
# runtime DLL that ships alongside it.
#
# This is the script CI runs (.github/workflows/build-windows.yml) and the
# one to use when producing something a user runs without installing
# anything - no installer, the same no-install model the Linux AppImage
# follows. For day-to-day work on the app, scripts/build_app_windows_dev.sh
# is faster and skips packaging.
#
# Usage: ./scripts/build_windows.sh [--skip-core] [--no-zip]
#   --skip-core  reuse an existing build/libbubix1core.a
#   --no-zip     stop at build/windows-stage, skip the zip - for CI's
#                non-release runs, so the uploaded artifact is the staged
#                files rather than a zip. actions/upload-artifact always
#                wraps what it uploads in its own zip for download, and
#                wrapping an already-zipped file that way leaves whoever
#                downloads it to test a build with a zip inside a zip.
#
# x86_64 is the only architecture this builds today - see README.md and
# CLAUDE.md for why (classic MinGW-w64 does not target Windows/arm64
# well; that needs llvm-mingw, left as future work rather than adding a
# second Windows toolchain to this project's build).
#
# Must run under a bash that reports itself as MINGW*/MSYS* to uname -s
# (Git Bash or an MSYS2 shell), matching build_core.sh/build_nim_app.sh.

set -eu
cd "$(dirname "$0")/.."

SKIP_CORE=0
NO_ZIP=0
for arg in "$@"; do
  case "$arg" in
    --skip-core) SKIP_CORE=1 ;;
    --no-zip) NO_ZIP=1 ;;
    *) echo "error: unknown option $arg" >&2; exit 1 ;;
  esac
done

APP_NAME=BubiX1turboZ
PKG=bubix1turboz

# .nimble is the single source of truth for the version (see its comment).
VERSION="$(grep '^version' ./*.nimble | sed -E 's/.*"(.*)".*/\1/')"

case "$(uname -m)" in
  x86_64) ARCH=x86_64 ;;
  *) echo "error: unsupported architecture $(uname -m) - only x86_64 is built today" >&2
     exit 1 ;;
esac

if [ "$SKIP_CORE" -eq 0 ]; then
  ./scripts/build_core.sh
fi

BIN="build/$APP_NAME.exe"
./scripts/build_nim_app.sh "$BIN" ''

STAGE="build/windows-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp "$BIN" "$STAGE/"
cp "build/toolchain/sdl2-windows/x86_64-w64-mingw32/bin/SDL2.dll" "$STAGE/"
cp LICENSE "$STAGE/LICENSE.txt"

if [ "$NO_ZIP" -eq 1 ]; then
  echo "staged $STAGE"
  exit 0
fi

OUT="build/$PKG-$VERSION-windows-$ARCH.zip"
rm -f "$OUT"
# Compress-Archive, not zip: Git Bash carries no zip binary, and
# PowerShell's is the one archiver every Windows machine this runs on
# already has (matches how scripts/fetch_sdl2_framework.sh reaches for
# ditto/hdiutil rather than a fetched tool - use what the platform gives).
powershell.exe -NoProfile -Command \
  "Compress-Archive -Path '$STAGE/*' -DestinationPath '$OUT' -Force"

echo "built $OUT"
