## GTK backend for ui/statepicker.nim: a grid of save-state slots, each a
## button showing its thumbnail with a translucent bar along the bottom
## carrying the slot number, when the state was taken and what was in the
## drives.
##
## The layout follows the macOS picker (ui/macos/statepicker.m), which in
## turn follows Bubilator88's sheet: two columns of 8:5 cells inside a
## scrolling area, and Cancel alone in the action area. A state is chosen by
## what it looks like rather than from a numbered menu, so the thumbnail is
## given the whole cell and the text is composited over it.
##
## Clicking a slot ends the modal dialog with that slot's index as the
## response; Cancel (or closing the window) returns -1.

import ./gtk3
import ./gtkshell
import ../types

const
  Columns = 2
  ## Cell geometry, matching the macOS picker. 8:5 like the emulated screen,
  ## so a 320x200 thumbnail lands in it without letterboxing.
  CellWidth = 248
  CellHeight = 155
  CellGap = 12
  ## Two rows of cells and a little of the third, as the sheet opens on macOS.
  WindowWidth = 580
  WindowHeight = 520

  ## The cells are painted by this style sheet alone - no GTK theme has an
  ## opinion about them. Sizes are in pixels to stay in step with the cell
  ## geometry above rather than with the theme's font scale.
  CellCss = """
    .bx1-slot { padding: 0; border: none; background: none; }
    .bx1-slot-bar {
      background-color: rgba(0, 0, 0, 0.55);
      padding: 3px 8px;
    }
    .bx1-slot-bar label {
      color: rgba(255, 255, 255, 0.95);
      font-size: 10px;
      font-weight: bold;
    }
    .bx1-slot-empty {
      background-color: rgba(0, 0, 0, 0.7);
      color: rgba(255, 255, 255, 0.3);
      font-size: 15px;
    }
  """

var
  currentDialog: GtkWidget
  cssLoaded = false

proc ensureCss() =
  ## Adds the cell style sheet to the default screen once per run. It is
  ## scoped by class name, so it touches nothing but the picker's own cells.
  if cssLoaded:
    return
  let provider = gtk_css_provider_new()
  if gtk_css_provider_load_from_data(provider, CellCss.cstring,
                                     CellCss.len.clong, nil) != 0:
    gtk_style_context_add_provider_for_screen(gdk_screen_get_default(),
      provider, GTK_STYLE_PROVIDER_PRIORITY_APPLICATION)
    cssLoaded = true
  g_object_unref(provider)

proc addClass(widget: GtkWidget, className: string) =
  gtk_style_context_add_class(gtk_widget_get_style_context(widget),
                              className.cstring)

proc onCellClicked(button: GtkWidget, data: Gpointer) {.cdecl.} =
  if currentDialog != nil:
    gtk_dialog_response(currentDialog, cast[int](data).cint)

proc thumbnailImage(data: seq[byte]): GtkWidget =
  ## A GtkImage of the slot's PNG bytes scaled to the cell, or nil if there
  ## are none or they will not decode. The scaling is nearest-neighbour:
  ## emulator output is pixel art, and smoothing it on the way down makes it
  ## look like a photograph of a screen. The loader owns the pixbuf, and
  ## the scaled copy is owned here until the image takes its own reference.
  if data.len == 0:
    return nil
  let loader = gdk_pixbuf_loader_new()
  discard gdk_pixbuf_loader_write(loader, unsafeAddr data[0], data.len.csize_t, nil)
  discard gdk_pixbuf_loader_close(loader, nil)
  let pixbuf = gdk_pixbuf_loader_get_pixbuf(loader)
  if pixbuf != nil:
    let scaled = gdk_pixbuf_scale_simple(pixbuf, CellWidth, CellHeight,
                                         GDK_INTERP_NEAREST)
    if scaled != nil:
      result = gtk_image_new_from_pixbuf(scaled)
      g_object_unref(scaled)
  g_object_unref(loader)

