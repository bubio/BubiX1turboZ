## System clipboard access, for the original's Control > Paste (which types
## the clipboard into the guest via the core's auto key).

when defined(macosx):
  from ./macos/clipboard as backend import nil
elif defined(linux):
  from ./linux/clipboard as backend import nil
elif defined(windows):
  from ./windows/clipboard as backend import nil
else:
  from ./stub/clipboard as backend import nil

proc getText*(): string =
  ## The clipboard's text, or "" if it holds none.
  backend.text()
