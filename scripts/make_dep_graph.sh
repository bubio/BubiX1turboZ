#!/bin/bash
# Regenerates the Nim module dependency graphs in docs/Architecture.md and
# its English counterpart docs/Architecture.en.md.
#
# `nim genDepend` writes the module graph as a Graphviz .dot file. Three
# things make a plain invocation insufficient here:
#
#   - bubix1/ui picks its backend with `when defined(...)`, so one run only
#     ever sees the host's own backend (the same reason make_api_docs.sh
#     runs three passes). This script unions the edges of --os:macosx,
#     --os:linux and --os:windows, so all four backends appear at once -
#     only one of which is ever compiled into a given build.
#   - genDepend then shells out to Graphviz's `dot` and exits non-zero when
#     it is absent. The .dot file is already written by that point, so the
#     exit status is tolerated below and the file's existence is checked
#     instead. Nothing here needs Graphviz: the edges are emitted as
#     Mermaid, which GitHub renders on its own.
#   - All 84 edges in one picture is a hairball, so they are split across
#     four diagrams along the seams the architecture already has: what the
#     entry point pulls in, what the modules under it need from each other,
#     which backend each facade selects, and what those backends are built
#     on. See the `scope` handling in the awk program below.
#
# genDepend writes its output next to the source rather than to an --outdir
# of our choosing, so each pass moves the artifacts out of src/ immediately.
#
# Only the region between the BEGIN/END markers in each document is
# rewritten - the rest, including the hand-drawn diagrams of the C++ core,
# is authored by hand and must survive this.
#
# Usage: ./scripts/make_dep_graph.sh

set -eu
cd "$(dirname "$0")/.."

WORK=build/dep-graph
BEGIN_MARK='<!-- BEGIN GENERATED: module-graph -->'
END_MARK='<!-- END GENERATED: module-graph -->'

# Each document and the language its generated headings and subgraph
# titles are written in.
DOCS=(docs/Architecture.md docs/Architecture.en.md)
LANGS=(ja en)

for doc in "${DOCS[@]}"; do
  # -x, not a substring match: the splice below keys on the whole line, so
  # a marker carrying trailing whitespace would pass a substring guard and
  # then match nothing - leaving the document silently unchanged.
  if ! grep -qxF "$BEGIN_MARK" "$doc" || ! grep -qxF "$END_MARK" "$doc"; then
    echo "error: $doc has no generated-region markers - refusing to" \
         "overwrite a file this script cannot merge into" >&2
    exit 1
  fi
done

# The version does not reach the graph, but bubix1turboz.nim will not
# compile without it being defined. See build_nim_app.sh for the source.
APP_VERSION="$(grep '^version' ./*.nimble | sed -E 's/.*"(.*)".*/\1/')"

rm -rf "$WORK"
mkdir -p "$WORK"

for os in macosx linux windows; do
  echo "generating --os:$os"
  # Tolerated: a missing Graphviz makes genDepend exit 1 after writing the
  # .dot (see the header comment). A real failure is caught by the
  # existence check below instead of by the exit status.
  mise exec -- nim genDepend --hints:off --os:"$os" \
    -d:appVersion="$APP_VERSION" src/nim/bubix1turboz.nim >/dev/null 2>&1 || true
  if [ ! -f src/nim/bubix1turboz.dot ]; then
    echo "error: nim genDepend --os:$os produced no .dot file" >&2
    exit 1
  fi
  mv src/nim/bubix1turboz.dot "$WORK/$os.dot"
  # Where Graphviz *is* installed genDepend also renders an image beside
  # the source; drop it rather than leaving a stray file in src/. The
  # .deps listing lands at the repo root (not beside the source) and is
  # equally unwanted.
  rm -f src/nim/bubix1turboz.png src/nim/bubix1turboz.svg bubix1turboz.deps
done

