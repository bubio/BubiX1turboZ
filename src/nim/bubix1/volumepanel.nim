## The Host > Volume panel: per-device L/R sliders, a master, and a link
## switch. See volumepanel.m for the AppKit side.
##
## The panel holds no mixing rules of its own. It reports what the user did
## and displays what it is told, so the decisions that need to see the VM -
## how the master is folded in, which channels this machine actually has,
## what gets written to config.ini - all stay with the caller.
##
## ```nim
## volumepanel.setOnChange(proc (device, channel, value: int) = ...)
## volumepanel.begin(tr(msgVolume), tr(msgVolumeMaster), ...)
## for i in devices: volumepanel.addDevice(i, caption(i))
## volumepanel.finish()
## ```

{.compile: "volumepanel.m".}
{.passL: "-framework Cocoa".}

type
  ChangeProc* = proc (device, channel, value: int) {.closure.}
    ## `device` is the core's sound device index, or `Master`. `channel` is
    ## `ChannelL` or `ChannelR`, and is always `ChannelL` for the master.
  LinkProc* = proc (linked: bool) {.closure.}
  ResetProc* = proc () {.closure.}

const
  Master* = -1
  ChannelL* = 0
  ChannelR* = 1

proc bx1VolumeSetCallbacks(change: proc (device, channel, value: cint) {.cdecl.},
                           link: proc (linked: cint) {.cdecl.},
                           reset: proc () {.cdecl.})
  {.importc: "bx1_volume_set_callbacks", cdecl.}
proc bx1VolumeBegin(title, masterTitle, linkLabel, resetLabel: cstring)
  {.importc: "bx1_volume_begin", cdecl.}
proc bx1VolumeAddDevice(device: cint, caption: cstring)
  {.importc: "bx1_volume_add_device", cdecl.}
proc bx1VolumeEnd() {.importc: "bx1_volume_end", cdecl.}
proc bx1VolumeSetLevel(device, channel, value: cint)
  {.importc: "bx1_volume_set_level", cdecl.}
proc bx1VolumeGetLevel(device, channel: cint): cint
  {.importc: "bx1_volume_get_level", cdecl.}
proc bx1VolumeSetDeviceEnabled(device, enabled: cint)
  {.importc: "bx1_volume_set_device_enabled", cdecl.}
proc bx1VolumeSetLinked(linked: cint) {.importc: "bx1_volume_set_linked", cdecl.}
proc bx1VolumeShow() {.importc: "bx1_volume_show", cdecl.}
proc bx1VolumeHide() {.importc: "bx1_volume_hide", cdecl.}

# Module-level for the reason nativemenu.nim keeps its action table here: a
# Nim closure is a two-word value that cannot be round-tripped through the
# single function pointer AppKit calls back on.
var
  changeHandler: ChangeProc
  linkHandler: LinkProc
  resetHandler: ResetProc

proc setOnChange*(p: ChangeProc) =
  ## Called when the user moves a slider, with the value it settled on.
  changeHandler = p

proc setOnLink*(p: LinkProc) =
  ## Called when the user switches the L/R link.
  linkHandler = p

proc setOnReset*(p: ResetProc) =
  ## Called when the user clicks Reset.
  resetHandler = p

proc dispatchChange(device, channel, value: cint) {.cdecl.} =
  if changeHandler != nil:
    changeHandler(device.int, channel.int, value.int)

proc dispatchLink(linked: cint) {.cdecl.} =
  if linkHandler != nil:
    linkHandler(linked != 0)

proc dispatchReset() {.cdecl.} =
  if resetHandler != nil:
    resetHandler()

proc begin*(title, masterTitle, linkLabel, resetLabel: string) =
  ## Creates the window and the master group. Devices are added after this,
  ## and `finish` lays the whole thing out.
  bx1VolumeSetCallbacks(dispatchChange, dispatchLink, dispatchReset)
  bx1VolumeBegin(title.cstring, masterTitle.cstring, linkLabel.cstring,
                 resetLabel.cstring)

proc addDevice*(device: int, caption: string) =
  ## Appends one device's group, below the ones already added.
  bx1VolumeAddDevice(device.cint, caption.cstring)

proc finish*() =
  ## Lays out every group added so far and sizes the window to them.
  bx1VolumeEnd()

proc setLevel*(device, channel, value: int) =
  bx1VolumeSetLevel(device.cint, channel.cint, value.cint)

proc level*(device, channel: int): int =
  bx1VolumeGetLevel(device.cint, channel.cint).int

proc setDeviceEnabled*(device: int, enabled: bool) =
  bx1VolumeSetDeviceEnabled(device.cint, enabled.cint)

proc setLinked*(linked: bool) =
  bx1VolumeSetLinked(linked.cint)

proc show*() = bx1VolumeShow()
proc hide*() = bx1VolumeHide()
