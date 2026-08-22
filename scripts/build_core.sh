#!/bin/bash
# Builds the vendored C++ core into a static library, for whichever host
# this runs on (macOS: arm64 / Apple clang; Linux: native g++).
#
# Compiles the translation units listed in the original
# vc++2017/x1turboz.vcxproj (minus src/win32/*), the new src/core/sdl/*.cpp
# OSD implementation, and the src/bridge/*.cpp C ABI facade, into
# build/libbubix1core.a. This is the one library the dev build scripts
# (build_app_macos_dev.sh / build_app_linux_dev.sh) link the app against.
#
# The core is host independent: src/core/sdl/osd.h deliberately includes no
# SDL headers (the C++/Nim boundary is a pure data boundary), so no SDL
# include path is needed here on any platform.
#
# Usage: ./scripts/build_core.sh [group]
#   group = vm | app | osd | bridge | all (default: all)

set -u
cd "$(dirname "$0")/.."

SRC=src/core
OBJ=build/core-obj
LOG=build/core-compile.log
LIB=build/libbubix1core.a

ZLIB_SRCS=()
case "$(uname -s)" in
  Darwin)
    # Matches LSMinimumSystemVersion in the .app's Info.plist. Without it
    # clang stamps the objects with the SDK's own (current) minimum, which
    # would make the released app refuse to launch on every macOS older
    # than the machine that built it.
    export MACOSX_DEPLOYMENT_TARGET=13.5
    CXX=clang++
    ARCHFLAGS=(-arch arm64)
    # Clang's spelling of "string literal assigned to char*", and a warning
    # only Clang knows for the Shift-JIS bytes in some comments.
    PLATFORM_WARNINGS=(-Wno-writable-strings -Wno-invalid-source-encoding)
    ;;
  MINGW*|MSYS*)
    # Windows, via the MinGW-w64 GCC scripts/fetch_mingw_windows.sh pins -
    # not the system g++ (there is not normally one), and not one found on
    # PATH, so the same compiler is used whether this runs on a developer's
    # machine or a CI runner that happens to carry an unrelated GCC.
    if [ ! -f build/toolchain/mingw-windows/env.sh ]; then
      ./scripts/fetch_mingw_windows.sh
    fi
    . build/toolchain/mingw-windows/env.sh
    CXX="$MINGW_BIN_DIR/g++.exe"
    CC="$MINGW_BIN_DIR/gcc.exe"
    AR="$MINGW_BIN_DIR/ar.exe"
    ARCHFLAGS=()
    PLATFORM_WARNINGS=(-Wno-write-strings)
    # Windows has no system zlib (see bubix1/deflate.nim's own comment);
    # its objects are compiled into libbubix1core.a here instead, so the
    # Nim side never needs a system -lz on this platform.
    if [ ! -f build/toolchain/zlib-windows/.zlib-version ]; then
      ./scripts/fetch_zlib_windows.sh
    fi
    ZLIB_SRCS=(adler32.c compress.c crc32.c deflate.c gzclose.c gzlib.c
      gzread.c gzwrite.c infback.c inffast.c inflate.c inftrees.c trees.c
      uncompr.c zutil.c)
    ;;
  *)
    # Linux (and any other Unix): the native g++, no architecture flag, and
    # GCC's own spelling of the writable-string warning. GCC accepts the
    # Shift-JIS comment bytes without a flag, so -Wno-invalid-source-encoding
    # (a Clang-only option) is omitted rather than passed and ignored.
    CXX="${CXX:-g++}"
    ARCHFLAGS=()
    PLATFORM_WARNINGS=(-Wno-write-strings)
    ;;
esac

CXXFLAGS=(
  -std=c++17 "${ARCHFLAGS[@]}" -c
  -D_X1TURBOZ -D_USE_SDL
  -I"$SRC"
  -Wno-register            # 'register' storage class removed in C++17 (fmgen)
  "${PLATFORM_WARNINGS[@]}"
  -fno-strict-aliasing
)

# Translation units from x1turboz.vcxproj, minus src/win32/*.
VM_SRCS=(
  vm/ay_3_891x.cpp vm/datarec.cpp vm/disk.cpp vm/event.cpp
  vm/fmgen/fmgen.cpp vm/fmgen/fmtimer.cpp vm/fmgen/opm.cpp
  vm/fmgen/opna.cpp vm/fmgen/psg.cpp
  vm/harddisk.cpp vm/hd46505.cpp vm/i8255.cpp vm/io.cpp vm/mb8877.cpp
  vm/mcs48.cpp vm/midi.cpp vm/mz1p17.cpp vm/noise.cpp vm/pcm8bit.cpp
  vm/prnfile.cpp vm/scsi_dev.cpp vm/scsi_hdd.cpp vm/scsi_host.cpp
  vm/upd1990a.cpp
  vm/x1/cz8rb.cpp vm/x1/display.cpp vm/x1/emm.cpp vm/x1/floppy.cpp
  vm/x1/iobus.cpp vm/x1/joystick.cpp vm/x1/keyboard.cpp vm/x1/memory.cpp
  vm/x1/mouse.cpp vm/x1/psub.cpp vm/x1/sasi.cpp vm/x1/sub.cpp vm/x1/x1.cpp
  vm/ym2151.cpp vm/z80.cpp vm/z80ctc.cpp vm/z80dma.cpp vm/z80sio.cpp
)
APP_SRCS=(
  common.cpp config.cpp fifo.cpp fileio.cpp emu.cpp debugger.cpp
)
OSD_SRCS=(
  sdl/osd.cpp sdl/osd_screen.cpp sdl/osd_sound.cpp sdl/osd_input.cpp
  sdl/osd_bitmap.cpp sdl/osd_console.cpp sdl/osd_midi.cpp
)
# Relative to repo root, not $SRC: the bridge lives at src/bridge, not
# under src/core. Its own quoted #includes ("../core/emu.h",
# "bubix1_api.h") resolve directory-relative regardless of -I.
BRIDGE_SRCS=(
  src/bridge/bubix1_api.cpp
)

