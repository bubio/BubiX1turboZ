#!/bin/bash
# Downloads the zlib source release and unpacks it into
# build/toolchain/zlib-windows.
#
# Windows has no system zlib (unlike macOS, which ships libz with the SDK,
# and Linux, which has it everywhere - see bubix1/deflate.nim's own
# comment). scripts/build_core.sh compiles this source straight into
# build/libbubix1core.a on that platform, so no zlib DLL ships or needs
# bundling - the same "vendor a pinned upstream release" pattern this
# project already uses for SDL2, applied to a static dependency instead of
# a dynamic one.
#
# Usage: ./scripts/fetch_zlib_windows.sh
# Result: build/toolchain/zlib-windows/{*.c,*.h}

set -eu
cd "$(dirname "$0")/.."

# Pinned so local and CI builds compile the same zlib. Update both lines
# together; the checksum is the release asset's own.
ZLIB_VERSION=1.3.2
ZLIB_ZIP_SHA256=e8bf55f3017aa181690990cb58a994e77885da140609fc8f94abe9b65d2cae28

DEST=build/toolchain/zlib-windows
STAMP="$DEST/.zlib-version"

if [ -f "$STAMP" ] && [ "$(cat "$STAMP" 2>/dev/null || true)" = "$ZLIB_VERSION" ]; then
  echo "zlib $ZLIB_VERSION already present in $DEST"
  exit 0
fi

# madler/zlib's release tag has no "v" in the asset's own directory name,
# but does in the git tag the download URL names.
DIR_VERSION="${ZLIB_VERSION//./}"
URL="https://github.com/madler/zlib/releases/download/v$ZLIB_VERSION/zlib$DIR_VERSION.zip"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "downloading $URL"
curl -fsSL -o "$WORK/zlib.zip" "$URL"

actual="$(sha256sum "$WORK/zlib.zip" | cut -d' ' -f1)"
if [ "$actual" != "$ZLIB_ZIP_SHA256" ]; then
  echo "error: checksum mismatch for zlib$DIR_VERSION.zip" >&2
  echo "  expected $ZLIB_ZIP_SHA256" >&2
  echo "  actual   $actual" >&2
  exit 1
fi

rm -rf "$DEST"
mkdir -p "$DEST"
unzip -q "$WORK/zlib.zip" -d "$WORK/extracted"
mv "$WORK/extracted/zlib-$ZLIB_VERSION"/* "$DEST"/

echo "$ZLIB_VERSION" > "$STAMP"
echo "unpacked $DEST ($ZLIB_VERSION)"
