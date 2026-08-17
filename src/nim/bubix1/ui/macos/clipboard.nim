## AppKit backend for ui/clipboard.nim. See clipboard.m.

{.compile: "clipboard.m".}
{.passL: "-framework Cocoa".}

proc bx1ClipboardText(): cstring {.importc: "bx1_clipboard_text", cdecl.}
proc bx1ClipboardFree(text: cstring) {.importc: "bx1_clipboard_free", cdecl.}

proc text*(): string =
  let raw = bx1ClipboardText()
  if raw == nil:
    return ""
  result = $raw
  bx1ClipboardFree(raw)
