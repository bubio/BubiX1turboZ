## Menu bar construction on top of AppKit directly, for the nesting that
## uing/libui-ng cannot express. See nativemenu.m for why this is needed.
##
## Usage: build menus after the uing window carrying the menu bar has been
## shown (NSApp has no main menu before that), then let the main loop run.
## Actions are ordinary Nim closures:
##
## ```nim
## let control = addMenu("Control")
## control.addItem("Reset", proc () = bx1Reset(h))
## let save = control.addSubmenu("Save State")
## for i in 0 .. 9:
##   save.addItem("State " & $i, makeSaveAction(i))
## ```
##
## Every item is registered with an integer tag and one shared Objective-C
## target; this module keeps the tag -> closure table. That means a `for`
## loop can add items directly without the `makeXxxAction(i)` dance
## DevelopmentPlan phase 7 documents, since the closure is stored per tag
## rather than captured per item - but note the loop variable still has to
## be bound freshly if the closure reads it, so the pattern above stays the
## safe habit.

import std/tables

{.compile: "nativemenu.m".}
{.passL: "-framework Cocoa".}

type
  Menu* = object
    ## An NSMenu. Zero value (`handle == nil`) is a valid no-op menu, which
    ## is what every operation degrades to if the menu bar is not up yet.
    handle: pointer

  MenuAction* = proc () {.closure.}

  MenuItemRef* = object
    ## A handle for changing an item after creation (check state, enabled
    ## state, title). Cheap to copy.
    tag*: cint

proc bx1NmenuSetAction(fn: proc (tag: cint) {.cdecl.})
  {.importc: "bx1_nmenu_set_action", cdecl.}
proc bx1NmenuAddToplevel(title: cstring): pointer
  {.importc: "bx1_nmenu_add_toplevel", cdecl.}
proc bx1NmenuAddSubmenu(parent: pointer, title: cstring): pointer
  {.importc: "bx1_nmenu_add_submenu", cdecl.}
proc bx1NmenuAddItem(menu: pointer, title: cstring, tag: cint, key: cstring, mods: cint)
  {.importc: "bx1_nmenu_add_item", cdecl.}
proc bx1NmenuAddSeparator(menu: pointer) {.importc: "bx1_nmenu_add_separator", cdecl.}
proc bx1NmenuSetChecked(tag: cint, checked: cint) {.importc: "bx1_nmenu_set_checked", cdecl.}
proc bx1NmenuGetChecked(tag: cint): cint {.importc: "bx1_nmenu_get_checked", cdecl.}
proc bx1NmenuSetEnabled(tag: cint, enabled: cint) {.importc: "bx1_nmenu_set_enabled", cdecl.}
proc bx1NmenuSetItemTitle(tag: cint, title: cstring)
  {.importc: "bx1_nmenu_set_item_title", cdecl.}

const
  ModCommand* = 1'i32
  ModShift* = 2'i32
  ModOption* = 4'i32
  ModControl* = 8'i32

# Module-level rather than passed through AppKit's `representedObject`: a
# Nim closure is a two-word value (proc + environment) that cannot be
# round-tripped through a single Objective-C pointer without manual GC
# rooting, and the table keeps the environment reachable for free.
var actions: Table[cint, MenuAction]
var nextTag: cint = 1
var installed = false

proc dispatch(tag: cint) {.cdecl.} =
  ## The single entry point every menu click arrives through.
  let a = actions.getOrDefault(tag)
  if a != nil:
    a()

proc ensureInstalled() =
  if not installed:
    bx1NmenuSetAction(dispatch)
    installed = true

proc addMenu*(title: string): Menu =
  ## Appends a new top-level menu to the menu bar, after whatever
  ## uing/libui-ng already put there (which includes the application menu).
  ensureInstalled()
  Menu(handle: bx1NmenuAddToplevel(title.cstring))

proc addSubmenu*(parent: Menu, title: string): Menu =
  ensureInstalled()
  if parent.handle == nil:
    return Menu(handle: nil)
  Menu(handle: bx1NmenuAddSubmenu(parent.handle, title.cstring))

proc addItem*(menu: Menu, title: string, action: MenuAction = nil,
              key = "", mods = ModCommand): MenuItemRef {.discardable.} =
  ## `key` is a single character for a Cmd-key equivalent, or "" for none.
  ## `mods` is ignored when `key` is empty.
  ensureInstalled()
  result = MenuItemRef(tag: nextTag)
  inc nextTag
  if action != nil:
    actions[result.tag] = action
  if menu.handle != nil:
    bx1NmenuAddItem(menu.handle, title.cstring, result.tag, key.cstring, mods.cint)

proc setAction*(item: MenuItemRef, action: MenuAction) =
  ## Replaces (or supplies) an item's action after creation. Needed for a
  ## self-toggling check item, whose closure has to refer to the item it is
  ## attached to - which does not exist yet while `addItem` is running.
  actions[item.tag] = action

proc addSeparator*(menu: Menu) =
  if menu.handle != nil:
    bx1NmenuAddSeparator(menu.handle)

proc `checked=`*(item: MenuItemRef, value: bool) =
  bx1NmenuSetChecked(item.tag, value.cint)

proc checked*(item: MenuItemRef): bool =
  bx1NmenuGetChecked(item.tag) != 0

proc `enabled=`*(item: MenuItemRef, value: bool) =
  bx1NmenuSetEnabled(item.tag, value.cint)

proc `title=`*(item: MenuItemRef, value: string) =
  bx1NmenuSetItemTitle(item.tag, value.cstring)
