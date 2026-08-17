/*
	BubiX1turboZ - native open/save panels and alerts.

	Replaces uing's uiOpenFile / uiSaveFile / uiMsgBox, which all funnel
	through libui's runSavePanel and open as a *sheet* attached to the
	uiWindow passed in (libui/darwin/stddialogs.m:
	beginSheetModalForWindow:). This app's only uiWindow exists solely so
	libui will build a menu bar; it holds nothing worth showing, and libui
	places it wherever it likes - in practice a corner of the screen. A file
	dialog dropping out of that stray window is what the user sees as "the
	Open dialog is wrong, and there is an odd window".

	Running the panels app-modal instead puts them where macOS puts an
	app-modal panel, needs no parent window at all, and avoids libui's
	runModalForWindow bookkeeping - the same bookkeeping that leaves NSApp
	believing a modal session is still live and greys out the whole menu
	bar afterwards (see cocoamenu.m's bx1_menu_disable_autoenable_all).
*/

#import <Cocoa/Cocoa.h>

// The caller owns the returned string and must free it with
// bx1_dialog_free(). NULL means the user cancelled.
static char *copy_path(NSURL *url)
{
	const char *utf8;
	char *copy;
	size_t len;

	if (url == nil) {
		return NULL;
	}
	utf8 = [[url path] UTF8String];
	if (utf8 == NULL) {
		return NULL;
	}
	len = strlen(utf8);
	copy = (char *)malloc(len + 1);
	if (copy != NULL) {
		memcpy(copy, utf8, len + 1);
	}
	return copy;
}

/*
	`extensions`: comma-separated list without dots ("d88,d77,zip"), or
	NULL/"" to accept anything. Filtering here is what lets one Insert
	action cover disk images, playlists and archives alike while still
	greying out files the app cannot mount.
*/
static void set_allowed_types(NSSavePanel *panel, const char *extensions)
{
	NSMutableArray *types;
	NSArray *parts;

	if (extensions == NULL || extensions[0] == '\0') {
		return;
	}
	types = [NSMutableArray array];
	parts = [[NSString stringWithUTF8String:extensions] componentsSeparatedByString:@","];
	for (NSString *ext in parts) {
		NSString *trimmed = [ext stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceCharacterSet]];
		if ([trimmed length] > 0) {
			[types addObject:trimmed];
		}
	}
	if ([types count] > 0) {
		[panel setAllowedFileTypes:types];
	}
}

char *bx1_dialog_open_file(const char *extensions)
{
	@autoreleasepool {
		NSOpenPanel *panel = [NSOpenPanel openPanel];
		[panel setCanChooseFiles:YES];
		[panel setCanChooseDirectories:NO];
		[panel setAllowsMultipleSelection:NO];
		[panel setResolvesAliases:YES];
		[panel setTreatsFilePackagesAsDirectories:YES];
		set_allowed_types(panel, extensions);
		if ([panel runModal] != NSModalResponseOK) {
			return NULL;
		}
		return copy_path([panel URL]);
	}
}

char *bx1_dialog_save_file(const char *extensions, const char *suggested_name)
{
	@autoreleasepool {
		NSSavePanel *panel = [NSSavePanel savePanel];
		[panel setCanCreateDirectories:YES];
		[panel setExtensionHidden:NO];
		[panel setTreatsFilePackagesAsDirectories:YES];
		set_allowed_types(panel, extensions);
		if (suggested_name != NULL && suggested_name[0] != '\0') {
			[panel setNameFieldStringValue:[NSString stringWithUTF8String:suggested_name]];
		}
		if ([panel runModal] != NSModalResponseOK) {
			return NULL;
		}
		return copy_path([panel URL]);
	}
}

/*
	Disk chooser for an image that turned out to hold several disks.

	Defined in nativemenu.m, which needs the same decoding for the same D88
	names; see the comment there for why raw Shift-JIS reaches this layer.
*/
extern NSString *bx1_ns_string(const char *bytes);

