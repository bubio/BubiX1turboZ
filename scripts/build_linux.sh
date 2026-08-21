#!/bin/bash
# Release build for Linux: static core -> Nim application -> AppImage, .deb
# and .rpm.
#
# This is the script CI runs (.github/workflows/build-linux.yml) and the one
# to use when producing something a user installs. For day-to-day work on the
# app, scripts/build_app_linux_dev.sh is faster and needs no packaging.
#
# Usage: ./scripts/build_linux.sh [--appimage] [--deb] [--rpm] [--skip-core]
#   --appimage   produce build/bubix1turboz-<version>-linux-<arch>.AppImage
#   --deb        produce build/bubix1turboz-<version>-linux-<arch>.deb
#   --rpm        produce build/bubix1turboz-<version>-linux-<arch>.rpm
#   --skip-core  reuse an existing build/libbubix1core.a
# With none of --appimage / --deb / --rpm, all three are built.
#
# The .deb and the .rpm are built from the same staged tree, so the two
# packages always install the same set of files; only the metadata and the
# way each states its dependencies differ.
#
# The AppImage bundles SDL2 and finds the system's GTK3, which every Linux
# desktop carries; the .deb and .rpm depend on both. GTK is not bundled - a full GTK
# stack in an AppImage brings its themes and loaders with it and is a project
# of its own (see DevelopmentPlan / the plan notes).

set -eu
cd "$(dirname "$0")/.."

WANT_APPIMAGE=0
WANT_DEB=0
WANT_RPM=0
SKIP_CORE=0
for arg in "$@"; do
  case "$arg" in
    --appimage)  WANT_APPIMAGE=1 ;;
    --deb)       WANT_DEB=1 ;;
    --rpm)       WANT_RPM=1 ;;
    --skip-core) SKIP_CORE=1 ;;
    *) echo "error: unknown option $arg" >&2; exit 1 ;;
  esac
done
if [ "$WANT_APPIMAGE" -eq 0 ] && [ "$WANT_DEB" -eq 0 ] && [ "$WANT_RPM" -eq 0 ]; then
  WANT_APPIMAGE=1; WANT_DEB=1; WANT_RPM=1
fi

APP_NAME=BubiX1turboZ
PKG=bubix1turboz
ICON_SRC=assets/AppIcon.icon/Assets/BubiX1turboZ.png
DESKTOP_SRC=assets/linux/$PKG.desktop
ICON_SIZES="16 32 48 64 128 256 512"

# .nimble is the single source of truth for the version (see its comment).
VERSION="$(grep '^version' ./*.nimble | sed -E 's/.*"(.*)".*/\1/')"

# ARCH names the artifact (Debian's spelling, used for every file name so the
# three packages agree); AI_ARCH and RPM_ARCH are what appimagetool and rpm
# call the same thing.
case "$(uname -m)" in
  x86_64)          ARCH=amd64; AI_ARCH=x86_64;  RPM_ARCH=x86_64 ;;
  aarch64|arm64)   ARCH=arm64; AI_ARCH=aarch64; RPM_ARCH=aarch64 ;;
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
  # The parts every package lays out the same way.
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

build_rpm() {
  # rpmbuild is asked to package a tree that is already laid out, rather than
  # to build anything: %install copies the staged root in wholesale, so the
  # .rpm carries the same files as the .deb.
  local top rpmroot
  top="$PWD/build/rpm"
  rpmroot=$top/root
  rm -rf "$top"
  install_common "$rpmroot"
  install -Dm644 LICENSE "$rpmroot/usr/share/licenses/$PKG/LICENSE"
  install -d "$top/SPECS" "$top/RPMS" "$top/BUILD"

  # debug_package: there are no sources to attach a debuginfo package to.
  # _build_id_links: the binary is not rebuilt here, so leave its build-id
  # alone instead of having rpm rewrite /usr/lib/.build-id symlinks.
  cat > "$top/SPECS/$PKG.spec" <<SPEC
%global debug_package %{nil}
%global __brp_mangle_shebangs %{nil}
%define _build_id_links none

Name:           $PKG
Version:        $VERSION
Release:        1
Summary:        Sharp X1 turbo Z emulator
License:        GPL-2.0-or-later
URL:            https://github.com/bubio/BubiX1turboZ
BuildArch:      $RPM_ARCH

# No Requires for GTK or SDL2: rpm reads them off the binary as soname
# dependencies (libgtk-3.so.0, libSDL2-2.0.so.0), which resolve on every
# distribution. Naming packages instead would tie the .rpm to Fedora's
# spelling and break on openSUSE, where the same libraries are libgtk-3-0
# and libSDL2-2_0-0. Only the archiver has no soname to key off.
Recommends:     bsdtar

%description
A multi-platform emulator of the Sharp X1 turbo Z, using the Common Source
Code Project core with a native GTK front end.

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
cp -a $rpmroot/. %{buildroot}/

%files
/usr/bin/$APP_NAME
/usr/share/applications/$PKG.desktop
/usr/share/icons/hicolor/*/apps/$PKG.png
%license /usr/share/licenses/$PKG/LICENSE

%changelog
SPEC

  rpmbuild -bb --define "_topdir $top" "$top/SPECS/$PKG.spec"

  local out="build/$PKG-$VERSION-linux-$ARCH.rpm"
  rm -f "$out"
  mv "$top/RPMS/$RPM_ARCH/$PKG-$VERSION-1.$RPM_ARCH.rpm" "$out"
  echo "built $out"
}

if [ "$WANT_APPIMAGE" -eq 1 ]; then build_appimage; fi
if [ "$WANT_DEB" -eq 1 ]; then build_deb; fi
if [ "$WANT_RPM" -eq 1 ]; then build_rpm; fi
