## The single GTK window the Linux port runs in: a menu bar above the SDL
## drawing surface, in one top-level window.
##
## Two Linux backends share this state. `nativemenu` fills the menu bar
## (built here, before the SDL window exists), and `hostwindow` embeds the
## SDL window beneath it and drives the window operations that on macOS go
## straight to SDL. `filedialog` and the panels read `topWindow` so their
## dialogs stand on this window.
##
## The embedding is deliberate and its ordering matters - see the project
## memory note "linux-gtk-embed-approach": the SDL window is reparented into
## the drawing area while still unmapped and mapped by hand, because
## SDL_ShowWindow blocks once the window is a child, and GtkSocket will not
## map a window that does not speak XEMBED.

import ./gtk3

var
  gtkUp = false           ## gtk_init has run
  inited = false          ## the window shell has been built
  topWin: GtkWidget       ## the one top-level window
  vbox: GtkWidget         ## menu bar over drawing area
  menuBarW: GtkWidget     ## the GtkMenuBar nativemenu appends to
  drawArea: GtkWidget     ## where the SDL window is reparented
  accelGroup: GtkWidget   ## menu keyboard equivalents hang here
  childDisplay: pointer   ## SDL's X11 Display*, for XResizeWindow on resize
  childXid: Window        ## the embedded SDL window
  topXid: Window          ## the GTK top-level's X window, the "focus stolen" state
  deleteHandler: proc () {.cdecl.}

proc onSizeAllocate(widget: GtkWidget, alloc: ptr GtkAllocation,
                    data: Gpointer) {.cdecl.} =
  ## Keep the embedded SDL window exactly the size GTK gave the drawing area.
  ## The resize reaches SDL as an X ConfigureNotify, so SDL_GetWindowSize and
  ## the renderer output size stay correct without anyone telling SDL.
  if childXid != 0 and childDisplay != nil:
    discard XResizeWindow(childDisplay, childXid,
                          alloc.width.cuint, alloc.height.cuint)

proc focusChild() =
  ## Point X keyboard focus at the embedded SDL window. The window manager
  ## only ever focuses the top-level, so this has to be (re)asserted whenever
  ## the top-level gains focus, not just once at embed time.
  if childXid != 0 and childDisplay != nil:
    discard XSetInputFocus(childDisplay, childXid, RevertToParent, CurrentTime)

proc onFocusIn(widget: GtkWidget, event, data: Gpointer): Gboolean {.cdecl.} =
  focusChild()
  0

proc onDelete(widget: GtkWidget, event, data: Gpointer): Gboolean {.cdecl.} =
  ## The window-manager close button. Returning true keeps GTK from
  ## destroying the window from under us; the handler routes the request to
  ## the same shutdown path every other quit uses.
  if deleteHandler != nil:
    deleteHandler()
  1

proc ensureGtk*() =
  ## Just bring GTK up. A dialog can be needed before the window shell is
  ## built - the missing-ROM alert runs at startup, ahead of the menu bar -
  ## so the dialog backends call this rather than the heavier ensureInit.
  if not gtkUp:
    gtk_init(nil, nil)
    gtkUp = true

proc ensureInit*() =
  ## Bring GTK up and build the empty shell. Called first by nativemenu, so
  ## the menu bar exists before the SDL window does.
  if inited:
    return
  ensureGtk()
  topWin = gtk_window_new(GTK_WINDOW_TOPLEVEL)
  gtk_window_set_resizable(topWin, 0)
  accelGroup = gtk_accel_group_new()
  gtk_window_add_accel_group(topWin, accelGroup)
  vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)
  gtk_container_add(topWin, vbox)
  menuBarW = gtk_menu_bar_new()
  gtk_box_pack_start(vbox, menuBarW, 0, 0, 0)
  connect(topWin, "delete-event", cast[GCallback](onDelete))
  # after=true: run once GTK's own focus handling has finished, so the focus
  # ends on the embedded SDL window rather than being taken back by GTK.
  connect(topWin, "focus-in-event", cast[GCallback](onFocusIn), after = true)
  inited = true

proc menuBar*(): GtkWidget =
  ## The bar nativemenu appends its top-level menus to.
  ensureInit()
  menuBarW

proc accels*(): GtkWidget =
  ensureInit()
  accelGroup

