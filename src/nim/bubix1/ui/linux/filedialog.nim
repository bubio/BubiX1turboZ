## GTK backend for ui/filedialog.nim: open/save panels, alerts and the
## multi-disk chooser, standing on the shared top-level window.
##
## The facade hands down every word it owns already translated. The two
## panels it opens without any (openFile/saveFile carry no button labels)
## borrow GTK's own, looked up from GTK's message catalog with g_dgettext -
## the same words the rest of the desktop shows, in the user's language.

import std/strutils
import ./gtk3
import ./gtkshell

proc gtkLabel(msgid: string): cstring =
  ## A GTK-supplied button label (e.g. "_Cancel"), in the desktop's language.
  g_dgettext("gtk30", msgid.cstring)

proc parent(): GtkWidget =
  ## Dialogs hang off the one window; nil before it exists (they stand alone).
  gtkshell.topWindow()

proc addFilters(chooser: GtkWidget, extensions: string) =
  if extensions.len == 0:
    return
  let filter = gtk_file_filter_new()
  var names: seq[string]
  for ext in extensions.split(','):
    let e = ext.strip()
    if e.len == 0: continue
    # Patterns are matched case-sensitively, and disk images arrive spelled
    # both ways, so each extension is added in lower and upper case.
    gtk_file_filter_add_pattern(filter, ("*." & e.toLowerAscii).cstring)
    gtk_file_filter_add_pattern(filter, ("*." & e.toUpperAscii).cstring)
    names.add("*." & e)
  gtk_file_filter_set_name(filter, names.join(" ").cstring)
  gtk_file_chooser_add_filter(chooser, filter)

proc setStartDir(chooser: GtkWidget, startDir: string) =
  ## Opens the chooser on `startDir`, or leaves GTK's own choice alone when
  ## the caller has none. Unlike AppKit, GTK remembers nothing between
  ## panels, so without this every chooser starts in the working directory.
  if startDir.len > 0:
    gtk_file_chooser_set_current_folder(chooser, startDir.cstring)

proc runFilename(dialog: GtkWidget): string =
  ## Run a file chooser to completion and return the chosen path, or "".
  result = ""
  if gtk_dialog_run(dialog) == GTK_RESPONSE_ACCEPT:
    let fn = gtk_file_chooser_get_filename(dialog)
    if fn != nil:
      result = $fn
      g_free(fn)
  gtk_widget_destroy(dialog)

proc earlyInit*() =
  discard

proc setParentWindow*(window: pointer) =
  ## The Linux dialogs find the window through gtkshell, not this SDL pointer,
  ## so there is nothing to store.
  discard

proc openFile*(extensions, startDir: string): string =
  ensureGtk()
  let dlg = gtk_file_chooser_dialog_new(gtkLabel("_Open"), parent(),
    GTK_FILE_CHOOSER_ACTION_OPEN, nil)
  discard gtk_dialog_add_button(dlg, gtkLabel("_Cancel"), GTK_RESPONSE_CANCEL)
  discard gtk_dialog_add_button(dlg, gtkLabel("_Open"), GTK_RESPONSE_ACCEPT)
  setStartDir(dlg, startDir)
  addFilters(dlg, extensions)
  runFilename(dlg)

proc saveFile*(extensions, suggestedName, startDir: string): string =
  ensureGtk()
  let dlg = gtk_file_chooser_dialog_new(gtkLabel("_Save"), parent(),
    GTK_FILE_CHOOSER_ACTION_SAVE, nil)
  discard gtk_dialog_add_button(dlg, gtkLabel("_Cancel"), GTK_RESPONSE_CANCEL)
  discard gtk_dialog_add_button(dlg, gtkLabel("_Save"), GTK_RESPONSE_ACCEPT)
  gtk_file_chooser_set_do_overwrite_confirmation(dlg, 1)
  setStartDir(dlg, startDir)
  if suggestedName.len > 0:
    gtk_file_chooser_set_current_name(dlg, suggestedName.cstring)
  addFilters(dlg, extensions)
  runFilename(dlg)

proc chooseFolder*(title, prompt, startDir: string): string =
  ensureGtk()
  let dlg = gtk_file_chooser_dialog_new(title.cstring, parent(),
    GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER, nil)
  discard gtk_dialog_add_button(dlg, gtkLabel("_Cancel"), GTK_RESPONSE_CANCEL)
  discard gtk_dialog_add_button(dlg, prompt.cstring, GTK_RESPONSE_ACCEPT)
  setStartDir(dlg, startDir)
  runFilename(dlg)

proc message*(title, body, okLabel: string) =
  ensureGtk()
  let dlg = gtk_message_dialog_new(parent(),
    GTK_DIALOG_MODAL or GTK_DIALOG_DESTROY_WITH_PARENT,
    GTK_MESSAGE_INFO, GTK_BUTTONS_NONE, "%s".cstring, body.cstring)
  gtk_window_set_title(dlg, title.cstring)
  discard gtk_dialog_add_button(dlg, okLabel.cstring, GTK_RESPONSE_OK)
  discard gtk_dialog_run(dlg)
  gtk_widget_destroy(dlg)

proc missingRom*(title, body, folder, openLabel, quitLabel: string): bool =
  ensureGtk()
  let dlg = gtk_message_dialog_new(parent(),
    GTK_DIALOG_MODAL or GTK_DIALOG_DESTROY_WITH_PARENT,
    GTK_MESSAGE_WARNING, GTK_BUTTONS_NONE, "%s".cstring, body.cstring)
  gtk_window_set_title(dlg, title.cstring)
  discard gtk_dialog_add_button(dlg, quitLabel.cstring, GTK_RESPONSE_CANCEL)
  discard gtk_dialog_add_button(dlg, openLabel.cstring, GTK_RESPONSE_ACCEPT)
  let revealed = gtk_dialog_run(dlg) == GTK_RESPONSE_ACCEPT
  gtk_widget_destroy(dlg)
  if revealed:
    # Reveal the folder in the file manager. Single-quote the path and escape
    # any embedded quote, since g_spawn parses the line with shell rules.
    let quoted = "'" & folder.replace("'", "'\\''") & "'"
    discard g_spawn_command_line_async(("xdg-open " & quoted).cstring, nil)
  revealed

proc chooseDisk*(title: string, rows: openArray[string], initial: int,
                 insertLabel, cancelLabel: string): int =
  ensureGtk()
  let dlg = gtk_dialog_new_with_buttons(title.cstring, parent(),
    GTK_DIALOG_MODAL or GTK_DIALOG_DESTROY_WITH_PARENT, nil)
  discard gtk_dialog_add_button(dlg, cancelLabel.cstring, GTK_RESPONSE_CANCEL)
  discard gtk_dialog_add_button(dlg, insertLabel.cstring, GTK_RESPONSE_ACCEPT)
  let combo = gtk_combo_box_text_new()
  for row in rows:
    gtk_combo_box_text_append_text(combo, sjisToUtf8(row).cstring)
  gtk_combo_box_set_active(combo, initial.cint)
  gtk_box_pack_start(gtk_dialog_get_content_area(dlg), combo, 0, 0, 8)
  gtk_widget_show_all(dlg)
  result =
    if gtk_dialog_run(dlg) == GTK_RESPONSE_ACCEPT: gtk_combo_box_get_active(combo).int
    else: -1
  gtk_widget_destroy(dlg)
