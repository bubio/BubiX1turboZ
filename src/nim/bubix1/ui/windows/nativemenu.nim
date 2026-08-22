## Win32 backend for ui/nativemenu.nim: a native menu bar attached to the
## SDL window itself (`SetMenu`, done in hostwindow.present once the window
## exists - installMenubar below runs earlier and only builds the HMENU
## tree, mirroring the order the facade actually calls things in).
##
## Win32 has no notion of a menu item that is present but hidden the way a
## GTK widget can be hidden in place (ui/linux/nativemenu.nim): a `HMENU`
## only ever holds the items actually appended to it. So this module keeps
## its own ordered record of every item a menu logically has - including
## the hidden ones - and rebuilds the live `HMENU` from that record on any
## change to which items are visible. Checked/enabled/title changes on an
## item already showing are cheaper: those go straight to the live menu.
##
## Keyboard equivalents are shown as a "\tCtrl+R"-style suffix on the label
## (the standard Win32 convention) but are matched the same way as on
## Linux: SDL owns keyboard focus, so nothing here ever runs through a real
## Win32 accelerator table, and `handleAccelerator` is offered every key
## press the application's event loop sees, ahead of the guest machine.

import std/[tables, strutils]
import ./win32
import ./winshell

type
  ItemKind = enum ikItem, ikSeparator, ikSubmenu

  ItemRec = object
    parent: HMENU
    kind: ItemKind
    title: string
    accel: string       ## "\tCtrl+R", or "" - ikItem only
    submenu: HMENU       ## ikSubmenu only
    checked: bool
    enabled: bool
    hidden: bool

const
  BitCommand = 1'i32
  BitShift = 2'i32
  BitOption = 4'i32
  BitControl = 8'i32

proc hasCtrl(mods: cint): bool = (mods and BitCommand) != 0 or (mods and BitControl) != 0
proc hasShift(mods: cint): bool = (mods and BitShift) != 0
proc hasAlt(mods: cint): bool = (mods and BitOption) != 0

var
  actionFn: proc (tag: cint) {.cdecl.}
  items: Table[cint, ItemRec]
  childOrder: Table[HMENU, seq[cint]]
  accelTable: Table[(char, bool, bool, bool), cint]
  subCounter: cint = -1  ## Negative, so it can never collide with a
                         ## facade-issued (always positive) item/separator tag.

proc nextSubTag(): cint =
  result = subCounter
  dec subCounter

proc dispatch(tag: cint) {.cdecl.} =
  if actionFn != nil:
    actionFn(tag)

proc setAction*(fn: proc (tag: cint) {.cdecl.}) =
  actionFn = fn
  winshell.commandHandler = dispatch

proc displayTitle(rec: ItemRec): string = rec.title & rec.accel

proc rebuild(menu: HMENU) =
  ## Repopulates `menu` from `childOrder[menu]`, in logical order, skipping
  ## hidden items. Cheap, and only visible the next time the menu opens.
  while getMenuItemCount(menu) > 0:
    discard removeMenu(menu, 0, MfByposition)
  for tag in childOrder.getOrDefault(menu):
    let rec = items[tag]
    if rec.hidden:
      continue
    case rec.kind
    of ikSeparator:
      discard appendMenuW(menu, MfSeparator, tag.uint, WideCString(nil))
    of ikSubmenu:
      discard appendMenuW(menu, MfString or MfPopup, cast[uint](rec.submenu),
                          toWide(rec.title))
    of ikItem:
      var flags = MfString
      if rec.checked: flags = flags or MfChecked
      if not rec.enabled: flags = flags or MfGrayed
      discard appendMenuW(menu, flags, tag.uint, toWide(displayTitle(rec)))
  if menu == winshell.menuBar and winshell.mainHwnd != nil:
    discard drawMenuBar(winshell.mainHwnd)

proc newToplevel(title: string): HMENU =
  result = createPopupMenu()
  childOrder[result] = @[]
  let tag = nextSubTag()
  items[tag] = ItemRec(parent: winshell.menuBar, kind: ikSubmenu,
                       title: title, submenu: result, enabled: true)
  childOrder[winshell.menuBar].add tag
  rebuild(winshell.menuBar)

proc installMenubar*(appName: cstring): pointer =
  ## The application menu at the head of the bar. Unlike macOS this has no
  ## host-owned items (About/Quit are this app's own, added by the caller,
  ## same as on Linux); the menu bar object itself is created here.
  if winshell.menuBar == nil:
    winshell.menuBar = createMenu()
    childOrder[winshell.menuBar] = @[]
  newToplevel($appName)

