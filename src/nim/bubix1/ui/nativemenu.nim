## Menu bar construction on top of the host's own menu API.
##
## Usage: `installMenuBar` once the windowing system is up (SDL brings it
## up), then build the menus. Actions are ordinary Nim closures:
##
## ```nim
## let appMenu = installMenuBar("BubiX1turboZ")
## appMenu.addItem("About BubiX1turboZ", proc () = showAbout())
## let control = addMenu("Control")
## control.addItem("Reset", proc () = bx1Reset(h))
## let save = control.addSubmenu("Save State")
## for i in 0 .. 9:
##   save.addItem("State " & $i, makeSaveAction(i))
## ```
##
## Every item is registered with an integer tag and one shared callback;
## this module keeps the tag -> closure table, and a backend never sees a
## closure. That means a `for` loop can add items directly without the
## `makeXxxAction(i)` dance DevelopmentPlan phase 7 documents, since the
## closure is stored per tag rather than captured per item - but note the
## loop variable still has to be bound freshly if the closure reads it, so
## the pattern above stays the safe habit.
##
## Two pieces of this interface are shaped by macOS rather than by menus
## in general, and are the ones a second backend has to decide about:
## `installMenuBar` returns an *application menu* to hang About and Quit
## off, and `StandardItem` names items whose behaviour belongs to AppKit.
## A platform with neither can return an ordinary menu from the first and
## ignore the second (which is what `stub/` does), at the cost of the call
## site in bubix1turboz.nim putting Quit somewhere that platform would
## not.

import std/tables

when defined(macosx):
  from ./macos/nativemenu as backend import nil
elif defined(linux):
  from ./linux/nativemenu as backend import nil
elif defined(windows):
  from ./windows/nativemenu as backend import nil
else:
  from ./stub/nativemenu as backend import nil

const
  hostOwnsStandardItems = defined(macosx)
    ## Whether `addStandardItem` actually puts something in the menu on this
    ## platform. Only AppKit owns Services/Hide/Show All; every other
    ## backend's `addStandardItem` is a no-op (see e.g.
    ## windows/nativemenu.nim), so a call site that always brackets a run of
    ## standard items with separators - the application menu in
    ## bubix1turboz.nim does, since it is written once for every platform -
    ## would otherwise leave two empty separators back to back wherever
    ## those items vanish.

type
  Menu* = object
    ## One menu. Zero value (`handle == nil`) is a valid no-op menu, which
    ## is what every operation degrades to if the menu bar is not up yet -
    ## and what a platform with no backend gets for all of them.
    handle: pointer

  MenuAction* = proc () {.closure.}

  MenuItemRef* = object
    ## A handle for changing an item after creation (check state, enabled
    ## state, title). Cheap to copy.
    tag*: cint

const
  ModCommand* = 1'i32
    ## The platform's primary accelerator modifier: Command on macOS,
    ## Control where there is no Command key.
  ModShift* = 2'i32
  ModOption* = 4'i32
    ## Option on macOS, Alt elsewhere.
  ModControl* = 8'i32
    ## Control as a modifier in its own right, distinct from `ModCommand`
    ## on the platform where the two differ.

# Module-level rather than passed through the backend: a Nim closure is a
# two-word value (proc + environment) that cannot be round-tripped through
# the single pointer a C callback carries without manual GC rooting, and
# the table keeps the environment reachable for free.
var actions: Table[cint, MenuAction]
var nextTag: cint = 1
var installed = false

type TailKind = enum tkEmpty, tkSeparator, tkOther
  ## What the last thing appended to a given menu was, so `addSeparator`
  ## can drop one that would be redundant (leading, or immediately after
  ## another separator) instead of asking every call site to know whether
  ## the item(s) it is bracketing actually rendered on this platform.

var menuTail: Table[pointer, TailKind]

proc markAppended(menu: Menu) =
  if menu.handle != nil:
    menuTail[menu.handle] = tkOther

proc dispatch(tag: cint) {.cdecl.} =
  ## The single entry point every menu click arrives through.
  let a = actions.getOrDefault(tag)
  if a != nil:
    a()

proc ensureInstalled() =
  if not installed:
    backend.setAction(dispatch)
    installed = true

type StandardItem* = enum
  ## Items whose behaviour is the host's own rather than this app's.
  siServices, siHide, siHideOthers, siShowAll

proc installMenuBar*(appName: string): Menu =
  ## Replaces the application's menu bar with an empty one and returns the
  ## application menu at the head of it. Everything else is appended after
  ## that menu, so this has to come first.
  ensureInstalled()
  result = Menu(handle: backend.installMenubar(appName.cstring))
  if result.handle != nil:
    menuTail[result.handle] = tkEmpty

