## Raw GTK3 / GDK / GLib / Xlib bindings shared by the Linux UI backends.
##
## Every Linux backend imports this one module, so the pkg-config flags that
## find GTK and Xlib live here and nowhere else. The bindings are the plain
## C entry points; the shaping into the application's own vocabulary is done
## by the backends and by gtkshell.nim.
##
## This file names host libraries and so belongs under bubix1/ui - the
## boundary bubix1/ui/README.md draws. It is compiled only on the platforms
## whose UI facades select a linux backend.

{.passC: gorge("pkg-config --cflags gtk+-3.0 x11").}
{.passL: gorge("pkg-config --libs gtk+-3.0 x11").}

type
  Gboolean* = cint
  Gpointer* = pointer
  GtkWidget* = pointer
    ## Every GTK object this code touches is passed around as an opaque
    ## widget pointer; the C type distinctions do not earn their keep here.
  GdkWindow* = pointer
  GCallback* = pointer
  Window* = culong
    ## An X11 resource id (XID).
  GdkAtom* = pointer
  GtkAllocation* = object
    ## The rectangle GTK hands a widget in its "size-allocate" signal. Only
    ## width and height are read here, but the layout has to match GtkWidget's
    ## GdkRectangle exactly.
    x*, y*, width*, height*: cint

const
  # GtkWindowType
  GTK_WINDOW_TOPLEVEL* = 0'i32
  # GtkOrientation
  GTK_ORIENTATION_HORIZONTAL* = 0'i32
  GTK_ORIENTATION_VERTICAL* = 1'i32
  # GdkModifierType (the ones menus use)
  GDK_SHIFT_MASK* = 1'u32
  GDK_CONTROL_MASK* = 4'u32
  GDK_MOD1_MASK* = 8'u32
  # GtkAccelFlags
  GTK_ACCEL_VISIBLE* = 1'i32
  # GConnectFlags
  G_CONNECT_AFTER* = 1'i32
  # GtkFileChooserAction
  GTK_FILE_CHOOSER_ACTION_OPEN* = 0'i32
  GTK_FILE_CHOOSER_ACTION_SAVE* = 1'i32
  GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER* = 2'i32
  # GtkResponseType (the negative predefined ones)
  GTK_RESPONSE_NONE* = -1'i32
  GTK_RESPONSE_ACCEPT* = -3'i32
  GTK_RESPONSE_CANCEL* = -6'i32
  GTK_RESPONSE_OK* = -5'i32
  # GtkMessageType
  GTK_MESSAGE_INFO* = 0'i32
  GTK_MESSAGE_WARNING* = 1'i32
  GTK_MESSAGE_QUESTION* = 2'i32
  GTK_MESSAGE_ERROR* = 3'i32
  # GtkButtonsType
  GTK_BUTTONS_NONE* = 0'i32
  # GtkDialogFlags
  GTK_DIALOG_MODAL* = 1'i32
  GTK_DIALOG_DESTROY_WITH_PARENT* = 2'i32

{.push importc, cdecl.}

{.push header: "<gtk/gtk.h>".}
proc gtk_init*(argc: ptr cint, argv: pointer)
proc gtk_main_iteration_do*(blocking: Gboolean): Gboolean
proc gtk_events_pending*(): Gboolean

proc gtk_window_new*(kind: cint): GtkWidget
proc gtk_window_set_title*(window: GtkWidget, title: cstring)
proc gtk_window_set_resizable*(window: GtkWidget, resizable: Gboolean)
proc gtk_window_move*(window: GtkWidget, x, y: cint)
proc gtk_window_get_position*(window: GtkWidget, x, y: ptr cint)
proc gtk_window_resize*(window: GtkWidget, width, height: cint)
proc gtk_window_fullscreen*(window: GtkWidget)
proc gtk_window_unfullscreen*(window: GtkWidget)
proc gtk_window_set_transient_for*(window, parent: GtkWidget)
proc gtk_window_add_accel_group*(window, accelGroup: GtkWidget)

proc gtk_box_new*(orientation: cint, spacing: cint): GtkWidget
proc gtk_box_pack_start*(box, child: GtkWidget, expand, fill: Gboolean, padding: cuint)
proc gtk_container_add*(container, widget: GtkWidget)

