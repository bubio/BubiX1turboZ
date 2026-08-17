## What language the host says the user reads.
##
## Not user interface as such, but host-dependent for the same reason the
## rest of this directory is: every platform answers the question through
## an API of its own, and none of them agree on where the answer lives.

when defined(macosx):
  from ./macos/hostlang as backend import nil
elif defined(windows):
  from ./windows/hostlang as backend import nil
else:
  from ./linux/hostlang as backend import nil

proc languageTag*(): string =
  ## A language tag ("ja", "ja-JP", "ja_JP.UTF-8" - the separators differ
  ## by platform, so read only what you need from the front of it), or ""
  ## when the host could not name one.
  backend.languageTag()
