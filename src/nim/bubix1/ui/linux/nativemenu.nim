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
  hiddenState: Table[cint, bool]     ## items collapsed out of their menu
  enabledState: Table[cint, bool]    ## items greyed out
  accelTags: Table[uint64, cint]     ## keyval + modifiers -> tag, for handleAccelerator
  suppress = false                   ## guard against set_active re-entering activate

proc accelKey(keyval, mods: cuint): uint64 =
  ## One lookup key out of a key value and a GDK modifier mask.
  (keyval.uint64 shl 32) or mods.uint64

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

proc addAccelerator(item: GtkWidget, tag: cint, key: cstring, mods: cint) =
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
  # The accelerator is registered with GTK for its label in the menu, and
  # kept here as well because GTK never gets to fire it - see
  # handleAccelerator below.
  accelTags[accelKey(keyval, gmods)] = tag

proc addItem*(menu: pointer, title: cstring, tag: cint, key: cstring, mods: cint) =
  let item = gtk_check_menu_item_new_with_label(title)
  items[tag] = item
  checkedState[tag] = false
  connect(item, "activate", cast[GCallback](onActivate),
          cast[Gpointer](cast[int](tag)))
  addAccelerator(item, tag, key, mods)
  gtk_widget_show(item)
  gtk_menu_shell_append(cast[GtkWidget](menu), item)

proc addSeparator*(menu: pointer, tag: cint) =
  let item = gtk_separator_menu_item_new()
  items[tag] = item
  gtk_widget_show(item)
  gtk_menu_shell_append(cast[GtkWidget](menu), item)

proc setHidden*(tag: cint, hidden: cint) =
  hiddenState[tag] = hidden != 0
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
  enabledState[tag] = enabled != 0
  let item = items.getOrDefault(tag)
  if item != nil:
    gtk_widget_set_sensitive(item, enabled)

proc setItemTitle*(tag: cint, title: cstring) =
  let item = items.getOrDefault(tag)
  if item != nil:
    gtk_menu_item_set_label(item, title)

proc handleAccelerator*(key: cint, ctrl, shift, alt, gui: cint): cint =
  ## Fire the item whose keyboard equivalent this keystroke is, if any.
  ##
  ## GTK's own accelerator handling never runs here: X keyboard focus sits
  ## on the embedded SDL window (gtkshell), so a key press reaches SDL and
  ## GTK is never told about it. The application's event loop therefore
  ## offers every key press to this, ahead of the guest machine, and it
  ## looks the key up in the same table `addAccelerator` filled.
  ##
  ## `gui` (the Super key) is not a menu modifier on this platform and is
  ## only accepted as "not pressed": a Super combination belongs to the
  ## desktop, not to us.
  if key <= 0 or key > 0x7f or gui != 0:
    return 0
  var gmods: cuint = 0
  # ModCommand is Control here, so a menu accelerator always carries one
  # modifier at least; a bare key press is the guest's.
  if ctrl != 0: gmods = gmods or GDK_CONTROL_MASK
  if shift != 0: gmods = gmods or GDK_SHIFT_MASK
  if alt != 0: gmods = gmods or GDK_MOD1_MASK
  if gmods == 0:
    return 0
  let keyval = ord(toLowerAscii(char(key))).cuint
  let tag = accelTags.getOrDefault(accelKey(keyval, gmods), 0.cint)
  if tag == 0 or hiddenState.getOrDefault(tag) or
     not enabledState.getOrDefault(tag, true):
    return 0
  # The item was not clicked, so GTK has toggled nothing to undo: the
  # action is called exactly as `onActivate` would call it.
  if actionFn != nil:
    actionFn(tag)
  1
