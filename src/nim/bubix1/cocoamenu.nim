## Direct NSMenuItem manipulation for what uing's Menu/MenuItem API can't
## do: attaching a Cmd-key shortcut, renaming an item, or toggling one's
## enabled state after menu construction. See cocoamenu.m for why.
##
## All lookups happen after the uing window with the menu bar has been
## shown (`win.show()`) - NSApp has no main menu until then - and match
## items by a stable prefix of their *current* title, since uing itself
## never renames anything out from under us.

{.compile: "cocoamenu.m".}
{.passL: "-framework Cocoa".}

proc bx1MenuSetKeyEquivalentImpl(menuTitle, itemPrefix, key: cstring, withShift: cint): cint
  {.importc: "bx1_menu_set_key_equivalent", cdecl.}
proc bx1MenuSetTitleImpl(menuTitle, itemPrefix, newTitle: cstring): cint
  {.importc: "bx1_menu_set_title", cdecl.}
proc bx1MenuSetEnabledImpl(menuTitle, itemPrefix: cstring, enabled: cint): cint
  {.importc: "bx1_menu_set_enabled", cdecl.}
proc bx1MenuDisableAutoenableAllImpl() {.importc: "bx1_menu_disable_autoenable_all", cdecl.}

proc titleArg(menuTitle: string): cstring =
  if menuTitle.len == 0: nil else: menuTitle.cstring

proc setMenuShortcut*(menuTitle: string, itemPrefix: string, key: string, withShift = false): bool =
  ## `menuTitle`: exact top-level menu title, or "" for the application
  ## menu (the one showing About/Quit). `itemPrefix`: matched against the
  ## start of each item's title in that menu (so "Quit" matches "Quit
  ## BubiX1turboZ"). `key`: a single lowercase character, e.g. "q".
  bx1MenuSetKeyEquivalentImpl(titleArg(menuTitle), itemPrefix.cstring, key.cstring, withShift.cint) != 0

proc setMenuItemTitle*(menuTitle: string, itemPrefix: string, newTitle: string): bool =
  bx1MenuSetTitleImpl(titleArg(menuTitle), itemPrefix.cstring, newTitle.cstring) != 0

proc setMenuItemEnabled*(menuTitle: string, itemPrefix: string, enabled: bool): bool =
  bx1MenuSetEnabledImpl(titleArg(menuTitle), itemPrefix.cstring, enabled.cint) != 0

proc disableAutoEnableAll*() =
  ## Must be called once, after the window carrying the menu bar has been
  ## shown (NSApp has no main menu before that) - see cocoamenu.m for why
  ## this exists. Call it unconditionally at startup, not just when
  ## setMenuItemEnabled is used: a broken NSApp modal session from any
  ## Open/Save dialog can disable every menu item in the app regardless
  ## of whether this app ever calls setMenuItemEnabled itself.
  bx1MenuDisableAutoenableAllImpl()
