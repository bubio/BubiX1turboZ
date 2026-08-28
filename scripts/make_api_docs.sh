#!/bin/bash
# Regenerates the committed API documentation in docs/api from the Nim
# sources.
#
# The catch is that bubix1/ui picks its backend with `when defined(...)`,
# so a single `nim doc` run only ever documents the host's own backend and
# the other two directories are simply absent from the output. `nim doc`
# accepts --os the same way `nim check` does (see check_other_platforms.sh),
# and needs no C compiler, SDL or GTK to do it, so this script runs it once
# per supported platform and merges the three results.
#
# Only two things actually differ between those results: the
# bubix1/ui/<platform>/ pages themselves, and the "Imports" link on each
# facade page, which points at whichever backend that run selected.
# Everything else is byte-identical, so the macOS run - the first-priority
# platform, and the one whose Imports links the merged tree therefore keeps
# - serves as the base and the other two contribute their backend
# directories alone.
#
# The per-module .idx files are kept until the merge is done so that
# `nim buildIndex` can build one theindex.html covering all three
# platforms, then dropped: they are a build artifact of no use to a reader
# and are not committed.
#
# Usage: ./scripts/make_api_docs.sh

set -eu
cd "$(dirname "$0")/.."

OUT=docs/api
WORK=build/api-docs

# The version is normally read from .nimble by build_nim_app.sh; the value
# does not reach the documentation, but bubix1turboz.nim will not compile
# without it being defined.
APP_VERSION="$(grep '^version' ./*.nimble | sed -E 's/.*"(.*)".*/\1/')"

# macosx first: it is the base tree the other two are merged into.
PLATFORMS=(macosx linux windows)

rm -rf "$WORK"
mkdir -p "$WORK"

for os in "${PLATFORMS[@]}"; do
  echo "generating --os:$os"
  mise exec -- nim doc --project --index:on --os:"$os" --hints:off \
    --outdir:"$WORK/$os" \
    -d:appVersion="$APP_VERSION" \
    src/nim/bubix1turboz.nim
done

# The backend directory each run names after its own platform. macosx
# additionally produces ui/stub, the fallback backend it selects itself,
# which comes along with the base tree.
echo "merging"
cp -R "$WORK/macosx" "$WORK/merged"
for os in linux windows; do
  cp -R "$WORK/$os/bubix1/ui/$os" "$WORK/merged/bubix1/ui/"
done

# Rebuild the index over the merged tree so it lists the symbols of all
# three backends, not just the base run's.
rm -f "$WORK/merged/theindex.html"
mise exec -- nim buildIndex --hints:off \
  -o:"$WORK/merged/theindex.html" "$WORK/merged"

find "$WORK/merged" -name '*.idx' -delete

rm -rf "$OUT"
mkdir -p "$(dirname "$OUT")"
mv "$WORK/merged" "$OUT"
rm -rf "$WORK"

echo "wrote $OUT"
