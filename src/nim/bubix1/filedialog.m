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

void bx1_dialog_free(char *text)
{
	free(text);
}

void bx1_dialog_message(const char *title, const char *body)
{
	@autoreleasepool {
		NSAlert *alert = [[[NSAlert alloc] init] autorelease];
		[alert setMessageText:title != NULL ? [NSString stringWithUTF8String:title] : @""];
		[alert setInformativeText:body != NULL ? [NSString stringWithUTF8String:body] : @""];
		[alert addButtonWithTitle:@"OK"];
		[alert runModal];
	}
}
