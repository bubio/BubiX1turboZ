## System clipboard access, for the original's Control > Paste (which types
## the clipboard into the guest via the core's auto key). See clipboard.m.

{.compile: "clipboard.m".}
{.passL: "-framework Cocoa".}

proc bx1ClipboardText(): cstring {.importc: "bx1_clipboard_text", cdecl.}
proc bx1ClipboardFree(text: cstring) {.importc: "bx1_clipboard_free", cdecl.}

proc getText*(): string =
  ## The clipboard's text, or "" if it holds none.
  let raw = bx1ClipboardText()
  if raw == nil:
    return ""
  result = $raw
  bx1ClipboardFree(raw)
