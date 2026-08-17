## The Host > Volume panel: per-device L/R sliders, a master, and a link
## switch.
##
## The panel holds no mixing rules of its own. It reports what the user did
## and displays what it is told, so the decisions that need to see the VM -
## how the master is folded in, which channels this machine actually has,
## what gets written to config.ini - all stay with the caller.
##
## It is also where the current levels live: the caller reads them back out
## with `level` to drive the core, rather than keeping a copy.
##
## ```nim
## volumepanel.setOnChange(proc (device, channel, value: int) = ...)
## volumepanel.begin(tr(msgVolume), tr(msgVolumeMaster), ...)
## for i in devices: volumepanel.addDevice(i, caption(i))
## volumepanel.finish()
## ```

when defined(macosx):
  from ./macos/volumepanel as backend import nil
else:
  from ./stub/volumepanel as backend import nil

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

# Module-level for the reason nativemenu.nim keeps its action table here: a
# Nim closure is a two-word value that cannot be round-tripped through the
# single function pointer a backend calls back on.
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
  backend.setCallbacks(dispatchChange, dispatchLink, dispatchReset)
  backend.begin(title.cstring, masterTitle.cstring, linkLabel.cstring,
                resetLabel.cstring)

proc addDevice*(device: int, caption: string) =
  ## Appends one device's group, below the ones already added.
  backend.addDevice(device.cint, caption.cstring)

proc finish*() =
  ## Lays out every group added so far and sizes the window to them.
  backend.finish()

proc setLevel*(device, channel, value: int) =
  backend.setLevel(device.cint, channel.cint, value.cint)

proc level*(device, channel: int): int =
  backend.getLevel(device.cint, channel.cint).int

proc setDeviceEnabled*(device: int, enabled: bool) =
  backend.setDeviceEnabled(device.cint, enabled.cint)

proc setLinked*(linked: bool) =
  backend.setLinked(linked.cint)

proc show*() = backend.show()
proc hide*() = backend.hide()