/*
	`rows` are display strings, one per disk, already carrying their index so
	no two are equal - NSPopUpButton silently drops an item whose title
	duplicates an existing one, which would otherwise make two identically
	named disks unreachable.

	Returns the chosen row, or -1 if the user cancelled. A pop-up rather than
	a table keeps this to an app-modal alert, matching the file panels above:
	no parent window, no libui modal bookkeeping.

	Both button titles arrive from the caller. This file is the macOS
	backend of a UI meant to grow GTK and Win32 siblings, so the words it
	shows come from the app's own catalog (src/nim/bubix1/i18n.nim) rather
	than from anything only AppKit can read.
*/
int bx1_dialog_choose_disk(const char *title, const char *const *rows, int count,
                           int initial, const char *insert_label,
                           const char *cancel_label)
{
	@autoreleasepool {
		NSAlert *alert;
		NSPopUpButton *popup;
		int i;

		if (rows == NULL || count <= 0) {
			return -1;
		}
		alert = [[[NSAlert alloc] init] autorelease];
		[alert setMessageText:bx1_ns_string(title)];
		[alert addButtonWithTitle:bx1_ns_string(insert_label)];
		[alert addButtonWithTitle:bx1_ns_string(cancel_label)];

		popup = [[[NSPopUpButton alloc]
			initWithFrame:NSMakeRect(0, 0, 360, 26) pullsDown:NO] autorelease];
		for (i = 0; i < count; i++) {
			[popup addItemWithTitle:bx1_ns_string(rows[i])];
		}
		if (initial >= 0 && initial < count) {
			[popup selectItemAtIndex:initial];
		}
		[alert setAccessoryView:popup];

		if ([alert runModal] != NSAlertFirstButtonReturn) {
			return -1;
		}
		return (int)[popup indexOfSelectedItem];
	}
}

void bx1_dialog_free(char *text)
{
	free(text);
}

void bx1_dialog_message(const char *title, const char *body, const char *ok_label)
{
	@autoreleasepool {
		NSAlert *alert = [[[NSAlert alloc] init] autorelease];
		[alert setMessageText:bx1_ns_string(title)];
		[alert setInformativeText:bx1_ns_string(body)];
		[alert addButtonWithTitle:bx1_ns_string(ok_label)];
		[alert runModal];
	}
}

/*
	The startup alert shown when the BIOS ROM is missing. Separate from
	bx1_dialog_message because it carries a second button that reveals
	`folder` in the Finder: telling someone which folder to fill is far
	less useful than putting that folder in front of them, and the folder
	is one the app just created inside ~/Library, which is not somewhere a
	user can conveniently navigate to by hand.

	Returns 1 if the folder was revealed, 0 if the user dismissed the
	alert. Both answers end the same way for the caller - the emulator
	cannot start without the ROM - so this reports what happened rather
	than asking the caller to act on it.

	This one runs before the main loop, which the other dialogs here do
	not: uiInit has created NSApp but nothing has called -run yet, and an
	NSApp that has not finished launching puts up no window at all - the
	process simply sits in runModal with nothing on screen. -finishLaunching
	is the part of -run that makes the app able to show one; calling it
	early is safe because -run skips it once it has been done.
*/
int bx1_dialog_missing_rom(const char *title, const char *body, const char *folder,
                           const char *open_label, const char *quit_label)
{
	@autoreleasepool {
		NSAlert *alert;
		NSString *path;

		if (![NSApp isRunning]) {
			// Regular, not the policy a process launched outside a bundle
			// gets by default: an accessory application shows no window
			// and cannot be activated, so the alert would never appear.
			// SDL_Init normally sets this, and it has not run yet here.
			[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
			[NSApp finishLaunching];
		}
		// An app with no window yet is not necessarily frontmost, which
		// would leave the alert behind whatever the user was looking at.
		[NSApp activateIgnoringOtherApps:YES];

		alert = [[[NSAlert alloc] init] autorelease];
		[alert setAlertStyle:NSAlertStyleWarning];
		[alert setMessageText:bx1_ns_string(title)];
		[alert setInformativeText:bx1_ns_string(body)];
		// First button added is the default one, and opening the folder is
		// the only action that gets the user closer to a running emulator.
		[alert addButtonWithTitle:bx1_ns_string(open_label)];
		[alert addButtonWithTitle:bx1_ns_string(quit_label)];

		if ([alert runModal] != NSAlertFirstButtonReturn) {
			return 0;
		}
		if (folder == NULL || folder[0] == '\0') {
			return 0;
		}
		path = [NSString stringWithUTF8String:folder];
		// selectFile:nil opens the folder itself rather than selecting it
		// inside its parent, which is what "open the ROM folder" means.
		[[NSWorkspace sharedWorkspace] selectFile:nil
						 inFileViewerRootedAtPath:path];
		return 1;
	}
}