proc addStandardItem*(menu: pointer, title: cstring, which: cint,
                      key: cstring, mods: cint) =
  ## Services / Hide / Show All are macOS' own; there is nothing to add here.
  discard

proc addToplevel*(title: cstring): pointer =
  newToplevel($title)

proc addSubmenu*(parent: pointer, title: cstring): pointer =
  if parent == nil:
    return nil
  let p = cast[HMENU](parent)
  let sub = createPopupMenu()
  childOrder[sub] = @[]
  let tag = nextSubTag()
  items[tag] = ItemRec(parent: p, kind: ikSubmenu, title: $title,
                       submenu: sub, enabled: true)
  childOrder[p].add tag
  rebuild(p)
  sub

proc accelSuffix(key: string, mods: cint): string =
  if key.len == 0:
    return ""
  var parts: seq[string]
  if hasCtrl(mods): parts.add "Ctrl"
  if hasShift(mods): parts.add "Shift"
  if hasAlt(mods): parts.add "Alt"
  if parts.len == 0: parts.add "Ctrl" # ModCommand alone still means Ctrl here
  parts.add key.toUpperAscii()
  "\t" & parts.join("+")

proc addItem*(menu: pointer, title: cstring, tag: cint, key: cstring, mods: cint) =
  if menu == nil:
    return
  let m = cast[HMENU](menu)
  let keyStr = $key
  items[tag] = ItemRec(parent: m, kind: ikItem, title: $title,
                       accel: accelSuffix(keyStr, mods), enabled: true)
  childOrder.mgetOrPut(m, @[]).add tag
  if keyStr.len > 0:
    accelTable[(toLowerAscii(keyStr[0]), hasCtrl(mods), hasShift(mods),
               hasAlt(mods))] = tag
  rebuild(m)

proc addSeparator*(menu: pointer, tag: cint) =
  if menu == nil:
    return
  let m = cast[HMENU](menu)
  items[tag] = ItemRec(parent: m, kind: ikSeparator)
  childOrder.mgetOrPut(m, @[]).add tag
  rebuild(m)

proc setHidden*(tag: cint, hidden: cint) =
  if tag notin items:
    return
  let want = hidden != 0
  if items[tag].hidden == want:
    return
  items[tag].hidden = want
  rebuild(items[tag].parent)

proc setChecked*(tag: cint, checked: cint) =
  if tag notin items:
    return
  items[tag].checked = checked != 0
  let rec = items[tag]
  if not rec.hidden and rec.parent != nil:
    discard checkMenuItem(rec.parent, tag.uint32,
      MfBycommand or (if rec.checked: MfChecked else: MfUnchecked))

proc getChecked*(tag: cint): cint =
  if tag in items and items[tag].checked: 1 else: 0

proc setEnabled*(tag: cint, enabled: cint) =
  if tag notin items:
    return
  items[tag].enabled = enabled != 0
  let rec = items[tag]
  if not rec.hidden and rec.parent != nil:
    discard enableMenuItem(rec.parent, tag.uint32,
      MfBycommand or (if rec.enabled: MfEnabled else: MfGrayed))

proc setItemTitle*(tag: cint, title: cstring) =
  if tag notin items:
    return
  items[tag].title = $title
  let rec = items[tag]
  if not rec.hidden and rec.parent != nil:
    var flags = MfBycommand or MfString
    if rec.checked: flags = flags or MfChecked
    if not rec.enabled: flags = flags or MfGrayed
    discard modifyMenuW(rec.parent, tag.uint32, flags, tag.uint,
                        toWide(displayTitle(rec)))

proc handleAccelerator*(key: cint, ctrl, shift, alt, gui: cint): cint =
  ## Matched against the key table `addItem` filled, exactly as Linux does
  ## it and for the same reason: keyboard focus belongs to the SDL window,
  ## so no Win32 accelerator table ever sees these key presses on its own.
  ##
  ## `gui` (a Windows-key combination) is accepted only as "not held": that
  ## belongs to the desktop, not to this app's menus.
  if key <= 0 or key > 0x7f or gui != 0:
    return 0
  if ctrl == 0 and shift == 0 and alt == 0:
    return 0 # a bare key press is the guest's
  let k = toLowerAscii(char(key))
  let tag = accelTable.getOrDefault((k, ctrl != 0, shift != 0, alt != 0), 0.cint)
  if tag == 0 or tag notin items:
    return 0
  let rec = items[tag]
  if rec.hidden or not rec.enabled:
    return 0
  if actionFn != nil:
    actionFn(tag)
  1
