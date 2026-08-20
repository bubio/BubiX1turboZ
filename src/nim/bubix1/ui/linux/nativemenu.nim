## GTK backend for ui/nativemenu.nim: the menu bar built into the top-level
## window (gtkshell.nim), rather than a global bar as on macOS.
##
## Every item is a GtkCheckMenuItem, so that the facade's `checked=` can put
## a tick on the toggles (Full Speed, the aspect and scale radios, Romaji to
## Kana) exactly as on macOS. An action item never has `checked=` called on
## it and simply keeps a blank indicator. GTK toggles a check item's state
## on click on its own, which an action item must not keep - so a click is
## first reset to the state the application actually holds for that item, and
## only then dispatched (the action may set a new state from inside).

import std/[tables, strutils]
import ./gtk3
import ./gtkshell

var
  actionFn: proc (tag: cint) {.cdecl.}
  items: Table[cint, GtkWidget]      ## tag -> item, for state changes
  checkedState: Table[cint, bool]    ## the application's own idea of each tick
  suppress = false                   ## guard against set_active re-entering activate

proc onActivate(item: GtkWidget, data: Gpointer) {.cdecl.} =
  if suppress:
    return
  let tag = cast[cint](cast[int](data))
  # Undo GTK's automatic toggle before handing control to the action: an
  # action item stays unticked, a toggle is set to its new state by the
  # action itself (through setChecked).
  suppress = true
  gtk_check_menu_item_set_active(item,
    if checkedState.getOrDefault(tag): 1 else: 0)
  suppress = false
  if actionFn != nil:
    actionFn(tag)

proc setAction*(fn: proc (tag: cint) {.cdecl.}) =
  actionFn = fn

proc newToplevel(title: cstring): GtkWidget =
  ## A menu-bar entry (or an application menu): a labelled item carrying a
  ## submenu. The submenu is the shell items are appended to.
  let item = gtk_menu_item_new_with_label(title)
  let sub = gtk_menu_new()
  gtk_menu_item_set_submenu(item, sub)
  gtk_widget_show(item)
  gtk_menu_shell_append(menuBar(), item)
  sub

proc installMenubar*(appName: cstring): pointer =
  ## The application menu at the head of the bar. About and Quit hang off it,
  ## following the macOS layout; Linux has no system-owned items to add.
  ensureInit()
  newToplevel(appName)

proc addStandardItem*(menu: pointer, title: cstring, which: cint,
                      key: cstring, mods: cint) =
  ## Services / Hide / Show All are macOS' own; there is nothing to add here.
  discard

proc addToplevel*(title: cstring): pointer =
  newToplevel(title)

proc addSubmenu*(parent: pointer, title: cstring): pointer =
  let item = gtk_menu_item_new_with_label(title)
  let sub = gtk_menu_new()
  gtk_menu_item_set_submenu(item, sub)
  gtk_widget_show(item)
  gtk_menu_shell_append(cast[GtkWidget](parent), item)
  sub

proc addAccelerator(item: GtkWidget, key: cstring, mods: cint) =
  let s = $key
  if s.len == 0:
    return
  var gmods: cuint = 0
  # ModCommand is the platform's primary accelerator: Control here.
  if (mods and 1) != 0: gmods = gmods or GDK_CONTROL_MASK   # ModCommand
  if (mods and 2) != 0: gmods = gmods or GDK_SHIFT_MASK     # ModShift
  if (mods and 4) != 0: gmods = gmods or GDK_MOD1_MASK      # ModOption -> Alt
  if (mods and 8) != 0: gmods = gmods or GDK_CONTROL_MASK   # ModControl
  # GDK key values coincide with ASCII for the letters and digits the menus
  # use; the accelerator is shown lower-case as menus conventionally are.
  let keyval = ord(toLowerAscii(s[0])).cuint
  gtk_widget_add_accelerator(item, "activate", accels(), keyval, gmods,
                             GTK_ACCEL_VISIBLE)

proc addItem*(menu: pointer, title: cstring, tag: cint, key: cstring, mods: cint) =
  let item = gtk_check_menu_item_new_with_label(title)
  items[tag] = item
  checkedState[tag] = false
  connect(item, "activate", cast[GCallback](onActivate),
          cast[Gpointer](cast[int](tag)))
  addAccelerator(item, key, mods)
  gtk_widget_show(item)
  gtk_menu_shell_append(cast[GtkWidget](menu), item)

proc addSeparator*(menu: pointer, tag: cint) =
  let item = gtk_separator_menu_item_new()
  items[tag] = item
  gtk_widget_show(item)
  gtk_menu_shell_append(cast[GtkWidget](menu), item)

proc setHidden*(tag: cint, hidden: cint) =
  let item = items.getOrDefault(tag)
  if item != nil:
    if hidden != 0: gtk_widget_hide(item)
    else: gtk_widget_show(item)

proc setChecked*(tag: cint, checked: cint) =
  checkedState[tag] = checked != 0
  let item = items.getOrDefault(tag)
  if item != nil:
    suppress = true
    gtk_check_menu_item_set_active(item, checked)
    suppress = false

proc getChecked*(tag: cint): cint =
  if checkedState.getOrDefault(tag): 1 else: 0

proc setEnabled*(tag: cint, enabled: cint) =
  let item = items.getOrDefault(tag)
  if item != nil:
    gtk_widget_set_sensitive(item, enabled)

proc setItemTitle*(tag: cint, title: cstring) =
  let item = items.getOrDefault(tag)
  if item != nil:
    gtk_menu_item_set_label(item, title)