proc infoBar(cell: SlotCell): GtkWidget =
  ## The translucent strip over the bottom of a cell: "Slot 3   08/15 12:34"
  ## on the left and the disks on the right, the order the macOS picker uses
  ## and the one that stays readable when a long title has to be truncated.
  result = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8)
  addClass(result, "bx1-slot-bar")
  gtk_widget_set_valign(result, GTK_ALIGN_END)
  gtk_widget_set_halign(result, GTK_ALIGN_FILL)

  var left = cell.caption
  if cell.detail.len > 0:
    left.add("   " & cell.detail)
  let leftLabel = gtk_label_new(left.cstring)
  gtk_label_set_xalign(leftLabel, 0.0)
  gtk_label_set_ellipsize(leftLabel, PANGO_ELLIPSIZE_END)
  gtk_widget_set_hexpand(leftLabel, 1)
  gtk_box_pack_start(result, leftLabel, 1, 1, 0)

  if cell.disks.len > 0:
    let rightLabel = gtk_label_new(sjisToUtf8(cell.disks).cstring)
    gtk_label_set_xalign(rightLabel, 1.0)
    gtk_label_set_ellipsize(rightLabel, PANGO_ELLIPSIZE_END)
    # Never more than half the bar, so the slot number cannot be crowded out.
    gtk_label_set_max_width_chars(rightLabel, 18)
    gtk_box_pack_start(result, rightLabel, 0, 0, 0)

proc cellButton(cell: SlotCell, index: int, emptyLabel: string): GtkWidget =
  ## One cell: the thumbnail (or an "Empty" placeholder) with the info bar
  ## laid over its bottom edge, the whole of it a borderless button.
  let overlay = gtk_overlay_new()
  var base = thumbnailImage(cell.thumbnail)
  if base == nil:
    base = gtk_label_new(emptyLabel.cstring)
    addClass(base, "bx1-slot-empty")
  gtk_widget_set_size_request(base, CellWidth, CellHeight)
  gtk_container_add(overlay, base)
  gtk_overlay_add_overlay(overlay, infoBar(cell))

  result = gtk_button_new()
  addClass(result, "bx1-slot")
  gtk_button_set_relief(result, GTK_RELIEF_NONE)
  gtk_widget_set_size_request(result, CellWidth, CellHeight)
  gtk_container_add(result, overlay)
  if not cell.enabled:
    # A slot the Load side cannot use is dimmed rather than hidden - the
    # slot number is half the point of the grid.
    gtk_widget_set_sensitive(result, 0)
    gtk_widget_set_opacity(result, 0.4)
  connect(result, "clicked", cast[GCallback](onCellClicked),
          cast[Gpointer](cast[int](index)))

proc choose*(title: string, cells: seq[SlotCell],
             cancelLabel, emptyLabel: string): int =
  ensureGtk()
  ensureCss()
  let dlg = gtk_dialog_new_with_buttons(title.cstring, gtkshell.topWindow(),
    GTK_DIALOG_MODAL or GTK_DIALOG_DESTROY_WITH_PARENT, nil)
  discard gtk_dialog_add_button(dlg, cancelLabel.cstring, GTK_RESPONSE_CANCEL)
  gtk_window_set_default_size(dlg, WindowWidth, WindowHeight)

  let grid = gtk_grid_new()
  gtk_grid_set_row_spacing(grid, CellGap.cuint)
  gtk_grid_set_column_spacing(grid, CellGap.cuint)
  gtk_widget_set_halign(grid, GTK_ALIGN_CENTER)
  gtk_widget_set_margin_start(grid, CellGap)
  gtk_widget_set_margin_end(grid, CellGap)
  gtk_widget_set_margin_top(grid, CellGap)
  gtk_widget_set_margin_bottom(grid, CellGap)
  for i, cell in cells:
    gtk_grid_attach(grid, cellButton(cell, i, emptyLabel),
                    (i mod Columns).cint, (i div Columns).cint, 1, 1)

  # The grid scrolls rather than growing the dialog past the screen; the
  # cells are a fixed size, so only the vertical scroller is ever wanted.
  let scroll = gtk_scrolled_window_new(nil, nil)
  gtk_scrolled_window_set_policy(scroll, GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC)
  gtk_container_add(scroll, grid)

  let content = gtk_dialog_get_content_area(dlg)
  gtk_box_pack_start(content, gtk_separator_new(GTK_ORIENTATION_HORIZONTAL),
                     0, 0, 0)
  gtk_box_pack_start(content, scroll, 1, 1, 0)
  gtk_box_pack_start(content, gtk_separator_new(GTK_ORIENTATION_HORIZONTAL),
                     0, 0, 0)
  gtk_widget_show_all(dlg)
  currentDialog = dlg
  let response = gtk_dialog_run(dlg)
  currentDialog = nil
  gtk_widget_destroy(dlg)
  if response >= 0 and response < cells.len:
    response
  else:
    -1
