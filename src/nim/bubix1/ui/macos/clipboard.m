/*
	BubiX1turboZ - reading the system pasteboard.

	Needed by the original's Control > Paste, which types the clipboard's
	text into the guest through the core's auto key facility. Nim's standard
	library has no clipboard access and SDL2 offers no plain text retrieval
	that works without a window focused, so this is a direct NSPasteboard
	read.
*/

#import <Cocoa/Cocoa.h>

/*
	Returns the clipboard's contents as UTF-8, or NULL if it holds no text.
	The returned buffer is owned by the caller and must be released with
	bx1_clipboard_free().
*/
char *bx1_clipboard_text(void)
{
	NSString *text = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
	const char *utf8;
	char *copy;
	size_t len;

	if (text == nil) {
		return NULL;
	}
	utf8 = [text UTF8String];
	if (utf8 == NULL) {
		return NULL;
	}
	// The NSString's own buffer is autoreleased; hand back a copy the
	// caller controls the lifetime of instead of a pointer that dies at the
	// next pool drain.
	len = strlen(utf8);
	copy = (char *)malloc(len + 1);
	if (copy == NULL) {
		return NULL;
	}
	memcpy(copy, utf8, len + 1);
	return copy;
}

void bx1_clipboard_free(char *text)
{
	free(text);
}
