#!/bin/bash
# Builds and runs the headless tests under tests/.
#
# They link the same build/libbubix1core.a the application does, but not
# SDL: the core is host independent (see build_core.sh), so a test can
# drive a whole machine - reset it, type at it, run frames - with no
# window, no audio device, and no BIOS ROMs. Nothing here needs a display
# or a ROM, so this could run unattended anywhere - but nothing under
# .github/ calls it: running it is a step someone takes, deliberately.
#
# Usage: ./scripts/run_tests.sh [name ...]
#   name  run only tests/t<name>.nim (default: every tests/t*.nim)

set -eu
cd "$(dirname "$0")/.."

LIB=build/libbubix1core.a
if [ ! -f "$LIB" ]; then
  echo "error: $LIB not found - run ./scripts/build_core.sh first" >&2
  exit 1
fi

OUT=build/tests
mkdir -p "$OUT"

EXE_SUFFIX=
NIM_CMD=(mise exec -- nim)
case "$(uname -s)" in
  Darwin)
    # Matches the deployment target build_core.sh stamps the library with.
    export MACOSX_DEPLOYMENT_TARGET=13.5
    PASSC="-Isrc/bridge"
    PASSL="$(pwd)/$LIB -lc++"
    ;;
  MINGW*|MSYS*)
    # The same two fetched toolchains build_nim_app.sh uses, for the same
    # reason: the library was compiled by this MinGW-w64 gcc, and nim.exe
    # has to shell out to that one rather than whatever is on PATH. See
    # that script's comments on `pwd -W` and on the static libgcc/libstdc++
    # /libwinpthread link.
    if [ ! -f build/toolchain/nim-windows/env.sh ]; then
      ./scripts/install_nim_windows.sh
    fi
    if [ ! -f build/toolchain/mingw-windows/env.sh ]; then
      ./scripts/fetch_mingw_windows.sh
    fi
    . build/toolchain/nim-windows/env.sh
    . build/toolchain/mingw-windows/env.sh
    export PATH="$MINGW_BIN_DIR:$PATH"
    NIM_CMD=("$NIM_BIN_DIR/nim.exe")
    WIN_ROOT="$(pwd -W)"
    EXE_SUFFIX=.exe
    PASSC="-I$WIN_ROOT/src/bridge"
    PASSL="$WIN_ROOT/$LIB -Wl,-Bstatic -lstdc++ -lwinpthread -Wl,-Bdynamic"
    ;;
  *)
    PASSC="-Isrc/bridge"
    PASSL="$(pwd)/$LIB -lstdc++ -lm -ldl -lpthread"
    ;;
esac

if [ $# -gt 0 ]; then
  TESTS=()
  for name in "$@"; do
    TESTS+=("tests/t$name.nim")
  done
else
  TESTS=(tests/t*.nim)
fi

pass=0
fail=0
failed=()
for test_src in "${TESTS[@]}"; do
  if [ ! -f "$test_src" ]; then
    echo "error: $test_src not found" >&2
    exit 1
  fi
  name="$(basename "$test_src" .nim)"
  echo "== $name"
  # No -d:release: these are assertions, and a failing one is worth more
  # with its stack trace intact than the seconds an optimized build saves.
  if ! "${NIM_CMD[@]}" c --hints:off \
      --passC:"$PASSC" \
      --passL:"$PASSL" \
      --path:src/nim \
      -o:"$(pwd)/$OUT/$name$EXE_SUFFIX" \
      "$test_src"; then
    fail=$((fail + 1))
    failed+=("$name (build)")
    continue
  fi
  if "./$OUT/$name$EXE_SUFFIX"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    failed+=("$name")
  fi
done

echo "----"
echo "pass=$pass fail=$fail"
if [ $fail -gt 0 ]; then
  printf 'failed: %s\n' "${failed[*]}"
  exit 1
fi
