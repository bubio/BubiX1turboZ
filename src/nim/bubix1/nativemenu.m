/*
	BubiX1turboZ - the whole menu bar, built directly as NSMenu/NSMenuItem
	objects.

	The original eX1turboZ menu bar this app mirrors is two levels deep
	(Control > Save State > State 0, Device > Sound > PSG, ...), which is
	ordinary AppKit but was beyond the GUI library this port started on. The
	bar is now built here in full, application menu included, so there is one
	answer to "where does this menu item come from".

	SDL creates its own menu bar when it registers the application: an app
	menu whose items are English literals, plus Window and View menus this
	app has no use for. Installing a bar here replaces all of that, so the
	six standard application-menu items are created with translated titles
	instead of being renamed afterwards, and nothing sits on the bar that
	this app does not offer.

	Shutdown is not one of the reasons. Every way of quitting is graceful
	whichever menu bar is installed - see the header of bubix1turboz.nim
	for why, and for why the delegate is not where to hook it.

	Items are addressed by an integer tag rather than by pointer: every item
	shares one target/action pair here, which forwards the tag to a single C
	callback. That gives the Nim side one dispatch point to map tags to
	closures, instead of one closure per item - and sidesteps the trap
	documented in DevelopmentPlan phase 7, where several closures created in
	one Nim for-loop all share a single binding of the loop variable.
*/

#import <Cocoa/Cocoa.h>

typedef void (*bx1_nmenu_action_fn)(int tag);

static bx1_nmenu_action_fn action_fn = NULL;

@interface BX1MenuTarget : NSObject
- (void)menuAction:(id)sender;
@end

@implementation BX1MenuTarget
- (void)menuAction:(id)sender
{
	if (action_fn != NULL) {
		action_fn((int)[(NSMenuItem *)sender tag]);
	}
}
@end

// NSMenuItem holds its target weakly, so this must stay alive for the
// process's lifetime or every menu click becomes a silent no-op (or worse,
// a message to a freed object). Deliberately allocated once and never
// released.
static BX1MenuTarget *target = nil;
// tag -> NSMenuItem, so callers can re-title / check / enable an item later
// without holding pointers across the FFI boundary.
static NSMutableDictionary *items_by_tag = nil;

/*
	Menu titles can carry bytes that are not UTF-8, and +stringWithUTF8String:
	returns nil for those - which would then reach -setTitle: and raise
	NSInvalidArgumentException. This is not hypothetical for X1 software: the
	core stores a D88's 17-byte disk name verbatim on non-Windows builds (its
	MultiByteToWideChar conversion is inside #ifdef _UNICODE, i.e. Win32
	only), so a Japanese multi-disk image hands us raw Shift-JIS, as do
	Shift-JIS filenames coming out of bsdtar. Try UTF-8, then Shift-JIS, and
	fall back to a lossy read so a title is always produced.

	Not static: filedialog.m's disk picker shows the same D88 names and has
	to decode them the same way. One decoder, one place to fix.
*/
NSString *bx1_ns_string(const char *bytes)
{
	NSString *s;

	if (bytes == NULL) {
		return @"";
	}
	if ((s = [NSString stringWithUTF8String:bytes]) != nil) {
		return s;
	}
	s = [NSString stringWithCString:bytes encoding:NSShiftJISStringEncoding];
	if (s != nil) {
		return s;
	}
	s = [[[NSString alloc] initWithBytes:bytes length:strlen(bytes)
		encoding:NSISOLatin1StringEncoding] autorelease];
	return s != nil ? s : @"";
}

static void ensure_globals(void)
{
	if (target == nil) {
		target = [[BX1MenuTarget alloc] init];
	}
	if (items_by_tag == nil) {
		items_by_tag = [[NSMutableDictionary alloc] init];
	}
}

void bx1_nmenu_set_action(bx1_nmenu_action_fn fn)
{
	action_fn = fn;
}

