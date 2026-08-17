#!/bin/bash
# Regenerates assets/BubiX1turboZ.icns from assets/BubiX1turboZ.png.
#
# Not part of the build: the .icns is committed, so a build (and CI) needs
# neither Swift nor this script. Run it only when the artwork changes.
#
# Usage: ./scripts/make_icon.sh

set -eu
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ICONSET="$WORK/BubiX1turboZ.iconset"
mkdir -p "$ICONSET"

swift scripts/make_icon.swift assets/BubiX1turboZ.png "$ICONSET"
mkdir -p assets
iconutil --convert icns --output assets/BubiX1turboZ.icns "$ICONSET"

echo "wrote assets/BubiX1turboZ.icns"