case "${1:-all}" in
  vm)     SRCS=("${VM_SRCS[@]}") ;;
  app)    SRCS=("${APP_SRCS[@]}") ;;
  osd)    SRCS=("${OSD_SRCS[@]}") ;;
  bridge) SRCS=() ;;
  *)      SRCS=("${VM_SRCS[@]}" "${APP_SRCS[@]}" "${OSD_SRCS[@]}") ;;
esac

rm -rf "$OBJ"; mkdir -p "$OBJ"
: > "$LOG"

pass=0; fail=0; failed=()
# ${SRCS[@]+...}: the bridge group leaves SRCS empty, which `set -u` treats
# as unbound for an empty array.
for s in ${SRCS[@]+"${SRCS[@]}"}; do
  o="$OBJ/${s//\//_}.o"
  if "$CXX" "${CXXFLAGS[@]}" "$SRC/$s" -o "$o" >>"$LOG" 2>&1; then
    printf 'ok   %s\n' "$s"
    pass=$((pass+1))
  else
    printf 'FAIL %s\n' "$s"
    fail=$((fail+1)); failed+=("$s")
  fi
done
if [ "${1:-all}" = "bridge" ] || [ "${1:-all}" = "all" ]; then
  for s in "${BRIDGE_SRCS[@]}"; do
    o="$OBJ/${s//\//_}.o"
    if "$CXX" "${CXXFLAGS[@]}" "$s" -o "$o" >>"$LOG" 2>&1; then
      printf 'ok   %s\n' "$s"
      pass=$((pass+1))
    else
      printf 'FAIL %s\n' "$s"
      fail=$((fail+1)); failed+=("$s")
    fi
  done
fi

if [ "${1:-all}" = "all" ] && [ ${#ZLIB_SRCS[@]} -gt 0 ]; then
  # Plain C, compiled with the matching gcc rather than g++: zlib is C, and
  # not every construct it uses is accepted under g++'s stricter C++ rules.
  ZLIB_SRC=build/toolchain/zlib-windows
  ZLIB_CFLAGS=(-c -I"$ZLIB_SRC")
  for s in "${ZLIB_SRCS[@]}"; do
    o="$OBJ/zlib_${s//\//_}.o"
    if "$CC" "${ZLIB_CFLAGS[@]}" "$ZLIB_SRC/$s" -o "$o" >>"$LOG" 2>&1; then
      printf 'ok   zlib/%s\n' "$s"
      pass=$((pass+1))
    else
      printf 'FAIL zlib/%s\n' "$s"
      fail=$((fail+1)); failed+=("zlib/$s")
    fi
  done
fi

echo "----"
echo "pass=$pass fail=$fail  objects=$(ls "$OBJ" | wc -l | tr -d ' ')"
if [ $fail -gt 0 ]; then
  printf 'failed: %s\n' "${failed[*]}"
  echo "see $LOG"
  exit 1
fi

if [ "${1:-all}" = "all" ]; then
  rm -f "$LIB"
  "${AR:-ar}" rcs "$LIB" "$OBJ"/*.o
  echo "archived $LIB"

  # Real link test (against an empty main) is the actual completion
  # condition: it is the only reliable way to see whether every OSD::*
  # symbol emu.cpp/vm/** need is now defined, vs. grepping `nm -u` output
  # which also lists resolvable libc/libc++ symbols per-object.
  LINK_TEST_SRC=$(mktemp /tmp/bubix1_link_test.XXXXXX.cpp)
  LINK_TEST_BIN=$(mktemp /tmp/bubix1_link_test.XXXXXX)
  echo 'int main() { return 0; }' > "$LINK_TEST_SRC"
  if "$CXX" -std=c++17 "${ARCHFLAGS[@]}" "$LINK_TEST_SRC" "$LIB" -o "$LINK_TEST_BIN" 2>"$LOG.link"; then
    echo "link test passed: no undefined symbols"
    rm -f "$LINK_TEST_SRC" "$LINK_TEST_BIN" "$LOG.link"
  else
    echo "link test FAILED (undefined symbols remain):"
    cat "$LOG.link"
    rm -f "$LINK_TEST_SRC" "$LINK_TEST_BIN"
    exit 1
  fi
fi
