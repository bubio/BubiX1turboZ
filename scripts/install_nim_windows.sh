#!/bin/bash
# Installs the Nim compiler on Windows, where mise cannot: the community
# asdf-nim plugin (mise.toml) is a set of bash scripts that mise's Windows
# backend cannot execute directly (confirmed - `mise install` fails with
# "%1 is not a valid Win32 application", os error 193, trying to run
# asdf-nim's bin/list-all as if it were a native executable).
#
# This downloads the official Windows zip from nim-lang.org instead. It does
# not bundle a C compiler (checked: no gcc anywhere under it), so
# scripts/fetch_mingw_windows.sh fetches that separately - see its own
# comment for why a pinned download rather than the asdf plugin there too.
#
# The version is read from mise.toml so local and CI builds stay pinned to
# the one place the rest of this project already treats as the source of
# truth for the Nim version - see mise.toml's own comment on why that file
# holds it rather than the .nimble.
#
# Usage: ./scripts/install_nim_windows.sh
# Result: build/toolchain/nim-windows/{bin,config,lib,...}, and
#         build/toolchain/nim-windows/env.sh exporting NIM_BIN_DIR for other
#         scripts to source (the zip's internal layout has moved between
#         releases before, so this is resolved once here rather than
#         hardcoded at every call site).

set -eu
cd "$(dirname "$0")/.."

NIM_VERSION="$(grep -E '^nim[[:space:]]*=' mise.toml | sed -E 's/.*"(.*)".*/\1/')"
if [ -z "$NIM_VERSION" ]; then
  echo "error: could not read the nim version from mise.toml" >&2
  exit 1
fi

DEST=build/toolchain/nim-windows
STAMP="$DEST/.nim-version"
ENV_FILE="$DEST/env.sh"

write_env_file() {
  local nim_bin
  nim_bin="$(dirname "$(find "$DEST" -maxdepth 4 -iname 'nim.exe' | head -n1)")"
  if [ -z "$nim_bin" ]; then
    echo "error: could not find nim.exe under $DEST" >&2
    echo "  the nim-lang.org Windows zip layout may have changed - see" >&2
    echo "  this script's own comment" >&2
    exit 1
  fi
  echo "NIM_BIN_DIR='$(cd "$nim_bin" && pwd)'" > "$ENV_FILE"
}

if [ -f "$STAMP" ] && [ "$(cat "$STAMP" 2>/dev/null || true)" = "$NIM_VERSION" ] \
    && [ -f "$ENV_FILE" ]; then
  echo "nim $NIM_VERSION already installed in $DEST"
  exit 0
fi

URL="https://nim-lang.org/download/nim-${NIM_VERSION}_x64.zip"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "downloading $URL"
curl -fsSL -o "$WORK/nim.zip" "$URL"

rm -rf "$DEST"
mkdir -p "$DEST"
unzip -q "$WORK/nim.zip" -d "$WORK/extracted"
# The zip wraps everything in a single "nim-<version>" top directory; move
# its contents up so $DEST is that directory's contents directly, matching
# the layout scripts/fetch_sdl2_framework.sh and friends leave behind.
inner="$(find "$WORK/extracted" -maxdepth 1 -mindepth 1 -type d | head -n1)"
if [ -z "$inner" ]; then
  echo "error: unexpected zip layout - no top-level directory in nim.zip" >&2
  exit 1
fi
mv "$inner"/* "$DEST"/

write_env_file
echo "$NIM_VERSION" > "$STAMP"
echo "installed nim $NIM_VERSION to $DEST"
. "$ENV_FILE"
echo "  nim: $NIM_BIN_DIR"
