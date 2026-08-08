/*
	BubiX1turboZ - menus built directly as NSMenu/NSMenuItem objects.

	This exists because the original eX1turboZ menu bar this app mirrors is
	two levels deep (Control > Save State > State 0, Device > Sound > PSG,
	...) and libui-ng - the library behind uing, which owns the rest of the
	UI - has no submenu API at all: uiMenuAppendItem only ever appends a
	flat item to a top-level menu (verified in uing 0.8.2's bundled
	libui/darwin/menu.m). Phase 6 worked around that with flat fixed slots;
	that does not scale to the full original structure.

	What libui *does* do is build the menu bar out of ordinary AppKit
	objects, which cocoamenu.m already reaches into for shortcuts and
	renaming. So the menus here are simply appended to [NSApp mainMenu]
	alongside libui's own. libui keeps the application menu (About, Quit) -
	it relocates those items there itself and handles their actions - and
	everything else is built through this file.

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

// Every menu created here turns off Cocoa's automatic item validation. With
// it on (the default), AppKit re-derives each item's enabled state from its
// target/action right before display and discards any manual setEnabled:,
// and a botched modal session from a file dialog makes it disable the whole
// bar - see cocoamenu.m's bx1_menu_disable_autoenable_all for the full
// story. Nothing here wants automatic validation.
static NSMenu *make_menu(const char *title)
{
	NSMenu *menu = [[NSMenu alloc] initWithTitle:[NSString stringWithUTF8String:title]];
	[menu setAutoenablesItems:NO];
	return menu;
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
	item = [[NSMenuItem alloc] initWithTitle:[NSString stringWithUTF8String:title]
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
	item = [[NSMenuItem alloc] initWithTitle:[NSString stringWithUTF8String:title]
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
	item = [[NSMenuItem alloc] initWithTitle:[NSString stringWithUTF8String:title]
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
	[item_for_tag(tag) setTitle:[NSString stringWithUTF8String:title]];
}
