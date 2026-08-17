/*
	BubiX1turboZ - the host's preferred UI language on macOS.

	The environment is not a usable source for this on a Mac: an .app
	launched from the Finder or the Dock inherits none of the LANG /
	LC_MESSAGES variables a shell would set, so a POSIX-style lookup reports
	English for a Japanese user and only works when the binary is started
	from a terminal. NSLocale's preferredLanguages is the list System
	Settings > General > Language & Region actually edits.
*/

#import <Foundation/Foundation.h>
#include <string.h>

/*
	The first preferred language as a BCP 47 tag ("ja-JP"), or "" when the
	system offers none. The result points at a static buffer owned by this
	file - the caller neither frees nor keeps it beyond the copy it makes,
	which is what lets it stay a plain `const char *` across the FFI.
*/
const char *bx1_preferred_language(void)
{
	static char tag[64];

	@autoreleasepool {
		NSArray<NSString *> *languages = [NSLocale preferredLanguages];
		const char *utf8;

		tag[0] = '\0';
		if ([languages count] == 0) {
			return tag;
		}
		utf8 = [[languages objectAtIndex:0] UTF8String];
		if (utf8 == NULL) {
			return tag;
		}
		strncpy(tag, utf8, sizeof(tag) - 1);
		tag[sizeof(tag) - 1] = '\0';
	}
	return tag;
}