/*
	Every menu created here turns off Cocoa's automatic item validation.

	With it on (the default), AppKit re-derives every item's enabled state
	from its target/action pair right before the menu is displayed, silently
	discarding any manual setEnabled: call on an item that has one - which
	every item here does. On its own that would only make
	bx1_nmenu_set_enabled a no-op, but there is a worse failure mode: a
	modal panel that leaves NSApp's modal-session bookkeeping in a broken
	state (logged by AppKit as "modalSession has been exited prematurely")
	makes autoenablesItems treat every item outside that phantom modal
	window as invalid and disable it - which reads as "the entire menu bar
	is now dead" after using any Open/Save dialog. Turning it off removes
	the dependency on that bookkeeping entirely, and nothing in this app
	relies on Cocoa's automatic validation. See filedialog.m, which runs its
	panels app-modal for the other half of the same problem.
*/
static NSMenu *make_menu(const char *title)
{
	NSMenu *menu = [[NSMenu alloc] initWithTitle:bx1_ns_string(title)];
	[menu setAutoenablesItems:NO];
	return menu;
}

/*
	Replaces whatever menu bar the application has with an empty one, and
	returns the application menu at the head of it - the menu macOS draws
	under the app's name, which the caller fills in with About, Hide, Quit
	and the rest.

	The application menu is simply the first item of the bar; its title is
	ignored for display (macOS substitutes the bundle name), but is set
	anyway so the item is not anonymous in the debugger.
*/
void *bx1_nmenu_install_menubar(const char *app_name)
{
	NSMenu *bar;
	NSMenu *app_menu;
	NSMenuItem *app_item;

	ensure_globals();
	if (NSApp == nil) {
		return NULL;
	}
	bar = [[NSMenu alloc] initWithTitle:@""];
	[bar setAutoenablesItems:NO];
	app_menu = make_menu(app_name);
	app_item = [[NSMenuItem alloc] initWithTitle:bx1_ns_string(app_name)
		action:NULL keyEquivalent:@""];
	[app_item setSubmenu:app_menu];
	[bar addItem:app_item];
	[NSApp setMainMenu:bar];
	return app_menu;
}

/*
	Appends one of the application menu's standard items - the ones whose
	behaviour belongs to AppKit rather than to this app, so they carry an
	AppKit selector instead of a tag.

	`which`: 0 = Services, 1 = Hide, 2 = Hide Others, 3 = Show All. Services
	is a submenu AppKit populates itself once it has been handed to NSApp.
	The others go to nil, i.e. down the responder chain to NSApp.
*/
void bx1_nmenu_add_standard_item(void *menu, const char *title, int which,
	const char *key, int mods)
{
	NSMenuItem *item;
	SEL action = NULL;

	ensure_globals();
	if (menu == NULL) {
		return;
	}
	switch (which) {
	case 1: action = @selector(hide:); break;
	case 2: action = @selector(hideOtherApplications:); break;
	case 3: action = @selector(unhideAllApplications:); break;
	default: break;
	}
	item = [[NSMenuItem alloc] initWithTitle:bx1_ns_string(title)
		action:action keyEquivalent:@""];
	if (which == 0) {
		NSMenu *services = [[NSMenu alloc] initWithTitle:@""];

		// Left on automatic validation, unlike every other menu here: its
		// items are AppKit's and only AppKit knows which of them apply to
		// what is currently selected.
		[item setSubmenu:services];
		[NSApp setServicesMenu:services];
	} else {
		// The menus here have automatic validation off, so an item that
		// AppKit would normally enable for itself has to say so.
		[item setEnabled:YES];
	}
	if (key != NULL && key[0] != '\0') {
		NSEventModifierFlags mask = 0;
		if (mods & 1) mask |= NSEventModifierFlagCommand;
		if (mods & 2) mask |= NSEventModifierFlagShift;
		if (mods & 4) mask |= NSEventModifierFlagOption;
		if (mods & 8) mask |= NSEventModifierFlagControl;
		[item setKeyEquivalent:[NSString stringWithUTF8String:key]];
		[item setKeyEquivalentModifierMask:mask];
	}
	[(NSMenu *)menu addItem:item];
}