proc gtk_menu_bar_new*(): GtkWidget
proc gtk_menu_new*(): GtkWidget
proc gtk_menu_item_new_with_label*(label: cstring): GtkWidget
proc gtk_check_menu_item_new_with_label*(label: cstring): GtkWidget
proc gtk_check_menu_item_set_active*(item: GtkWidget, active: Gboolean)
proc gtk_check_menu_item_get_active*(item: GtkWidget): Gboolean
proc gtk_separator_menu_item_new*(): GtkWidget
proc gtk_menu_item_set_submenu*(item, submenu: GtkWidget)
proc gtk_menu_item_set_label*(item: GtkWidget, label: cstring)
proc gtk_menu_shell_append*(shell, child: GtkWidget)

proc gtk_accel_group_new*(): GtkWidget
proc gtk_widget_add_accelerator*(widget: GtkWidget, signal: cstring,
  accelGroup: GtkWidget, accelKey: cuint, accelMods: cuint, accelFlags: cint)

proc gtk_drawing_area_new*(): GtkWidget
proc gtk_widget_set_size_request*(widget: GtkWidget, width, height: cint)
proc gtk_widget_show*(widget: GtkWidget)
proc gtk_widget_show_all*(widget: GtkWidget)
proc gtk_widget_hide*(widget: GtkWidget)
proc gtk_widget_destroy*(widget: GtkWidget)
proc gtk_widget_realize*(widget: GtkWidget)
proc gtk_widget_set_sensitive*(widget: GtkWidget, sensitive: Gboolean)
proc gtk_widget_get_window*(widget: GtkWidget): GdkWindow
proc gtk_widget_get_allocated_height*(widget: GtkWidget): cint
proc gtk_window_is_active*(window: GtkWidget): Gboolean
proc gtk_grab_get_current*(): GtkWidget

# Dialogs. gtk_file_chooser_dialog_new is variadic (a NULL-terminated list of
# button label / response id pairs); it is declared with just the trailing
# NULL so the dialog opens button-less and gtk_dialog_add_button fills it,
# which sidesteps passing an alternating varargs list from Nim.
proc gtk_file_chooser_dialog_new*(title: cstring, parent: GtkWidget,
  action: cint, firstButtonText: cstring): GtkWidget
proc gtk_dialog_add_button*(dialog: GtkWidget, text: cstring,
  responseId: cint): GtkWidget
proc gtk_dialog_run*(dialog: GtkWidget): cint
proc gtk_dialog_response*(dialog: GtkWidget, responseId: cint)
proc gtk_dialog_new_with_buttons*(title: cstring, parent: GtkWidget,
  flags: cint, firstButtonText: cstring): GtkWidget
proc gtk_file_chooser_get_filename*(chooser: GtkWidget): cstring
proc gtk_file_chooser_set_current_name*(chooser: GtkWidget, name: cstring)
proc gtk_file_chooser_set_do_overwrite_confirmation*(chooser: GtkWidget,
  doConfirm: Gboolean)
proc gtk_file_chooser_add_filter*(chooser, filter: GtkWidget)
proc gtk_file_filter_new*(): GtkWidget
proc gtk_file_filter_set_name*(filter: GtkWidget, name: cstring)
proc gtk_file_filter_add_pattern*(filter: GtkWidget, pattern: cstring)
proc gtk_message_dialog_new*(parent: GtkWidget, flags: cint, kind: cint,
  buttons: cint, messageFormat: cstring): GtkWidget {.varargs.}

proc gtk_dialog_get_content_area*(dialog: GtkWidget): GtkWidget
proc gtk_combo_box_text_new*(): GtkWidget
proc gtk_combo_box_text_append_text*(combo: GtkWidget, text: cstring)
proc gtk_combo_box_set_active*(combo: GtkWidget, index: cint)
proc gtk_combo_box_get_active*(combo: GtkWidget): cint

