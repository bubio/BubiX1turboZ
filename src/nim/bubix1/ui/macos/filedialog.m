/*
	BubiX1turboZ - native open/save panels and alerts.

	The panels hang off the emulator's window as sheets. That window is
	SDL's rather than one this app made for itself, so the Nim side
	registers it here once it exists (bx1_dialog_set_parent) and SDL_syswm
	turns the handle into the NSWindow AppKit wants; nothing else in this
	file knows about SDL. With no window to attach to - the state
	bx1_dialog_missing_rom runs in, since it is shown before the emulator
	window is created - every dialog here falls back to app-modal.

	A sheet is asynchronous where the rest of this app is not: each
	function below returns the user's answer, and the Nim facade they back
	is shaped that way for its Linux and Windows siblings too. So the sheet
	is begun and then a nested modal session runs until the completion
	handler stops it, which keeps the call synchronous.

	That session is NSApp's own (runModalForWindow: / stopModalWithCode:),
	the one path this app has verified it can open and close cleanly: a
	session left half-open makes Cocoa's automatic menu validation disable
	the entire menu bar afterwards (see the make_menu comment in
	nativemenu.m).
*/

#import <Cocoa/Cocoa.h>
#include <SDL.h>
#include <SDL_syswm.h>

// The emulator window, as SDL knows it. NULL until the Nim side registers
// it, which it does as soon as the window is on screen.
static SDL_Window *emulator_window = NULL;

void bx1_dialog_set_parent(void *window)
{
	emulator_window = (SDL_Window *)window;
}

/*
	The window a sheet should hang from, or nil when there is none to use.

	Deliberately not [NSApp mainWindow]: the volume panel is a window of
	this app's own and can be the main one, and a file panel that opened
	as a sheet on the volume slider would be attached to the wrong thing
	entirely. Asking SDL names the emulator window and only that.
*/
NSWindow *bx1_dialog_parent_window(void)
{
	SDL_SysWMinfo info;
	NSWindow *window;

	if (emulator_window == NULL) {
		return nil;
	}
	SDL_VERSION(&info.version);
	if (!SDL_GetWindowWMInfo(emulator_window, &info)) {
		return nil;
	}
	if (info.subsystem != SDL_SYSWM_COCOA) {
		return nil;
	}
	window = info.info.cocoa.window;
	// A sheet on a hidden or minimised window would be out of reach until
	// the window came back, with the emulation loop blocked meanwhile.
	if (window == nil || ![window isVisible] || [window isMiniaturized]) {
		return nil;
	}
	return window;
}

/*
	One dialog at a time. The modal session already stops a second menu
	action from firing while one is up - which is what the app-modal
	panels relied on too - but a sheet is queued rather than refused when
	its parent already has one, and the nested session below would then be
	waiting on a window that is not on screen yet. That is a hang, and it
	costs two lines to rule out. Every caller treats the cancel answer as
	"the user chose nothing", which is exactly what a swallowed request is.
*/
static BOOL dialog_running = NO;

// Both runners below return what the dialog itself would have returned
// app-modal, so their callers read the answer the same way either way.
static NSModalResponse run_panel(NSSavePanel *panel)
{
	NSWindow *parent;
	__block NSModalResponse answer = NSModalResponseCancel;

	if (dialog_running) {
		return NSModalResponseCancel;
	}
	dialog_running = YES;
	parent = bx1_dialog_parent_window();
	if (parent == nil) {
		answer = [panel runModal];
	} else {
		[panel beginSheetModalForWindow:parent
				  completionHandler:^(NSModalResponse response) {
			answer = response;
			[NSApp stopModalWithCode:response];
		}];
		[NSApp runModalForWindow:panel];
	}
	dialog_running = NO;
	return answer;
}

static NSModalResponse run_alert(NSAlert *alert)
{
	NSWindow *parent;
	__block NSModalResponse answer = NSModalResponseCancel;

	if (dialog_running) {
		return NSModalResponseCancel;
	}
	dialog_running = YES;
	parent = bx1_dialog_parent_window();
	if (parent == nil) {
		answer = [alert runModal];
	} else {
		[alert beginSheetModalForWindow:parent
				  completionHandler:^(NSModalResponse response) {
			answer = response;
			[NSApp stopModalWithCode:response];
		}];
		[NSApp runModalForWindow:[alert window]];
	}
	dialog_running = NO;
	return answer;
}

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
		if (run_panel(panel) != NSModalResponseOK) {
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
		if (run_panel(panel) != NSModalResponseOK) {
			return NULL;
		}
		return copy_path([panel URL]);
	}
}

/*
	Folder chooser, for an action that writes several files at once and so
	has no single name to put in a Save panel.

	`prompt` is the default button's title, which is the only place a folder
	chooser can say what it is about to do - there is no file name field to
	label. Passed down from the message catalog like every other word here.
*/
char *bx1_dialog_choose_folder(const char *title, const char *prompt)
{
	@autoreleasepool {
		NSOpenPanel *panel = [NSOpenPanel openPanel];
		[panel setCanChooseFiles:NO];
		[panel setCanChooseDirectories:YES];
		[panel setAllowsMultipleSelection:NO];
		[panel setCanCreateDirectories:YES];
		[panel setResolvesAliases:YES];
		if (title != NULL && title[0] != '\0') {
			[panel setMessage:[NSString stringWithUTF8String:title]];
		}
		if (prompt != NULL && prompt[0] != '\0') {
			[panel setPrompt:[NSString stringWithUTF8String:prompt]];
		}
		if (run_panel(panel) != NSModalResponseOK) {
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
	a table keeps this to an NSAlert, which run_alert presents as a sheet on
	the emulator window like the file panels above.

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

		if (run_alert(alert) != NSAlertFirstButtonReturn) {
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
		run_alert(alert);
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

	This one runs before the main loop, and before the emulator window
	exists - so run_alert finds no window to hang a sheet on and shows it
	app-modal, which is where an alert with nothing behind it belongs
	anyway. That is safe because SDL_Init has already registered the
	application: it creates NSApp, sets the Regular activation policy an
	app needs to show a window at all, and calls -finishLaunching. Without
	those an alert never appears and the process simply sits in its modal
	session with nothing on screen, so this must not be called any earlier
	than that.
*/
int bx1_dialog_missing_rom(const char *title, const char *body, const char *folder,
                           const char *open_label, const char *quit_label)
{
	@autoreleasepool {
		NSAlert *alert;
		NSString *path;

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

		if (run_alert(alert) != NSAlertFirstButtonReturn) {
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
