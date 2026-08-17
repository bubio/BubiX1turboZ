#!/bin/bash
# Checks the Nim sources for the platforms this machine cannot build.
#
# Nim never compiles the unselected branch of a `when`, so the Linux and
# Windows sides of src/nim/bubix1/ui can go stale without any macOS build
# noticing. `nim check` runs the semantic pass alone - no C compiler, no
# SDL, no linking - which is enough to catch a backend that has drifted
# out of step with its facade.
#
# It also enforces the rule bubix1/ui/README.md states: outside that
# directory nothing in src/nim may name a platform or reach for a host
# library. Two files are excepted, and both are named in that README:
#
#   paths.nim    needs no backend, only the right branch
#   deflate.nim  links zlib with -lz, which is not a platform name but is
#                a real gap - Windows has no system zlib, so that flag has
#                to be revisited when Windows is built
#
# Usage: ./scripts/check_other_platforms.sh

set -eu
cd "$(dirname "$0")/.."

status=0

# The version is normally read from .nimble by build_nim_app.sh; any value
# will do here, since nothing checked depends on what it says.
APP_VERSION="$(grep '^version' ./*.nimble | sed -E 's/.*"(.*)".*/\1/')"

for os in linux windows; do
  echo "checking --os:$os"
  if ! mise exec -- nim check --os:"$os" --hints:off --path:src \
      -d:appVersion="$APP_VERSION" src/nim/bubix1turboz.nim; then
    status=1
  fi
done

echo "checking that no platform is named outside bubix1/ui"
leaked="$(grep -rnE --include='*.nim' \
  -e 'defined\((macosx|osx|windows|linux|posix|bsd|unix)\)' \
  -e '\{\.[[:space:]]*(compile|passC|passL)[[:space:]]*:' \
  -e 'dynlib[[:space:]]*:' \
  src/nim \
  | grep -v '^src/nim/bubix1/ui/' \
  | grep -v '^src/nim/bubix1/paths\.nim:' \
  | grep -v '^src/nim/bubix1/deflate\.nim:' || true)"
if [ -n "$leaked" ]; then
  echo "error: host-dependent code outside src/nim/bubix1/ui:" >&2
  echo "$leaked" >&2
  status=1
fi

if [ "$status" -eq 0 ]; then
  echo "ok"
fi
exit "$status"
