## Tracks recently-opened media paths for the File menu's "Recent Files"
## submenu.
##
## Not backed by the core's own config_t.recent_*_path fields - those are
## declared but never populated by this vendored tree (see
## docs/dev/DevelopmentPlan.md phase 6). This keeps its own flat text
## file instead, one path per line, most recent first.

import std/[os, strutils]

const maxEntries = 8 ## matches MAX_HISTORY in src/core/config.h

proc load*(path: string): seq[string] =
  if not fileExists(path):
    return @[]
  for line in path.readFile().splitLines():
    let p = line.strip()
    if p.len > 0:
      result.add p
    if result.len >= maxEntries:
      break

proc save*(path: string, entries: seq[string]) =
  createDir(path.parentDir())
  writeFile(path, entries.join("\n") & (if entries.len > 0: "\n" else: ""))

proc pushFront*(entries: seq[string], newPath: string): seq[string] =
  ## Moves `newPath` to the front, de-duplicating, capped at maxEntries.
  result = @[newPath]
  for p in entries:
    if p != newPath and result.len < maxEntries:
      result.add p
