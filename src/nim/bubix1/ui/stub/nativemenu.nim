## Does-nothing menu bar for the platforms without a backend yet.
##
## Every menu is the null pointer, which the facade already treats as "no
## menu bar is up" - so the application builds its whole menu tree, gets
## no menu bar, and runs. Item state is accepted and forgotten.

proc setAction*(fn: proc (tag: cint) {.cdecl.}) = discard
proc installMenubar*(appName: cstring): pointer = nil
proc addStandardItem*(menu: pointer, title: cstring, which: cint,
                      key: cstring, mods: cint) = discard
proc addToplevel*(title: cstring): pointer = nil
proc addSubmenu*(parent: pointer, title: cstring): pointer = nil
proc addItem*(menu: pointer, title: cstring, tag: cint, key: cstring,
              mods: cint) = discard
proc addSeparator*(menu: pointer, tag: cint) = discard
proc setHidden*(tag: cint, hidden: cint) = discard
proc setChecked*(tag: cint, checked: cint) = discard
proc getChecked*(tag: cint): cint = 0
proc setEnabled*(tag: cint, enabled: cint) = discard
proc setItemTitle*(tag: cint, title: cstring) = discard
proc handleAccelerator*(key: cint, ctrl, shift, alt, gui: cint): cint = 0
