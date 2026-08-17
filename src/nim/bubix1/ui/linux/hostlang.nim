## POSIX backend for ui/hostlang.nim: the language the environment names.
##
## Used by every platform that is not macOS or Windows, not by Linux
## alone - a desktop environment's own idea of the language reaches an
## application through these variables either way.

import std/os

proc languageTag*(): string =
  ## The first of these that is set and is not the C locale wins, which is
  ## the order gettext itself consults them in.
  for name in ["LC_ALL", "LC_MESSAGES", "LANG"]:
    let value = getEnv(name)
    if value.len > 0 and value != "C" and value != "POSIX":
      return value
  ""
