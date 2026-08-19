#!/bin/bash
# Compiles the app's asset catalog - the icon and the accent colour - into
# assets/Assets.car and assets/AppIcon.icns.
#
# Both outputs are committed, so a build (and CI) needs no Xcode. Run this
# only when the artwork in assets/AppIcon.icon or the accent colour in
# assets/Assets.xcassets changes.
#
# assets/AppIcon.icon is an Icon Composer document: full-bleed artwork plus
# the fill that shows through the corners, with the rounded-square mask,
# shading and shadow left to the system. That is what macOS 26 wants. An app
# that ships only a legacy .icns is drawn shrunk inside a light tile the
# system supplies, which is the padding it looks like at small sizes in the
# Finder; the compiled catalog is the only way out of it.
#
# The .icns actool emits alongside the catalog is Apple's own rendering of
# the same document for macOS releases before 26, where the icon is a
# picture rather than a masked layer.
#
# Usage: ./scripts/make_icon.sh

set -eu
# Absolute, because actool resolves relative paths against its own working
# directory rather than this script's.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! xcrun --find actool >/dev/null 2>&1; then
  echo "error: actool not found - this script needs Xcode, not just the" \
       "Command Line Tools" >&2
  exit 1
fi

# Matches LSMinimumSystemVersion in build_macos.sh.
MIN_MACOS=13.5

# actool insists on writing the partial plist it would hand to an Xcode
# build. The keys in it are the ones build_macos.sh writes by hand, so it
# goes somewhere disposable.
PARTIAL_PLIST="$(mktemp -t bubix1-actool)"
trap 'rm -f "$PARTIAL_PLIST"' EXIT

xcrun actool "$ROOT/assets/Assets.xcassets" "$ROOT/assets/AppIcon.icon" \
  --compile "$ROOT/assets" \
  --platform macosx \
  --minimum-deployment-target "$MIN_MACOS" \
  --app-icon AppIcon \
  --accent-color AccentColor \
  --output-partial-info-plist "$PARTIAL_PLIST" \
  > /dev/null

echo "wrote assets/Assets.car and assets/AppIcon.icns"