# Project modules only - the standard library accounts for two thirds of
# the raw edges and says nothing about this application's structure.
cat "$WORK"/*.dot \
  | grep -E '^"bubix1[^"]*" -> "bubix1' \
  | sort -u > "$WORK/edges.txt"

# Mermaid cannot take a slash in a node id, so every module path becomes an
# underscore-joined id carrying the path as its label. Nodes are emitted in
# the order they appear in the (sorted) edge list rather than in awk's
# unordered array iteration, so re-running this produces no spurious diff.
cat > "$WORK/emit.awk" <<'AWK'
function id(m) { gsub(/\//, "_", m); return m }
function label(m) { sub(/^bubix1\//, "", m); return m }
function backend(m) { return m ~ /^bubix1\/ui\/(macos|linux|windows|stub)\// }
function seen(m) {
  if (!(m in nodes)) { nodes[m] = 1; order_n++; nodelist[order_n] = m }
}
function group(m) {
  if (m == "bubix1turboz") return "entry"
  if (backend(m)) { split(m, p, "/"); return p[3] }
  if (m ~ /^bubix1\/ui\//) return "facade"
  return "app"
}

BEGIN {
  FS = "\""
  title["ja", "app"]     = "アプリケーションモジュール"
  title["ja", "facade"]  = "UI の共通部分 (bubix1/ui)"
  title["ja", "macos"]   = "macOS / AppKit"
  title["ja", "linux"]   = "Linux / GTK"
  title["ja", "windows"] = "Windows / Win32"
  title["ja", "stub"]    = "スタブ (未実装の OS 用)"
  title["en", "app"]     = "Application modules"
  title["en", "facade"]  = "Shared UI code (bubix1/ui)"
  title["en", "macos"]   = "macOS / AppKit"
  title["en", "linux"]   = "Linux / GTK"
  title["en", "windows"] = "Windows / Win32"
  title["en", "stub"]    = "Stub (for OSes with no implementation yet)"
  # A star fans out more legibly downwards; the rest read left to right.
  dir["entry"] = "TD"; dir["app"] = "LR"
  dir["facade"] = "LR"; dir["backend"] = "LR"
}

# One scope per diagram:
#   entry    what the entry point imports directly
#   app      what the modules below it need from each other
#   facade   which backend each facade selects
#   backend  what those backends are built on
{
  from = $2; to = $4
  isbackend = backend(from) || backend(to)
  if (scope == "entry")        keep = (from == "bubix1turboz")
  else if (scope == "app")     keep = (from != "bubix1turboz" && !isbackend)
  else if (scope == "facade")  keep = (!backend(from) && backend(to))
  else                         keep = backend(from)
  if (!keep) next
  edges[++n] = id(from) " --> " id(to)
  seen(from); seen(to)
}

END {
  print "```mermaid"
  print "flowchart " dir[scope]
  for (j = 1; j <= order_n; j++) {
    m = nodelist[j]
    g = group(m)
    members[g] = members[g] "    " id(m) "[\"" label(m) "\"]\n"
  }
  norder = split("entry app facade macos linux windows stub", order, " ")
  for (i = 1; i <= norder; i++) {
    g = order[i]
    if (!(g in members)) continue
    # The entry point belongs to no group; a one-node subgraph around it
    # would only add a box to read.
    if (g == "entry") { printf "%s", members[g]; continue }
    print "  subgraph " g "[\"" title[lang, g] "\"]"
    printf "%s", members[g]
    print "  end"
  }
  for (i = 1; i <= n; i++) print "  " edges[i]
  print "```"
}
AWK

emit_region() { # $1 = lang
  local lang="$1" scope
  echo "$BEGIN_MARK"
  local -a scopes=(entry app facade backend)
  local -a heads_ja=(
    "### 本体が直接使っているモジュール"
    "### モジュールどうしのつながり"
    "### UI が OS ごとに切り替わるしくみ"
    "### OS ごとの実装が使っているもの"
  )
  local -a heads_en=(
    "### What the main program uses directly"
    "### How the modules relate to each other"
    "### How the UI switches from one OS to another"
    "### What each OS's implementation sits on"
  )
  local i=0
  for scope in "${scopes[@]}"; do
    echo
    if [ "$lang" = "ja" ]; then echo "${heads_ja[$i]}"; else echo "${heads_en[$i]}"; fi
    echo
    awk -v scope="$scope" -v lang="$lang" -f "$WORK/emit.awk" "$WORK/edges.txt"
    i=$((i + 1))
  done
  echo
  echo "$END_MARK"
}

for k in "${!DOCS[@]}"; do
  doc="${DOCS[$k]}"
  lang="${LANGS[$k]}"
  emit_region "$lang" > "$WORK/region.md"

  # Splice the region back in: everything up to BEGIN, the new region,
  # then everything from END on.
  awk -v begin="$BEGIN_MARK" -v end="$END_MARK" -v region="$WORK/region.md" '
    $0 == begin { while ((getline line < region) > 0) print line; skip = 1; next }
    $0 == end   { skip = 0; next }
    !skip       { print }
  ' "$doc" > "$WORK/spliced.md"

  # A splice that matched nothing would produce the input unchanged, which
  # is indistinguishable from success by file comparison alone. The
  # heading below is emitted only by this script - the hand-written
  # diagrams elsewhere in the document would satisfy a looser test.
  if [ "$lang" = "ja" ]; then
    probe='### モジュールどうしのつながり'
  else
    probe='### How the modules relate to each other'
  fi
  if ! grep -qxF "$probe" "$WORK/spliced.md"; then
    echo "error: the generated region did not splice into $doc" >&2
    exit 1
  fi

  mv "$WORK/spliced.md" "$doc"
  echo "wrote $doc"
done

edge_count="$(wc -l < "$WORK/edges.txt" | tr -d ' ')"
rm -rf "$WORK"

echo "$edge_count edges across 4 diagrams"
