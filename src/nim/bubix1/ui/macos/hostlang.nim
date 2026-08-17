## AppKit backend for ui/hostlang.nim. See hostlang.m.

{.compile: "hostlang.m".}
{.passL: "-framework Foundation".}

proc bx1PreferredLanguage(): cstring
  {.importc: "bx1_preferred_language", cdecl.}
  ## The first of the user's preferred languages, as a BCP 47 tag
  ## ("ja-JP"). Read from NSLocale rather than from the environment: a
  ## bundle launched from the Finder inherits no LANG at all, so an
  ## environment-based guess works from a terminal and fails on a
  ## double-click.

proc languageTag*(): string =
  let tag = bx1PreferredLanguage()
  if tag == nil: "" else: $tag
