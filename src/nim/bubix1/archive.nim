## Archive expansion, playlist parsing, and media classification for
## drag-and-drop and file-menu media loading (phase 7).
##
## This module only resolves a dropped/opened path down to a concrete,
## orderable list of floppy/tape image paths - it knows nothing about
## `bx1_handle` or drive assignment. The caller (bubix1turboz.nim) decides
## which resolved path goes to which drive and when to reset the VM.
##
## Extraction shells out to bsdtar, the libarchive front end, whose backend
## reads both `.7z` and `.zip` with no extra flags - so one code path covers
## both formats, and no third-party `7z`/`p7zip` binary is needed. macOS
## ships bsdtar as `/usr/bin/tar`; other systems provide it as a separate
## `bsdtar` (on Linux, the `libarchive-tools` package). GNU tar cannot read
## these formats, so `extractTool` prefers a real `bsdtar` and only falls
## back to `/usr/bin/tar` where that path *is* bsdtar.

import std/[os, osproc, strutils, hashes, times, algorithm]
import paths

type
  MediaKind* = enum
    mkFloppy, mkTape, mkArchive, mkPlaylist, mkUnknown

const
  # Kept in step with filedialog.DiskExtensions: an extension the Open panel
  # lets through but classify() calls unknown would silently resolve to no
  # media at all.
  floppyExts = [".d88", ".d77", ".d8e", ".1dd", ".2d"]
  tapeExts = [".tap", ".cmt", ".t88", ".wav"]
  archiveExts = [".zip", ".7z"]
  playlistExts = [".m3u", ".m3u8"]

proc extractTool(): string =
  ## The bsdtar binary to extract with. A real `bsdtar` on the PATH wins
  ## (Linux's libarchive-tools puts it there); otherwise `/usr/bin/tar`,
  ## which is bsdtar on macOS. GNU tar cannot read .7z/.zip, so a bare `tar`
  ## from the PATH is deliberately not consulted.
  let bsd = findExe("bsdtar")
  if bsd.len > 0: bsd else: "/usr/bin/tar"

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

const SourceMetaName = "source.txt"
  ## Records which archive an extraction directory came from. A cache
  ## directory is named after a hash, so without this the only thing
  ## `exportCache` could call the exported folder is that hash - and a
  ## user looking for a game's save data would have nothing to recognise.
  ## `classify` calls it unknown, so `findMediaFiles` steps over it.

proc writeSourceMeta(dest, path: string) =
  ## One line, the archive's own path. Written next to the extracted
  ## files rather than in an index of its own so that deleting a cache
  ## directory takes its metadata with it.
  ##
  ## Best-effort: an extraction that cannot record where it came from is
  ## still a usable extraction, and failing the mount over it would be a
  ## poor trade.
  try:
    writeFile(dest / SourceMetaName, path & "\n")
  except CatchableError:
    discard

proc readSourceMeta(dir: string): string =
  ## The archive `dir` was extracted from, or "" for a directory that
  ## predates `SourceMetaName` or whose archive was never recorded.
  try:
    readFile(dir / SourceMetaName).strip()
  except CatchableError:
    ""

proc extractArchive*(path: string): string =
  ## Extracts `path` under `paths.extractedDir()`, reusing a previous
  ## extraction keyed by `cacheKey`. Returns the extraction directory.
  let dest = paths.extractedDir() / cacheKey(path)
  if dirExists(dest):
    # Fills the file in for a directory extracted before this app wrote
    # one, so an old cache becomes exportable by name on next use.
    if not fileExists(dest / SourceMetaName):
      writeSourceMeta(dest, path)
    return dest
  # Extract into a sibling temp directory and move it into place only on
  # success. Extracting straight into `dest` would leave a directory that
  # *exists* (and therefore looks cached and reusable forever) if the
  # process is killed or the archive is corrupt mid-extraction.
  let tmp = dest & ".tmp-" & $getCurrentProcessId()
  removeDir(tmp)
  createDir(tmp)
  let (output, code) = execCmdEx(extractTool().quoteShell() & " -xf " &
    path.quoteShell() & " -C " & tmp.quoteShell())
  if code != 0:
    removeDir(tmp)
    raise newException(IOError, "failed to extract " & path & ": " & output)
  moveDir(tmp, dest)
  writeSourceMeta(dest, path)
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

# --- Exporting the extraction cache ---------------------------------------
#
# A disk mounted out of an archive is a file under `paths.extractedDir()`,
# and the guest writes its saves straight into it. That directory is named
# after a hash, sits inside the application's own storage, and is deleted
# without ceremony when a cache is invalidated - so a game's save data can
# be there and be, for the user, unreachable and unsafe. Bubilator88 has
# the same problem and answers it the same way (`exportCachedDisks` in its
# DiskCacheManager). This is that answer.

type
  ExportResult* = object
    ## What `exportCache` did. `archives` counts extraction directories,
    ## `files` the images inside them.
    archives*: int
    files*: int

proc uniqueDir(parent, name: string): string =
  ## `parent/name`, or `parent/name-2`, `parent/name-3`, ... if taken. An
  ## export never writes into a directory it did not create: two archives
  ## can legitimately share a name, and merging their disks would produce
  ## a folder that belongs to neither.
  result = parent / name
  var n = 2
  while dirExists(result) or fileExists(result):
    result = parent / (name & "-" & $n)
    inc n

proc copyMediaTree(src, dest: string): int =
  ## Copies `src`'s media files into `dest`, keeping the layout the
  ## archive had - a compilation that ships `Disk A/game.d88` is worth
  ## exporting with that folder intact. Returns how many files were
  ## written. The metadata file is not one of them.
  for path in walkDirRec(src):
    if path.extractFilename() == SourceMetaName:
      continue
    case classify(path)
    of mkFloppy, mkTape, mkPlaylist:
      let target = dest / path.relativePath(src)
      createDir(target.parentDir())
      copyFile(path, target)
      inc result
    of mkArchive, mkUnknown:
      discard

proc exportCache*(destination: string): ExportResult =
  ## Copies every extracted archive under `paths.extractedDir()` into
  ## `destination`, one folder per archive named after the archive itself
  ## (falling back to the cache key when the archive was never recorded).
  ##
  ## Everything is copied rather than only what the guest has written to.
  ## "Which of these did a game save into" is not a question this app can
  ## answer honestly - a disk's timestamp moves when the core rewrites a
  ## sector for any reason, including ones the user would not call a save
  ## - and a filter that quietly left the wanted disk behind would be
  ## worse than a copy that includes a few the user did not need.
  ##
  ## Raises `OSError`/`IOError` if a copy fails; whatever was written
  ## before that stays where it is.
  let cacheRoot = paths.extractedDir()
  if not dirExists(cacheRoot):
    return
  var dirs: seq[string]
  for kind, path in walkDir(cacheRoot):
    # `.tmp-<pid>` directories are extractions in flight (see
    # extractArchive); they are nobody's disks yet.
    if kind == pcDir and not path.extractFilename().contains(".tmp-"):
      dirs.add path
  dirs.sort()
  for dir in dirs:
    let source = readSourceMeta(dir)
    let name =
      if source.len > 0: source.extractFilename().changeFileExt("")
      else: dir.extractFilename()
    let target = uniqueDir(destination, name)
    let copied = copyMediaTree(dir, target)
    if copied == 0:
      # An extraction that held no media at all: leave no empty folder
      # behind to explain.
      removeDir(target)
      continue
    inc result.archives
    result.files += copied
