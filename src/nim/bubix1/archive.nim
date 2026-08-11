## Archive expansion, playlist parsing, and media classification for
## drag-and-drop and file-menu media loading (phase 7).
##
## This module only resolves a dropped/opened path down to a concrete,
## orderable list of floppy/tape image paths - it knows nothing about
## `bx1_handle` or drive assignment. The caller (bubix1turboz.nim) decides
## which resolved path goes to which drive and when to reset the VM.
##
## Extraction shells out to `/usr/bin/tar`, the bsdtar front end to
## libarchive that ships with the OS itself, not the Homebrew `p7zip`
## `7z` binary from docs/dev/DevelopmentPlan.md phase 1.1 - a shipped
## .dmg must work on a Mac with no Homebrew installed. Confirmed at
## authoring time: bsdtar's libarchive backend reads both `.7z` and
## `.zip` with no extra flags, so one code path covers both formats.

import std/[os, osproc, strutils, hashes, times, algorithm]
import paths

type
  MediaKind* = enum
    mkFloppy, mkTape, mkArchive, mkPlaylist, mkUnknown

const
  floppyExts = [".d88", ".d77", ".2d"]
  tapeExts = [".tap", ".cmt", ".t88", ".wav"]
  archiveExts = [".zip", ".7z"]
  playlistExts = [".m3u", ".m3u8"]

proc classify*(path: string): MediaKind =
  let ext = path.splitFile().ext.toLowerAscii()
  if ext in floppyExts: mkFloppy
  elif ext in tapeExts: mkTape
  elif ext in archiveExts: mkArchive
  elif ext in playlistExts: mkPlaylist
  else: mkUnknown

proc cacheKey(path: string): string =
  ## Identifies an archive by name + size + mtime rather than hashing its
  ## full contents - commercial compilations run into the hundreds of MB,
  ## and re-reading one on every drop/reopen would defeat the point of
  ## caching. Collisions would only matter if two different archives
  ## shared all three, which does not happen in practice for this use.
  let info = getFileInfo(path)
  var h = hash(path.extractFilename())
  h = h !& hash(info.size)
  h = h !& hash(info.lastWriteTime.toUnix())
  toHex(uint64(!$h), 12)

proc extractArchive*(path: string): string =
  ## Extracts `path` under `paths.extractedDir()`, reusing a previous
  ## extraction keyed by `cacheKey`. Returns the extraction directory.
  let dest = paths.extractedDir() / cacheKey(path)
  if dirExists(dest):
    return dest
  # Extract into a sibling temp directory and move it into place only on
  # success. Extracting straight into `dest` would leave a directory that
  # *exists* (and therefore looks cached and reusable forever) if the
  # process is killed or the archive is corrupt mid-extraction.
  let tmp = dest & ".tmp-" & $getCurrentProcessId()
  removeDir(tmp)
  createDir(tmp)
  let (output, code) = execCmdEx("/usr/bin/tar -xf " & path.quoteShell() & " -C " & tmp.quoteShell())
  if code != 0:
    removeDir(tmp)
    raise newException(IOError, "failed to extract " & path & ": " & output)
  moveDir(tmp, dest)
  dest

proc parsePlaylist*(path: string): seq[string] =
  ## One entry per line; blank lines and `#`-comments are skipped.
  ## Relative entries resolve against the playlist's own directory - the
  ## shape commercial multi-disk compilations ship in is an archive
  ## containing `disk1.d88`, `disk2.d88`, ... alongside one `.m3u` that
  ## fixes their order.
  let base = path.parentDir()
  for rawLine in path.readFile().splitLines():
    let line = rawLine.strip()
    if line.len == 0 or line.startsWith("#"):
      continue
    result.add(if isAbsolute(line): line else: base / line)

proc findMediaFiles(dir: string): seq[string] =
  ## Depth-first walk of an extraction directory, collecting floppy/tape
  ## images. A `.m3u`/`.m3u8` found alongside them wins outright and
  ## fixes disk order; without one, files are sorted by path so that the
  ## common `disk1`/`disk2` naming convention still yields a stable,
  ## sensible drive assignment.
  var playlist = ""
  for path in walkDirRec(dir):
    case classify(path)
    of mkPlaylist:
      if playlist.len == 0:
        playlist = path
    of mkFloppy, mkTape:
      result.add path
    of mkArchive, mkUnknown:
      discard
  if playlist.len > 0:
    return parsePlaylist(playlist)
  result.sort()

proc resolveMedia*(path: string): seq[string] =
  ## Turns any accepted input - a bare image, an archive, or a playlist -
  ## into a concrete, ordered list of floppy/tape image paths ready to
  ## mount. Entry 0 is intended for drive 1, entry 1 for drive 2.
  case classify(path)
  of mkArchive: findMediaFiles(extractArchive(path))
  of mkPlaylist: parsePlaylist(path)
  of mkFloppy, mkTape: @[path]
  of mkUnknown: @[]

proc isAcceptedMedia*(path: string): bool =
  classify(path) != mkUnknown
