/*
	BubiX1turboZ - direct NSMenuItem manipulation, for the handful of
	things libui-ng (uing's backing library) doesn't expose an API for:

	1. Keyboard shortcuts. libui-ng creates every NSMenuItem with an empty
	   key equivalent and has no API to set one (verified in phase 1.2 -
	   see docs/dev/DevelopmentPlan.md, "libui-ng はメニューにキーボード
	   ショートカットを一切付けない").
	2. Renaming an item after creation (needed for the "Recent Files"
	   submenu to update within a running session - uing's MenuItem has
	   no `title=` setter).

	Both look up items by matching a stable prefix of their current title
	(uing itself never changes titles, so the prefix chosen at menu-build
	time stays valid across renames).
*/

#import <Cocoa/Cocoa.h>

static NSMenuItem *find_item(const char *menu_title, const char *item_prefix)
{
	NSMenu *bar;
	NSMenuItem *top = nil;
	NSString *prefix;

	if (NSApp == nil) {
		return nil;
	}
	bar = [NSApp mainMenu];
	if (bar == nil) {
		return nil;
	}

	if (menu_title == NULL) {
		// The application menu is always the first item of the menu bar.
		if ([[bar itemArray] count] == 0) {
			return nil;
		}
		top = [[bar itemArray] objectAtIndex:0];
	} else {
		NSString *wanted = [NSString stringWithUTF8String:menu_title];
		for (NSMenuItem *candidate in [bar itemArray]) {
			if ([[candidate title] isEqualToString:wanted]) {
				top = candidate;
				break;
			}
		}
	}
	if (top == nil || [top submenu] == nil) {
		return nil;
	}

	prefix = [NSString stringWithUTF8String:item_prefix];
	for (NSMenuItem *item in [[top submenu] itemArray]) {
		if ([[item title] hasPrefix:prefix]) {
			return item;
		}
	}
	return nil;
}

int bx1_menu_set_key_equivalent(const char *menu_title, const char *item_prefix,
	const char *key, int with_shift)
{
	NSMenuItem *item = find_item(menu_title, item_prefix);
	if (item == nil) {
		return 0;
	}
	NSEventModifierFlags mask = NSEventModifierFlagCommand;
	if (with_shift) {
		mask |= NSEventModifierFlagShift;
	}
	[item setKeyEquivalent:[NSString stringWithUTF8String:key]];
	[item setKeyEquivalentModifierMask:mask];
	return 1;
}

int bx1_menu_set_title(const char *menu_title, const char *item_prefix, const char *new_title)
{
	NSMenuItem *item = find_item(menu_title, item_prefix);
	if (item == nil) {
		return 0;
	}
	[item setTitle:[NSString stringWithUTF8String:new_title]];
	return 1;
}

int bx1_menu_set_enabled(const char *menu_title, const char *item_prefix, int enabled)
{
	NSMenuItem *item = find_item(menu_title, item_prefix);
	if (item == nil) {
		return 0;
	}
	[item setEnabled:(enabled != 0)];
	return 1;
}

void bx1_menu_disable_autoenable_all(void)
{
	NSMenu *bar;

	if (NSApp == nil) {
		return;
	}
	bar = [NSApp mainMenu];
	if (bar == nil) {
		return;
	}
	// NSMenu's default autoenablesItems (YES) re-derives every item's
	// enabled state from its target/action pair right before the menu is
	// displayed, silently discarding any manual setEnabled: call on an
	// item that has one (which every libui-ng item does). This alone
	// would just make bx1_menu_set_enabled a no-op, but there is a worse
	// failure mode: libui-ng's file-open dialog (uiOpenFile) can leave
	// NSApp's modal-session bookkeeping in a broken state on close
	// (logged by AppKit as "modalSession has been exited prematurely" -
	// reproduced with nothing but the stock File > Open Floppy flow, so
	// this is not specific to any one dialog call site). While NSApp
	// believes a modal session is still active, autoenablesItems treats
	// every item outside that phantom modal window as invalid and
	// disables it - which reads as "the entire menu bar is now dead"
	// after using any Open/Save dialog. Turning autoenablesItems off for
	// every submenu removes the dependency on that bookkeeping entirely;
	// nothing in this app relies on Cocoa's automatic validation, so
	// there is no behavior this disables that was ever wanted.
	for (NSMenuItem *top in [bar itemArray]) {
		if ([top submenu] != nil) {
			[[top submenu] setAutoenablesItems:NO];
		}
	}
}
