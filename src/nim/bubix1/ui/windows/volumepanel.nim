## Win32 backend for ui/volumepanel.nim: a non-modal window of L/R
## trackbars (comctl32's "msctls_trackbar32"), one row per device plus the
## master, with a link checkbox and a Reset button above them - the same
## layout ui/linux/volumepanel.nim lays out with GTK widgets.
##
## Unlike a GTK range, a trackbar only ever posts WM_HSCROLL for a move the
## user actually made - TBM_SETPOS does not generate one - so there is no
## need for the "was this our own programmatic move" suppression flag the
## GTK backend carries.
##
## The window is created once, on the first `begin`: the caller builds this
## panel's whole device list a single time at startup (see the reasoning in
## bubix1turboz.nim next to where it calls this), so there is nothing here
## to rebuild it against a later `begin`.

import std/tables
import ./win32
import ./winshell

const
  ClassName = "BubiX1turboZVolumePanel"
  Margin = 12'i32
  RowH = 26'i32
  LabelW = 90'i32
  SliderW = 220'i32
  ValueW = 48'i32
  GroupGapTop = 10'i32
  VolMin = -40'i32
  VolMax = 0'i32

var
  panelHwnd: HWND
  onChange: proc (device, channel, value: cint) {.cdecl.}
  onLink: proc (linked: cint) {.cdecl.}
  onReset: proc () {.cdecl.}
  sliders: Table[(int32, int32), HWND]
  valueLabels: Table[(int32, int32), HWND]
  sliderKey: Table[HWND, (int32, int32)]
  levels: Table[(int32, int32), int32]
  linkCheckbox: HWND
  resetButton: HWND
  curY: int32
  nextCtrlId: int32 = 100

proc nextId(): int32 =
  result = nextCtrlId
  inc nextCtrlId

proc updateValueLabel(device, channel: int32) =
  let lbl = valueLabels.getOrDefault((device, channel))
  if lbl != nil:
    discard setWindowTextW(lbl, toWide($levels.getOrDefault((device, channel)) & " dB"))

