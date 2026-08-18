#!/bin/sh
# Applies the patches in patches/ to the vendored C++ core under src/core/.
#
# Re-importing the core from upstream drops these patches without a word, so
# run this after every re-vendor. Both modes are idempotent: a patch that is
# already applied is reported and skipped rather than failing the run.
#
#   scripts/apply_core_patches.sh          apply what is missing
#   scripts/apply_core_patches.sh --check  report only, change nothing
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

check_only=0
if [ $# -gt 0 ]; then
	case "$1" in
		--check) check_only=1 ;;
		*) echo "usage: $0 [--check]" >&2; exit 2 ;;
	esac
fi

if [ ! -d patches ]; then
	echo "no patches/ directory - nothing to do"
	exit 0
fi

found=0
missing=0
failed=0

for patch in patches/*.patch; do
	[ -e "$patch" ] || continue
	found=$((found + 1))
	name=$(basename "$patch")

	if git apply --reverse --check "$patch" 2>/dev/null; then
		echo "applied   $name"
		continue
	fi

	if ! git apply --check "$patch" 2>/dev/null; then
		echo "CONFLICT  $name (applies neither forwards nor backwards)" >&2
		failed=$((failed + 1))
		continue
	fi

	if [ "$check_only" -eq 1 ]; then
		echo "missing   $name"
		missing=$((missing + 1))
		continue
	fi

	git apply "$patch"
	echo "applying  $name"
done

if [ "$found" -eq 0 ]; then
	echo "no patches found in patches/"
	exit 0
fi

if [ "$failed" -gt 0 ]; then
	echo "----"
	echo "$failed patch(es) do not fit the current core - resolve by hand," >&2
	echo "then regenerate them with: git diff -- src/core > patches/<name>.patch" >&2
	exit 1
fi

if [ "$check_only" -eq 1 ] && [ "$missing" -gt 0 ]; then
	echo "----"
	echo "$missing patch(es) not applied - run $0 without --check" >&2
	exit 1
fi

echo "----"
echo "core patches up to date ($found)"
