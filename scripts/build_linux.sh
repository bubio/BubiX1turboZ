#!/bin/bash
# Release build for Linux: static core -> Nim application -> AppImage and .deb.
#
# This is the script CI runs (.github/workflows/build-linux.yml) and the one
# to use when producing something a user installs. For day-to-day work on the
# app, scripts/build_app_linux_dev.sh is faster and needs no packaging.
#
# Usage: ./scripts/build_linux.sh [--appimage] [--deb] [--skip-core]
#   --appimage   produce build/bubix1turboz-<version>-linux-<arch>.AppImage
#   --deb        produce build/bubix1turboz-<version>-linux-<arch>.deb
#   --skip-core  reuse an existing build/libbubix1core.a
# With neither --appimage nor --deb, both are built.
#
# The AppImage bundles SDL2 and finds the system's GTK3, which every Linux
# desktop carries; the .deb depends on both. GTK is not bundled - a full GTK
# stack in an AppImage brings its themes and loaders with it and is a project
# of its own (see DevelopmentPlan / the plan notes).

set -eu
cd "$(dirname "$0")/.."

WANT_APPIMAGE=0
WANT_DEB=0
SKIP_CORE=0
for arg in "$@"; do
  case "$arg" in
    --appimage)  WANT_APPIMAGE=1 ;;
    --deb)       WANT_DEB=1 ;;
    --skip-core) SKIP_CORE=1 ;;
    *) echo "error: unknown option $arg" >&2; exit 1 ;;
  esac
done
if [ "$WANT_APPIMAGE" -eq 0 ] && [ "$WANT_DEB" -eq 0 ]; then
  WANT_APPIMAGE=1; WANT_DEB=1
fi

APP_NAME=BubiX1turboZ
PKG=bubix1turboz
ICON_SRC=assets/AppIcon.icon/Assets/BubiX1turboZ.png
DESKTOP_SRC=assets/linux/$PKG.desktop
ICON_SIZES="16 32 48 64 128 256 512"

# .nimble is the single source of truth for the version (see its comment).
VERSION="$(grep '^version' ./*.nimble | sed -E 's/.*"(.*)".*/\1/')"

case "$(uname -m)" in
  x86_64)          ARCH=amd64; AI_ARCH=x86_64 ;;
  aarch64|arm64)   ARCH=arm64; AI_ARCH=aarch64 ;;
  *) echo "error: unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac

BIN=build/$APP_NAME
if [ "$SKIP_CORE" -eq 0 ]; then
  ./scripts/build_core.sh
fi
# $ORIGIN/../lib: the binary lands in usr/bin and the bundled SDL2 in usr/lib
# (AppImage). On a .deb the system SDL2 is found by the loader as usual, so
# the same binary serves both.
./scripts/build_nim_app.sh "$BIN" '$ORIGIN/../lib'

install_icons() {
  # $1 = tree root under which usr/share/icons/hicolor/... is created.
  local root="$1" s
  for s in $ICON_SIZES; do
    install -d "$root/usr/share/icons/hicolor/${s}x${s}/apps"
    convert "$ICON_SRC" -resize "${s}x${s}" \
      "$root/usr/share/icons/hicolor/${s}x${s}/apps/$PKG.png"
  done
}

install_common() {
  # The parts a .deb and an AppImage lay out the same way.
  local root="$1"
  install -Dm755 "$BIN" "$root/usr/bin/$APP_NAME"
  install -Dm644 "$DESKTOP_SRC" "$root/usr/share/applications/$PKG.desktop"
  install_icons "$root"
}

build_appimage() {
  local appdir=build/AppDir
  rm -rf "$appdir"
  install_common "$appdir"

  # Bundle SDL2 (the one the binary actually resolved to) beside the binary's
  # rpath. GTK and X11 come from the host.
  install -d "$appdir/usr/lib"
  local sdl
  sdl="$(ldd "$BIN" | awk '/libSDL2/{print $3}')"
  if [ -n "$sdl" ] && [ -f "$sdl" ]; then
    cp -L "$sdl" "$appdir/usr/lib/"
  fi

  cat > "$appdir/AppRun" <<'APPRUN'
#!/bin/bash
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/usr/lib:${LD_LIBRARY_PATH:-}"
exec "$HERE/usr/bin/BubiX1turboZ" "$@"
APPRUN
  chmod +x "$appdir/AppRun"

  # appimagetool reads the .desktop and icon at the AppDir root.
  cp "$DESKTOP_SRC" "$appdir/$PKG.desktop"
  cp "$appdir/usr/share/icons/hicolor/256x256/apps/$PKG.png" "$appdir/$PKG.png"
  cp "$appdir/$PKG.png" "$appdir/.DirIcon"

  # appimagetool is itself an AppImage; fetch the pinned-to-continuous build
  # once and run it without FUSE so it works on a CI runner.
  local tool="build/tools/appimagetool-$AI_ARCH.AppImage"
  if [ ! -x "$tool" ]; then
    install -d build/tools
    curl -fsSL -o "$tool" \
      "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$AI_ARCH.AppImage"
    chmod +x "$tool"
  fi

  local out="build/$PKG-$VERSION-linux-$ARCH.AppImage"
  rm -f "$out"
  ARCH="$AI_ARCH" "$tool" --appimage-extract-and-run "$appdir" "$out"
  echo "built $out"
}

build_deb() {
  local debroot=build/deb/$PKG
  rm -rf "$debroot"
  install_common "$debroot"

  install -Dm644 LICENSE "$debroot/usr/share/doc/$PKG/copyright" 2>/dev/null || true

  install -d "$debroot/DEBIAN"
  # GTK drags in gdk/pango/cairo/glib and SDL2 its own X11 stack, so the two
  # top-level runtime libraries are enough to name.
  cat > "$debroot/DEBIAN/control" <<CONTROL
Package: $PKG
Version: $VERSION
Section: games
Priority: optional
Architecture: $ARCH
Depends: libc6, libstdc++6, libgtk-3-0, libsdl2-2.0-0, libarchive-tools | p7zip-full
Maintainer: bubio
Description: Sharp X1 turbo Z emulator
 A multi-platform emulator of the Sharp X1 turbo Z, using the Common Source
 Code Project core with a native GTK front end.
CONTROL

  local out="build/$PKG-$VERSION-linux-$ARCH.deb"
  rm -f "$out"
  dpkg-deb --root-owner-group --build "$debroot" "$out"
  echo "built $out"
}

if [ "$WANT_APPIMAGE" -eq 1 ]; then build_appimage; fi
if [ "$WANT_DEB" -eq 1 ]; then build_deb; fi