proc addSliderRow(caption: string, device, channel: int32, y: int32) =
  discard createWindowExW(0, toWide("STATIC"), toWide(caption),
    WsChild or WsVisible or SsLeft, Margin, y + 4, LabelW, 18,
    panelHwnd, cast[HMENU](nextId()), getModuleHandleW(WideCString(nil)), nil)
  let slider = createWindowExW(0, toWide("msctls_trackbar32"), toWide(""),
    WsChild or WsVisible or TbsHorz or TbsAutoticks, Margin + LabelW, y,
    SliderW, RowH, panelHwnd, cast[HMENU](nextId()),
    getModuleHandleW(WideCString(nil)), nil)
  # TBM_SETRANGE packs MAKELONG(min, max): min in the low word, max in the
  # high. VolMin is negative, but a two's-complement 16-bit word carries
  # that correctly - the trackbar reads each word back as a signed SHORT.
  discard sendMessageW(slider, TbmSetrange, 1,
    LPARAM((VolMax.uint32 shl 16) or (VolMin.uint32 and 0xffff'u32)))
  discard sendMessageW(slider, TbmSetpos, 1, LPARAM(0))
  let label = createWindowExW(0, toWide("STATIC"), toWide("0 dB"),
    WsChild or WsVisible or SsLeft, Margin + LabelW + SliderW + 8, y + 4,
    ValueW, 18, panelHwnd, cast[HMENU](nextId()),
    getModuleHandleW(WideCString(nil)), nil)
  sliders[(device, channel)] = slider
  sliderKey[slider] = (device, channel)
  valueLabels[(device, channel)] = label
  levels[(device, channel)] = 0

proc wndProc(hwnd: HWND, msg: uint32, wParam: WPARAM,
            lParam: LPARAM): LRESULT {.stdcall.} =
  case msg
  of WmHscroll:
    let ctl = cast[HWND](cast[pointer](lParam))
    if sliderKey.hasKey(ctl):
      let (device, channel) = sliderKey[ctl]
      let pos = sendMessageW(ctl, TbmGetpos, 0, 0).int32
      levels[(device, channel)] = pos
      updateValueLabel(device, channel)
      if onChange != nil:
        onChange(device, channel, pos)
  of WmCommand:
    let ctl = cast[HWND](cast[pointer](lParam))
    if ctl == linkCheckbox:
      let checked = sendMessageW(linkCheckbox, BmGetcheck, 0, 0) == BstChecked.LRESULT
      if onLink != nil:
        onLink(if checked: 1 else: 0)
    elif ctl == resetButton:
      if onReset != nil:
        onReset()
  of WmClose:
    discard showWindow(hwnd, SwHide) # hidden, not destroyed - see hide()
    return 0
  else:
    return defWindowProcW(hwnd, msg, wParam, lParam)
  0

proc setCallbacks*(change: proc (device, channel, value: cint) {.cdecl.},
                   link: proc (linked: cint) {.cdecl.},
                   reset: proc () {.cdecl.}) =
  onChange = change
  onLink = link
  onReset = reset

proc begin*(title, masterTitle, linkLabel, resetLabel: cstring) =
  ensureCommonControls()
  winshell.registerWindowClass(ClassName, wndProc)
  if panelHwnd != nil:
    discard setWindowTextW(panelHwnd, toWide($title))
    return
  panelHwnd = createWindowExW(0, toWide(ClassName), toWide($title),
    WsCaption or WsSysmenu, 140, 140,
    Margin * 2 + LabelW + SliderW + ValueW + 24, 200,
    winshell.mainHwnd, nil, getModuleHandleW(WideCString(nil)), nil)
  curY = Margin
  addSliderRow($masterTitle, -1, 0, curY)
  curY += RowH + 6
  linkCheckbox = createWindowExW(0, toWide("BUTTON"), toWide($linkLabel),
    WsChild or WsVisible or BsAutocheckbox, Margin, curY, 150, 22,
    panelHwnd, cast[HMENU](nextId()), getModuleHandleW(WideCString(nil)), nil)
  resetButton = createWindowExW(0, toWide("BUTTON"), toWide($resetLabel),
    WsChild or WsVisible or BsPushbutton, Margin + 160, curY, 80, 24,
    panelHwnd, cast[HMENU](nextId()), getModuleHandleW(WideCString(nil)), nil)
  curY += RowH + GroupGapTop

proc addDevice*(device: cint, caption: cstring) =
  discard createWindowExW(0, toWide("STATIC"), toWide($caption),
    WsChild or WsVisible or SsLeft, Margin, curY, 300, 18,
    panelHwnd, cast[HMENU](nextId()), getModuleHandleW(WideCString(nil)), nil)
  curY += 20
  addSliderRow("L", device, 0, curY)
  curY += RowH
  addSliderRow("R", device, 1, curY)
  curY += RowH + GroupGapTop

proc finish*() =
  if panelHwnd == nil:
    return
  var client = Rect(left: 0, top: 0,
    right: Margin * 2 + LabelW + SliderW + ValueW + 24, bottom: curY + Margin)
  var wr = client
  # AdjustWindowRect isn't declared; the caption/border padding is a small,
  # fixed amount that setWindowPos below tolerates being slightly generous
  # about (a taller window than the content is harmless here).
  discard setWindowPos(panelHwnd, HwndTop, 0, 0,
    client.right + 16, client.bottom + 40, SwpNomove or SwpNoactivate)

proc setLevel*(device, channel, value: cint) =
  levels[(device.int32, channel.int32)] = value.int32
  let s = sliders.getOrDefault((device.int32, channel.int32))
  if s != nil:
    discard sendMessageW(s, TbmSetpos, 1, LPARAM(value))
    updateValueLabel(device.int32, channel.int32)

proc getLevel*(device, channel: cint): cint =
  levels.getOrDefault((device.int32, channel.int32))

proc setDeviceEnabled*(device, enabled: cint) =
  for channel in 0'i32 .. 1'i32:
    let s = sliders.getOrDefault((device.int32, channel))
    if s != nil:
      discard enableWindow(s, enabled)

proc setLinked*(linked: cint) =
  if linkCheckbox != nil:
    discard sendMessageW(linkCheckbox, BmSetcheck,
      (if linked != 0: BstChecked else: BstUnchecked).WPARAM, 0)

proc show*() =
  if panelHwnd != nil:
    discard showWindow(panelHwnd, SwShow)

proc hide*() =
  if panelHwnd != nil:
    discard showWindow(panelHwnd, SwHide)