void *bx1_nmenu_add_toplevel(const char *title)
{
	NSMenu *bar;
	NSMenuItem *item;
	NSMenu *menu;

	ensure_globals();
	if (NSApp == nil || (bar = [NSApp mainMenu]) == nil) {
		return NULL;
	}
	menu = make_menu(title);
	item = [[NSMenuItem alloc] initWithTitle:bx1_ns_string(title)
		action:NULL keyEquivalent:@""];
	[item setSubmenu:menu];
	[bar addItem:item];
	return menu;
}

void *bx1_nmenu_add_submenu(void *parent, const char *title)
{
	NSMenu *menu;
	NSMenuItem *item;

	ensure_globals();
	if (parent == NULL) {
		return NULL;
	}
	menu = make_menu(title);
	item = [[NSMenuItem alloc] initWithTitle:bx1_ns_string(title)
		action:NULL keyEquivalent:@""];
	[item setSubmenu:menu];
	[(NSMenu *)parent addItem:item];
	return menu;
}

/*
	`key`: a single character for the Cmd-key equivalent, or NULL/"" for
	none. `mods` is a bitmask: 1 = Command, 2 = Shift, 4 = Option,
	8 = Control. Command is not implied - pass it explicitly - so an item
	can carry a bare function-key equivalent if one is ever wanted.
*/
void bx1_nmenu_add_item(void *menu, const char *title, int tag, const char *key, int mods)
{
	NSMenuItem *item;

	ensure_globals();
	if (menu == NULL) {
		return;
	}
	item = [[NSMenuItem alloc] initWithTitle:bx1_ns_string(title)
		action:@selector(menuAction:) keyEquivalent:@""];
	[item setTarget:target];
	[item setTag:tag];
	if (key != NULL && key[0] != '\0') {
		NSEventModifierFlags mask = 0;
		if (mods & 1) mask |= NSEventModifierFlagCommand;
		if (mods & 2) mask |= NSEventModifierFlagShift;
		if (mods & 4) mask |= NSEventModifierFlagOption;
		if (mods & 8) mask |= NSEventModifierFlagControl;
		[item setKeyEquivalent:[NSString stringWithUTF8String:key]];
		[item setKeyEquivalentModifierMask:mask];
	}
	[(NSMenu *)menu addItem:item];
	[items_by_tag setObject:item forKey:[NSNumber numberWithInt:tag]];
}

// Registered under a tag like any other item so it can be hidden, which
// matters for a separator that only makes sense when the optional section
// below it is showing.
void bx1_nmenu_add_separator(void *menu, int tag)
{
	NSMenuItem *item;

	ensure_globals();
	if (menu == NULL) {
		return;
	}
	item = [NSMenuItem separatorItem];
	[(NSMenu *)menu addItem:item];
	if (tag != 0) {
		[items_by_tag setObject:item forKey:[NSNumber numberWithInt:tag]];
	}
}

static NSMenuItem *item_for_tag(int tag)
{
	if (items_by_tag == nil) {
		return nil;
	}
	return [items_by_tag objectForKey:[NSNumber numberWithInt:tag]];
}

void bx1_nmenu_set_checked(int tag, int checked)
{
	[item_for_tag(tag) setState:(checked ? NSControlStateValueOn : NSControlStateValueOff)];
}

int bx1_nmenu_get_checked(int tag)
{
	NSMenuItem *item = item_for_tag(tag);
	return (item != nil && [item state] == NSControlStateValueOn) ? 1 : 0;
}

void bx1_nmenu_set_enabled(int tag, int enabled)
{
	[item_for_tag(tag) setEnabled:(enabled != 0)];
}

// Hiding rather than disabling is how the original renders its optional
// sections: the D88 bank list and the recent-file entries simply are not
// there when they do not apply (winmain.cpp rebuilds the menu tail each
// time). AppKit collapses hidden items out of the layout, giving the same
// result without rebuilding anything.
void bx1_nmenu_set_hidden(int tag, int hidden)
{
	[item_for_tag(tag) setHidden:(hidden != 0)];
}

void bx1_nmenu_set_item_title(int tag, const char *title)
{
	[item_for_tag(tag) setTitle:bx1_ns_string(title)];
}
