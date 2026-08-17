## AppKit backend for ui/volumepanel.nim. See volumepanel.m.

{.compile: "volumepanel.m".}
{.passL: "-framework Cocoa".}

proc setCallbacks*(change: proc (device, channel, value: cint) {.cdecl.},
                   link: proc (linked: cint) {.cdecl.},
                   reset: proc () {.cdecl.})
  {.importc: "bx1_volume_set_callbacks", cdecl.}
proc begin*(title, masterTitle, linkLabel, resetLabel: cstring)
  {.importc: "bx1_volume_begin", cdecl.}
proc addDevice*(device: cint, caption: cstring)
  {.importc: "bx1_volume_add_device", cdecl.}
proc finish*() {.importc: "bx1_volume_end", cdecl.}
proc setLevel*(device, channel, value: cint)
  {.importc: "bx1_volume_set_level", cdecl.}
proc getLevel*(device, channel: cint): cint
  {.importc: "bx1_volume_get_level", cdecl.}
proc setDeviceEnabled*(device, enabled: cint)
  {.importc: "bx1_volume_set_device_enabled", cdecl.}
proc setLinked*(linked: cint) {.importc: "bx1_volume_set_linked", cdecl.}
proc show*() {.importc: "bx1_volume_show", cdecl.}
proc hide*() {.importc: "bx1_volume_hide", cdecl.}
