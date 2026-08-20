## GTK backend for ui/volumepanel.nim: a non-modal window of L/R sliders.
##
## The panel keeps the current levels (the caller reads them back to drive the
## core) and reports each move through the single change callback. Levels are
## whole decibels from -40 (silent) to 0 (full), the range the caller clamps
## to. Programmatic moves - the link copying one channel to the other, Reset
## zeroing everything - must not be mistaken for the user's, so they are made
## with the change signal suppressed.

import std/tables
import ./gtk3
import ./gtkshell

const
  VolMin = -40.0
  VolMax = 0.0

var
  onChange: proc (device, channel, value: cint) {.cdecl.}
  onLink: proc (linked: cint) {.cdecl.}
  onReset: proc () {.cdecl.}
  window: GtkWidget
  box: GtkWidget                       ## the vertical stack of groups
  sliders: Table[(cint, cint), GtkWidget]
  levels: Table[(cint, cint), cint]
  linkToggle: GtkWidget
  suppress = false

proc encode(device, channel: cint): Gpointer =
  ## device (>= -1) and channel (0/1) packed into one callback argument.
  cast[Gpointer](cast[int](((device + 1) shl 1) or channel))

proc onSliderChanged(range: GtkWidget, data: Gpointer) {.cdecl.} =
  if suppress:
    return
  let code = cast[int](data)
  let device = cint((code shr 1) - 1)
  let channel = cint(code and 1)
  let value = cint(gtk_range_get_value(range))
  levels[(device, channel)] = value
  if onChange != nil:
    onChange(device, channel, value)

proc onLinkToggled(toggle: GtkWidget, data: Gpointer) {.cdecl.} =
  if suppress: return
  if onLink != nil:
    onLink(gtk_toggle_button_get_active(toggle))

proc onResetClicked(button: GtkWidget, data: Gpointer) {.cdecl.} =
  if onReset != nil:
    onReset()

proc onDeleteHide(widget: GtkWidget, event, data: Gpointer): Gboolean {.cdecl.} =
  ## Closing the panel hides it rather than destroying it - the caller reads
  ## levels out of it for the rest of the run.
  gtk_widget_hide(window)
  1

proc makeSlider(device, channel: cint): GtkWidget =
  let s = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, VolMin, VolMax, 1.0)
  gtk_scale_set_draw_value(s, 1)
  gtk_scale_set_digits(s, 0)
  gtk_widget_set_size_request(s, 220, -1)
  sliders[(device, channel)] = s
  levels[(device, channel)] = 0
  connect(s, "value-changed", cast[GCallback](onSliderChanged),
          encode(device, channel))
  s

proc addRow(caption: cstring, s: GtkWidget) =
  let row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8)
  let lbl = gtk_label_new(caption)
  gtk_widget_set_size_request(lbl, 90, -1)
  gtk_box_pack_start(row, lbl, 0, 0, 0)
  gtk_box_pack_start(row, s, 1, 1, 0)
  gtk_box_pack_start(box, row, 0, 0, 0)

proc setCallbacks*(change: proc (device, channel, value: cint) {.cdecl.},
                   link: proc (linked: cint) {.cdecl.},
                   reset: proc () {.cdecl.}) =
  onChange = change
  onLink = link
  onReset = reset

proc begin*(title, masterTitle, linkLabel, resetLabel: cstring) =
  ensureGtk()
  window = gtk_window_new(GTK_WINDOW_TOPLEVEL)
  gtk_window_set_title(window, title)
  gtk_window_set_resizable(window, 0)
  connect(window, "delete-event", cast[GCallback](onDeleteHide))
  box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6)
  gtk_widget_set_margin_start(box, 12)
  gtk_widget_set_margin_end(box, 12)
  gtk_widget_set_margin_top(box, 12)
  gtk_widget_set_margin_bottom(box, 12)
  gtk_container_add(window, box)
  # The master, then the link switch and Reset, above the per-device groups.
  addRow(masterTitle, makeSlider(-1, 0))
  let controls = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8)
  linkToggle = gtk_check_button_new_with_label(linkLabel)
  connect(linkToggle, "toggled", cast[GCallback](onLinkToggled))
  gtk_box_pack_start(controls, linkToggle, 0, 0, 0)
  let resetBtn = gtk_button_new_with_label(resetLabel)
  connect(resetBtn, "clicked", cast[GCallback](onResetClicked))
  gtk_box_pack_start(controls, resetBtn, 0, 0, 0)
  gtk_box_pack_start(box, controls, 0, 0, 0)

proc addDevice*(device: cint, caption: cstring) =
  let group = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2)
  gtk_widget_set_margin_top(group, 6)
  let title = gtk_label_new(caption)
  gtk_box_pack_start(group, title, 0, 0, 0)
  gtk_box_pack_start(box, group, 0, 0, 0)
  addRow("L", makeSlider(device, 0))
  addRow("R", makeSlider(device, 1))

proc finish*() =
  ## Layout is automatic; nothing to lay out by hand.
  discard

proc setLevel*(device, channel, value: cint) =
  levels[(device, channel)] = value
  let s = sliders.getOrDefault((device, channel))
  if s != nil:
    suppress = true
    gtk_range_set_value(s, value.cdouble)
    suppress = false

proc getLevel*(device, channel: cint): cint =
  levels.getOrDefault((device, channel))

proc setDeviceEnabled*(device, enabled: cint) =
  for channel in 0'i32 .. 1'i32:
    let s = sliders.getOrDefault((device, channel))
    if s != nil:
      gtk_widget_set_sensitive(s, enabled)

proc setLinked*(linked: cint) =
  if linkToggle != nil:
    suppress = true
    gtk_toggle_button_set_active(linkToggle, linked)
    suppress = false

proc show*() =
  if window != nil:
    gtk_widget_show_all(window)

proc hide*() =
  if window != nil:
    gtk_widget_hide(window)
