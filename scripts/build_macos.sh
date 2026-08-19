#!/bin/bash
# Release build for macOS: static core -> Nim application -> .app bundle,
# and optionally a .dmg.
#
# This is the script CI runs (.github/workflows/build-macos.yml) and the one
# to use when producing something a user will install. For day-to-day work
# on the app itself, scripts/build_app_macos_dev.sh is faster and needs no
# bundle.
#
# Usage: ./scripts/build_macos.sh [--dmg] [--skip-core]
#   --dmg        also produce build/bubix1turboz-<version>-macos-arm64.dmg
#   --skip-core  reuse an existing build/libbubix1core.a
#
# Result: build/BubiX1turboZ.app

set -eu
cd "$(dirname "$0")/.."

MAKE_DMG=0
SKIP_CORE=0
for arg in "$@"; do
  case "$arg" in
    --dmg)       MAKE_DMG=1 ;;
    --skip-core) SKIP_CORE=1 ;;
    *) echo "error: unknown option $arg" >&2; exit 1 ;;
  esac
done

APP_NAME=BubiX1turboZ
BUNDLE_ID=io.github.bubio.BubiX1turboZ
# Matches MACOSX_DEPLOYMENT_TARGET in build_core.sh / build_nim_app.sh. The
# bundled SDL2 framework is built for 10.11 (x86_64) / 11.0 (arm64), so this
# floor is set by this project's own code, not by its dependencies.
MIN_MACOS=13.5

# .nimble is the single source of truth for the version (see its comment).
VERSION="$(grep '^version' ./*.nimble | sed -E 's/.*"(.*)".*/\1/')"
# A separate 1-based build sequence, per CLAUDE.md. Kept at 1 deliberately:
# deriving it from a CI run number would make local and CI builds disagree
# about a value macOS requires to be monotonic per version.
BUILD_NUMBER=1

APP="build/$APP_NAME.app"
CONTENTS="$APP/Contents"

./scripts/fetch_sdl2_framework.sh
if [ "$SKIP_CORE" -eq 0 ]; then
  ./scripts/build_core.sh
fi

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks"

# @executable_path/../Frameworks: the binary must find SDL2 inside the
# bundle wherever the user drags it, so no absolute path may survive here.
./scripts/build_nim_app.sh "$CONTENTS/MacOS/$APP_NAME" '@executable_path/../Frameworks'

ditto build/frameworks/SDL2.framework "$CONTENTS/Frameworks/SDL2.framework"
# The icon and the accent colour both live in the compiled asset catalog,
# which scripts/make_icon.sh produces and the repository carries, so no part
# of a build needs Xcode. macOS 26 draws the icon from Assets.car - given
# only the .icns it wraps the artwork in a light tile of its own, which is
# the padding a legacy icon shows at small sizes in the Finder - while
# earlier releases take the .icns. Both are copied; Info.plist names both.
cp assets/Assets.car "$CONTENTS/Resources/Assets.car"
cp assets/AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"

# The app's own strings come from its Nim catalog (src/nim/bubix1/i18n.nim),
# but the words AppKit supplies - the Open/Save panel buttons, the standard
# window and edit menus, "Are you sure you want to..." - are drawn in the
# first language the *bundle* claims to have. A CFBundleLocalizations entry
# alone is not enough: AppKit looks for the matching .lproj resource
# directory, and a bundle without one stays English however its plist reads.
# The directories carry only an empty InfoPlist.strings, which is all it
# takes for the localization to count as present (nothing in Info.plist
# needs translating - the app's name is the same in both languages).
for LANG_CODE in en ja; do
  mkdir -p "$CONTENTS/Resources/$LANG_CODE.lproj"
  cat > "$CONTENTS/Resources/$LANG_CODE.lproj/InfoPlist.strings" <<'STRINGS'
/* No Info.plist key needs translating; this file marks the localization
   as present so AppKit uses its own strings in this language. */
STRINGS
done

# CFBundleDocumentTypes is deliberately absent - a decision now, not a gap.
# It could work: opening a document from the Finder arrives as an Apple
# Event handled by the application delegate, and SDLAppDelegate does
# implement application:openFile: (confirmed with otool -oV on the bundled
# SDL2), so the types would turn into the SDL_DROPFILE this app listens
# for. It is left out because an emulator has no business claiming .d88 and
# the rest from whatever the user already opens them with; dragging a file
# onto the running window is the way in, and it is enough.
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleLocalizations</key>
	<array>
		<string>en</string>
		<string>ja</string>
	</array>
	<key>CFBundleExecutable</key>
	<string>$APP_NAME</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIconName</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$APP_NAME</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>$BUILD_NUMBER</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.games</string>
	<key>LSMinimumSystemVersion</key>
	<string>$MIN_MACOS</string>
	<key>NSAccentColorName</key>
	<string>AccentColor</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>GNU General Public License v2 or later</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc signing, not Developer ID: this project has no signing identity, so
# the dmg is unsigned and unnotarized and users must clear the quarantine
# flag on first launch (README.md documents how). The ad-hoc signature is
# still required - on Apple silicon an unsigned or stale-signed binary is
# killed by the kernel before main() - and nested code must be signed before
# the bundle that seals over it.
codesign --force --sign - --timestamp=none \
  "$CONTENTS/Frameworks/SDL2.framework/Versions/A"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"

echo "built $APP"

if [ "$MAKE_DMG" -eq 1 ]; then
  DMG="build/bubix1turboz-$VERSION-macos-arm64.dmg"
  STAGE="$(mktemp -d)"
  trap 'rm -rf "$STAGE"' EXIT
  ditto "$APP" "$STAGE/$APP_NAME.app"
  # The customary drop target, so the window is a complete install gesture
  # even without a styled background.
  ln -s /Applications "$STAGE/Applications"
  rm -f "$DMG"
  hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" \
    -ov -format UDZO -quiet "$DMG"
  echo "built $DMG"
fi
