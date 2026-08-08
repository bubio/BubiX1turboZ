## Persistence for host-side preferences the emulation core cannot hold.
##
## Almost everything the menus change lives in the core's own `config`
## struct and round-trips through its config.ini. A few settings do not:
## `config.show_status_bar`, for instance, is declared inside
## `#if defined(_WIN32)` in src/core/config.h, so it does not exist in this
## build at all. Rather than patch the vendored core for one boolean, those
## settings live here, in a small INI-style file beside config.ini.
##
## Format is deliberately trivial - `Key=Value` per line, `#` comments,
## unknown keys preserved on save so a newer build's settings survive a
## downgrade.

import std/[os, strutils, tables]

type
  HostConfig* = object
    values: OrderedTable[string, string]

proc load*(path: string): HostConfig =
  ## Missing or unreadable file yields an empty config rather than an
  ## error: absent preferences simply fall back to their defaults.
  result.values = initOrderedTable[string, string]()
  if not fileExists(path):
    return
  var content: string
  try:
    content = readFile(path)
  except IOError:
    return
  for rawLine in content.splitLines():
    let line = rawLine.strip()
    if line.len == 0 or line.startsWith('#'):
      continue
    let sep = line.find('=')
    if sep > 0:
      result.values[line[0 ..< sep].strip()] = line[sep + 1 .. ^1].strip()

proc save*(path: string, cfg: HostConfig) =
  var lines = @["# BubiX1turboZ host settings (see src/nim/bubix1/hostconfig.nim)"]
  for key, value in cfg.values.pairs:
    lines.add(key & "=" & value)
  try:
    writeFile(path, lines.join("\n") & "\n")
  except IOError as e:
    stderr.writeLine "bubix1turboz: could not save host settings: " & e.msg

proc getBool*(cfg: HostConfig, key: string, fallback: bool): bool =
  let raw = cfg.values.getOrDefault(key, "")
  if raw.len == 0: fallback else: raw != "0"

proc setBool*(cfg: var HostConfig, key: string, value: bool) =
  cfg.values[key] = (if value: "1" else: "0")