# Widgets for the volume panel and the save-state picker.
proc gtk_label_new*(text: cstring): GtkWidget
proc gtk_button_new*(): GtkWidget
proc gtk_button_new_with_label*(label: cstring): GtkWidget
proc gtk_check_button_new_with_label*(label: cstring): GtkWidget
proc gtk_toggle_button_get_active*(toggle: GtkWidget): Gboolean
proc gtk_toggle_button_set_active*(toggle: GtkWidget, active: Gboolean)
proc gtk_scale_new_with_range*(orientation: cint, min, max, step: cdouble): GtkWidget
proc gtk_scale_set_draw_value*(scale: GtkWidget, drawValue: Gboolean)
proc gtk_scale_set_digits*(scale: GtkWidget, digits: cint)
proc gtk_range_get_value*(range: GtkWidget): cdouble
proc gtk_range_set_value*(range: GtkWidget, value: cdouble)
proc gtk_grid_new*(): GtkWidget
proc gtk_grid_attach*(grid, child: GtkWidget, left, top, width, height: cint)
proc gtk_image_new_from_pixbuf*(pixbuf: GtkWidget): GtkWidget
proc gtk_widget_set_margin_start*(widget: GtkWidget, margin: cint)
proc gtk_widget_set_margin_end*(widget: GtkWidget, margin: cint)
proc gtk_widget_set_margin_top*(widget: GtkWidget, margin: cint)
proc gtk_widget_set_margin_bottom*(widget: GtkWidget, margin: cint)

proc gtk_clipboard_get*(selection: GdkAtom): GtkWidget
proc gtk_clipboard_wait_for_text*(clipboard: GtkWidget): cstring
{.pop.}

{.push header: "<gdk/gdkx.h>".}
proc gdk_x11_window_get_xid*(window: GdkWindow): Window
{.pop.}

{.push header: "<gdk/gdk.h>".}
proc gdk_atom_intern*(atomName: cstring, onlyIfExists: Gboolean): GdkAtom
{.pop.}

{.push header: "<gdk-pixbuf/gdk-pixbuf.h>".}
proc gdk_pixbuf_loader_new*(): GtkWidget
proc gdk_pixbuf_loader_write*(loader: GtkWidget, buf: ptr byte, count: csize_t,
  error: ptr pointer): Gboolean
proc gdk_pixbuf_loader_close*(loader: GtkWidget, error: ptr pointer): Gboolean
proc gdk_pixbuf_loader_get_pixbuf*(loader: GtkWidget): GtkWidget
{.pop.}

{.push header: "<glib-object.h>".}
proc g_signal_connect_data*(instance: pointer, detailedSignal: cstring,
  handler: GCallback, data: Gpointer, destroyData: pointer,
  connectFlags: cint): culong
proc g_object_unref*(obj: pointer)
{.pop.}

{.push header: "<glib.h>".}
proc g_free*(mem: pointer)
proc g_convert*(str: cstring, len: clong, toCodeset, fromCodeset: cstring,
  bytesRead, bytesWritten: ptr csize_t, error: ptr pointer): cstring
proc g_spawn_command_line_async*(commandLine: cstring, error: ptr pointer): Gboolean
proc g_dgettext*(domain, msgid: cstring): cstring
{.pop.}

{.push header: "<X11/Xlib.h>".}
proc XReparentWindow*(display: pointer, w, parent: Window, x, y: cint): cint
proc XMapWindow*(display: pointer, w: Window): cint
proc XResizeWindow*(display: pointer, w: Window, width, height: cuint): cint
proc XSetInputFocus*(display: pointer, focus: Window, revertTo: cint, time: culong): cint
proc XGetInputFocus*(display: pointer, focusReturn: ptr Window, revertReturn: ptr cint): cint
proc XSync*(display: pointer, discardQueue: cint): cint
{.pop.}

const
  RevertToParent* = 2'i32
  CurrentTime* = 0'u64

{.pop.}

proc connect*(instance: pointer, signal: cstring, handler: GCallback,
              data: Gpointer = nil, after = false) =
  ## Thin wrapper over g_signal_connect (which is itself a macro over
  ## g_signal_connect_data with no destroy notify and no flags). `after` runs
  ## the handler after the widget's own default handler for the signal - the
  ## difference between overriding GTK's focus handling and losing to it.
  discard g_signal_connect_data(instance, signal, handler, data, nil,
    if after: G_CONNECT_AFTER else: 0)

proc sjisToUtf8*(s: string): string =
  ## D88 disk names and the like arrive as raw Shift-JIS. This is the app's
  ## one place on Linux that turns them into UTF-8; a sequence GLib cannot
  ## convert is left untouched rather than dropped.
  if s.len == 0:
    return ""
  let converted = g_convert(s.cstring, s.len.clong, "UTF-8".cstring,
    "CP932".cstring, nil, nil, nil)
  if converted == nil:
    return s
  result = $converted
  g_free(converted)
