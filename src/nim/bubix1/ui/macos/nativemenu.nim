## AppKit backend for ui/nativemenu.nim. See nativemenu.m.
##
## Menus are opaque `pointer`s (`NSMenu *`) as far as the facade is
## concerned, and items are addressed by the integer tag the facade
## allocated for them - which is also what the single Objective-C target
## hands back when one is clicked.

{.compile: "nativemenu.m".}
{.passL: "-framework Cocoa".}

proc setAction*(fn: proc (tag: cint) {.cdecl.})
  {.importc: "bx1_nmenu_set_action", cdecl.}
proc installMenubar*(appName: cstring): pointer
  {.importc: "bx1_nmenu_install_menubar", cdecl.}
proc addStandardItem*(menu: pointer, title: cstring, which: cint,
                      key: cstring, mods: cint)
  {.importc: "bx1_nmenu_add_standard_item", cdecl.}
proc addToplevel*(title: cstring): pointer
  {.importc: "bx1_nmenu_add_toplevel", cdecl.}
proc addSubmenu*(parent: pointer, title: cstring): pointer
  {.importc: "bx1_nmenu_add_submenu", cdecl.}
proc addItem*(menu: pointer, title: cstring, tag: cint, key: cstring, mods: cint)
  {.importc: "bx1_nmenu_add_item", cdecl.}
proc addSeparator*(menu: pointer, tag: cint)
  {.importc: "bx1_nmenu_add_separator", cdecl.}
proc setHidden*(tag: cint, hidden: cint) {.importc: "bx1_nmenu_set_hidden", cdecl.}
proc setChecked*(tag: cint, checked: cint) {.importc: "bx1_nmenu_set_checked", cdecl.}
proc getChecked*(tag: cint): cint {.importc: "bx1_nmenu_get_checked", cdecl.}
proc setEnabled*(tag: cint, enabled: cint) {.importc: "bx1_nmenu_set_enabled", cdecl.}
proc setItemTitle*(tag: cint, title: cstring)
  {.importc: "bx1_nmenu_set_item_title", cdecl.}