proc topWindow*(): GtkWidget =
  ## The window dialogs are made transient for. nil until the shell is built:
  ## a dialog shown before then (the missing-ROM alert) simply stands alone.
  topWin

proc setDeleteHandler*(fn: proc () {.cdecl.}) =
  deleteHandler = fn

proc embed*(display: pointer, xid: Window, width, height, x, y: cint,
            restorePos: bool) =
  ## Put the SDL window (given by its X11 Display and XID) under the menu bar
  ## and show the whole thing. Must run while the SDL window is still hidden.
  ensureInit()
  childDisplay = display
  childXid = xid
  drawArea = gtk_drawing_area_new()
  gtk_widget_set_size_request(drawArea, width, height)
  gtk_box_pack_start(vbox, drawArea, 1, 1, 0)
  connect(drawArea, "size-allocate", cast[GCallback](onSizeAllocate))
  if restorePos:
    gtk_window_move(topWin, x, y)
  # Shown widget by widget rather than with gtk_widget_show_all: the menus
  # carry sections the application hides (the D88 bank list, the recent-file
  # entries), and show_all would recursively re-reveal every one of them.
  # nativemenu shows each item it means to be visible as it builds it.
  gtk_widget_show(menuBarW)
  gtk_widget_show(vbox)
  gtk_widget_show(drawArea)
  gtk_widget_show(topWin)
  gtk_widget_realize(drawArea)
  topXid = gdk_x11_window_get_xid(gtk_widget_get_window(topWin))
  let parent = gdk_x11_window_get_xid(gtk_widget_get_window(drawArea))
  discard XReparentWindow(display, xid, parent, 0, 0)
  discard XResizeWindow(display, xid, width.cuint, height.cuint)
  discard XMapWindow(display, xid)
  # Hand keyboard focus to the embedded window itself: it is a child now, so
  # the window manager will not focus it, and without this key events go to
  # the GTK top-level and never reach SDL. The menu bar's own accelerators
  # are given up in return - a known, accepted trade (see the memory note).
  discard XSetInputFocus(display, xid, RevertToParent, CurrentTime)
  discard XSync(display, 0)

proc setSize*(width, height: cint) =
  ## Resize to fit a picture of this size (the game area, without the bar).
  ## The drawing area's size-allocate then resizes the embedded window.
  if not inited or drawArea == nil:
    return
  gtk_widget_set_size_request(drawArea, width, height)
  gtk_window_resize(topWin, width, height + gtk_widget_get_allocated_height(menuBarW))

proc setFullscreen*(on: bool) =
  if not inited:
    return
  if on:
    gtk_widget_hide(menuBarW)
    gtk_window_fullscreen(topWin)
  else:
    gtk_window_unfullscreen(topWin)
    gtk_widget_show(menuBarW)

proc getPosition*(x, y: var cint) =
  if inited:
    gtk_window_get_position(topWin, addr x, addr y)

proc destroy*() =
  if inited and topWin != nil:
    gtk_widget_destroy(topWin)

proc keepFocusOnChild() =
  ## Hand keyboard focus back to the embedded SDL window if GTK has taken it
  ## onto the top-level. GTK retakes focus for its own widgets at moments the
  ## focus-in handler does not catch; reasserting here each pass is the safety
  ## net. The test is deliberately narrow - only the exact "focus sits on the
  ## GTK top-level" state is corrected - so it never fights SDL, which parks
  ## focus on a private child window of its own. Skipped while a GTK grab is
  ## up (a menu is open) or the window is not active (a dialog or the volume
  ## panel holds the focus it needs).
  if childXid == 0 or childDisplay == nil or topXid == 0:
    return
  if gtk_grab_get_current() != nil or gtk_window_is_active(topWin) == 0:
    return
  var focused: Window
  var revert: cint
  discard XGetInputFocus(childDisplay, addr focused, addr revert)
  if focused == topXid:
    discard XSetInputFocus(childDisplay, childXid, RevertToParent, CurrentTime)

proc pump*() =
  ## Drain whatever GTK has queued. Non-blocking: called once per pass of the
  ## application's own event loop.
  if inited:
    while gtk_events_pending() != 0:
      discard gtk_main_iteration_do(0)
    keepFocusOnChild()