proc addStandardItem*(menu: Menu, title: string, which: StandardItem,
                      key = "", mods = ModCommand) =
  ## Appends an item the host acts on itself (Services, Hide, Show All).
  ensureInstalled()
  if menu.handle != nil:
    backend.addStandardItem(menu.handle, title.cstring, which.cint,
                            key.cstring, mods.cint)
    if hostOwnsStandardItems:
      markAppended(menu)

proc addMenu*(title: string): Menu =
  ## Appends a new top-level menu to the menu bar, after the application
  ## menu `installMenuBar` put there.
  ensureInstalled()
  result = Menu(handle: backend.addToplevel(title.cstring))
  if result.handle != nil:
    menuTail[result.handle] = tkEmpty

proc addSubmenu*(parent: Menu, title: string): Menu =
  ensureInstalled()
  if parent.handle == nil:
    return Menu(handle: nil)
  markAppended(parent)
  result = Menu(handle: backend.addSubmenu(parent.handle, title.cstring))
  if result.handle != nil:
    menuTail[result.handle] = tkEmpty

proc addItem*(menu: Menu, title: string, action: MenuAction = nil,
              key = "", mods = ModCommand): MenuItemRef {.discardable.} =
  ## `key` is a single character for a keyboard equivalent, or "" for
  ## none. `mods` is ignored when `key` is empty.
  ensureInstalled()
  result = MenuItemRef(tag: nextTag)
  inc nextTag
  if action != nil:
    actions[result.tag] = action
  if menu.handle != nil:
    backend.addItem(menu.handle, title.cstring, result.tag, key.cstring, mods.cint)
    markAppended(menu)

proc setAction*(item: MenuItemRef, action: MenuAction) =
  ## Replaces (or supplies) an item's action after creation. Needed for a
  ## self-toggling check item, whose closure has to refer to the item it is
  ## attached to - which does not exist yet while `addItem` is running.
  actions[item.tag] = action

proc addSeparator*(menu: Menu): MenuItemRef {.discardable.} =
  ## The returned handle only matters for a separator that has to be hidden
  ## along with an optional section below it.
  ##
  ## Dropped (never reaches the backend) if the menu is still empty or the
  ## last thing appended was itself a separator - which happens whenever a
  ## call site brackets a platform-only run of items (`addStandardItem`'s
  ## Services/Hide/Show All, real only on macOS) with separators on both
  ## sides, and that platform is one where the run added nothing. The
  ## returned ref is a harmless no-op tag in that case: nothing ever
  ## registers it, so `hidden=`/etc. on it do nothing.
  ensureInstalled()
  result = MenuItemRef(tag: nextTag)
  inc nextTag
  if menu.handle != nil and menuTail.getOrDefault(menu.handle, tkOther) == tkOther:
    backend.addSeparator(menu.handle, result.tag)
    menuTail[menu.handle] = tkSeparator

proc `hidden=`*(item: MenuItemRef, value: bool) =
  ## Hidden items collapse out of the menu entirely, which is how the
  ## original app presents its optional sections (the D88 bank list and the
  ## recent-file entries are simply absent when they do not apply).
  backend.setHidden(item.tag, value.cint)

proc `checked=`*(item: MenuItemRef, value: bool) =
  backend.setChecked(item.tag, value.cint)

proc checked*(item: MenuItemRef): bool =
  backend.getChecked(item.tag) != 0

proc `enabled=`*(item: MenuItemRef, value: bool) =
  backend.setEnabled(item.tag, value.cint)

proc `title=`*(item: MenuItemRef, value: string) =
  backend.setItemTitle(item.tag, value.cstring)

proc handleAccelerator*(ch: char, ctrl, shift, alt, gui: bool): bool =
  ## Offers a key press to the menu bar's keyboard equivalents, ahead of
  ## whatever else the application would do with it. True if an item took
  ## it, in which case the key press is spent and must go no further.
  ##
  ## Needed because not every host delivers key presses to its menus by
  ## itself: on macOS AppKit fires an equivalent before the application
  ## ever sees the event and this is a no-op, while on Linux the keyboard
  ## focus belongs to the SDL window and the menu bar depends on this call
  ## entirely. The modifier flags are the ones physically held down, so
  ## the call site needs to know nothing about which of them a host uses
  ## for its menus.
  backend.handleAccelerator(ch.cint, ctrl.cint, shift.cint, alt.cint,
                            gui.cint) != 0
