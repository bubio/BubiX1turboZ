## GTK backend for ui/clipboard.nim: the system clipboard, for Control > Paste.

import ./gtk3
import ./gtkshell

proc text*(): string =
  ## The clipboard's text, or "" if it holds none. gtk_clipboard_wait_for_text
  ## runs its own nested loop, so it works whether or not the application's
  ## event loop is turning.
  ensureGtk()
  let clip = gtk_clipboard_get(gdk_atom_intern("CLIPBOARD", 0))
  let s = gtk_clipboard_wait_for_text(clip)
  if s == nil:
    return ""
  result = $s
  g_free(s)
