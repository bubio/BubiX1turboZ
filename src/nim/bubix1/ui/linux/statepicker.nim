## GTK backend for ui/statepicker.nim: a grid of save-state slots, each a
## button showing its thumbnail, when it was taken and what was in the drives.
##
## Clicking a slot ends the modal dialog with that slot's index as the
## response; Cancel (or closing the window) returns -1. Following Bubilator88,
## a state is chosen by what it looks like rather than from a numbered menu.

import ./gtk3
import ./gtkshell
import ../types

const Columns = 5

var currentDialog: GtkWidget

proc onCellClicked(button: GtkWidget, data: Gpointer) {.cdecl.} =
  if currentDialog != nil:
    gtk_dialog_response(currentDialog, cast[int](data).cint)

proc thumbnailImage(data: seq[byte]): GtkWidget =
  ## A GtkImage built from the slot's PNG bytes, or nil if there are none or
  ## they will not decode. The loader owns the pixbuf; the image takes its own
  ## reference, so the loader can be dropped once the image exists.
  if data.len == 0:
    return nil
  let loader = gdk_pixbuf_loader_new()
  discard gdk_pixbuf_loader_write(loader, unsafeAddr data[0], data.len.csize_t, nil)
  discard gdk_pixbuf_loader_close(loader, nil)
  let pixbuf = gdk_pixbuf_loader_get_pixbuf(loader)
  if pixbuf != nil:
    result = gtk_image_new_from_pixbuf(pixbuf)
  g_object_unref(loader)

proc choose*(title: string, cells: seq[SlotCell],
             cancelLabel, emptyLabel: string): int =
  ensureGtk()
  let dlg = gtk_dialog_new_with_buttons(title.cstring, gtkshell.topWindow(),
    GTK_DIALOG_MODAL or GTK_DIALOG_DESTROY_WITH_PARENT, nil)
  discard gtk_dialog_add_button(dlg, cancelLabel.cstring, GTK_RESPONSE_CANCEL)

  let grid = gtk_grid_new()
  for i, cell in cells:
    let button = gtk_button_new()
    if not cell.enabled:
      gtk_widget_set_sensitive(button, 0)
    let stack = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2)
    let image = thumbnailImage(cell.thumbnail)
    if image != nil:
      gtk_box_pack_start(stack, image, 0, 0, 0)
    else:
      gtk_box_pack_start(stack, gtk_label_new(emptyLabel.cstring), 0, 0, 0)
    gtk_box_pack_start(stack, gtk_label_new(cell.caption.cstring), 0, 0, 0)
    if cell.detail.len > 0:
      gtk_box_pack_start(stack, gtk_label_new(cell.detail.cstring), 0, 0, 0)
    if cell.disks.len > 0:
      gtk_box_pack_start(stack, gtk_label_new(sjisToUtf8(cell.disks).cstring), 0, 0, 0)
    gtk_container_add(button, stack)
    connect(button, "clicked", cast[GCallback](onCellClicked),
            cast[Gpointer](cast[int](i)))
    gtk_grid_attach(grid, button, (i mod Columns).cint, (i div Columns).cint, 1, 1)

  gtk_box_pack_start(gtk_dialog_get_content_area(dlg), grid, 1, 1, 8)
  gtk_widget_show_all(dlg)
  currentDialog = dlg
  let response = gtk_dialog_run(dlg)
  currentDialog = nil
  gtk_widget_destroy(dlg)
  if response >= 0 and response < cells.len:
    response
  else:
    -1
