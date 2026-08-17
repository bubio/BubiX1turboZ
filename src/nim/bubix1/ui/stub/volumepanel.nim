## Does-nothing volume panel for the platforms without a backend yet.
##
## Levels are stored rather than discarded. The panel is where this
## application keeps the mixer's current position - it reads levels back
## out of it to drive the core (see the Host > Volume section of
## bubix1turboz.nim) - so a backend that forgot them would silence every
## device, not merely hide a window.

import std/tables

var levels: Table[(cint, cint), cint]

proc setCallbacks*(change: proc (device, channel, value: cint) {.cdecl.},
                   link: proc (linked: cint) {.cdecl.},
                   reset: proc () {.cdecl.}) = discard
proc begin*(title, masterTitle, linkLabel, resetLabel: cstring) = discard
proc addDevice*(device: cint, caption: cstring) = discard
proc finish*() = discard
proc setLevel*(device, channel, value: cint) = levels[(device, channel)] = value
proc getLevel*(device, channel: cint): cint = levels.getOrDefault((device, channel))
proc setDeviceEnabled*(device, enabled: cint) = discard
proc setLinked*(linked: cint) = discard
proc show*() = discard
proc hide*() = discard
