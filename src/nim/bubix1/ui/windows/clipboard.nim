## Win32 backend for ui/clipboard.nim: the system clipboard, for Control > Paste.

import ./win32
import ./winshell

proc text*(): string =
  ## The clipboard's text, or "" if it holds none.
  if isClipboardFormatAvailable(CfUnicodetext) == 0:
    return ""
  if openClipboard(winshell.mainHwnd) == 0:
    return ""
  defer: discard closeClipboard()
  let data = getClipboardData(CfUnicodetext)
  if data == nil:
    return ""
  let locked = globalLock(data)
  if locked == nil:
    return ""
  # CF_UNICODETEXT's global block is itself a null-terminated UTF-16
  # string; fromWide reads it directly off the locked pointer.
  result = fromWide(cast[WideCString](locked))
  discard globalUnlock(data)
