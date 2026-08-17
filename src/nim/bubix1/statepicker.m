/*
	BubiX1turboZ - the save state slot picker.

	Bubilator88 presents its ten slots as a grid of thumbnails
	(Views/SaveStateSheetView.swift): each cell is the screen as it was,
	with a translucent bar along the bottom carrying the slot number, the
	time it was taken, and what was in the drives. This is that, in AppKit.

	Built on NSAlert with an accessory view rather than as a window of its
	own, for the reason filedialog.m gives at length: this app's only
	uiWindow is a placeholder libui needs for the menu bar, so there is
	nothing to hang a sheet on, and NSAlert's app-modal session is the one
	path already proven not to leave NSApp believing a modal is still live
	(see cocoamenu.m's bx1_menu_disable_autoenable_all for what that
	looks like when it goes wrong).
*/

#import <Cocoa/Cocoa.h>
#include "statepicker.h"

/*
	Defined in nativemenu.m. Disk names arrive here as the raw bytes of a
	D88 header - Shift-JIS in practice - and this is the single place in
	the app that decodes them (diskset.nim documents why it is kept to
	one). Slot captions and dates are plain ASCII but go through it too,
	since it handles UTF-8 correctly as well.
*/
extern NSString *bx1_ns_string(const char *bytes);

// Window and cell geometry, following Bubilator88's sheet: 580x520 with
// two columns of cells. Each cell is 8:5 like the emulated screen, so a
// 320x200 thumbnail lands in it without letterboxing.
static const CGFloat WindowWidth = 580.0;
static const CGFloat WindowHeight = 520.0;
static const CGFloat HeaderHeight = 48.0;
static const CGFloat FooterHeight = 52.0;
static const CGFloat Margin = 16.0;
static const CGFloat CancelWidth = 90.0;
static const CGFloat CancelHeight = 24.0;
static const CGFloat CellWidth = 248.0;
static const CGFloat CellHeight = 155.0;
static const CGFloat CellGap = 12.0;
static const CGFloat ScrollerWidth = 16.0;
static const CGFloat BarHeight = 22.0;
static const CGFloat Columns = 2.0;
// Distinct from every NSModalResponse AppKit hands out on its own.
static const NSModalResponse PickedResponse = 9000;

@interface Bx1StatePickerTarget : NSObject
@property (assign) NSInteger picked;
- (void)pick:(id)sender;
- (void)cancel:(id)sender;
@end

@implementation Bx1StatePickerTarget
- (void)pick:(id)sender
{
	self.picked = [sender tag];
	[NSApp stopModalWithCode:PickedResponse];
}

- (void)cancel:(id)sender
{
	(void)sender;
	[NSApp stopModalWithCode:NSModalResponseCancel];
}
@end

static NSDictionary *text_attributes(CGFloat size, BOOL bold, CGFloat alpha)
{
	NSMutableParagraphStyle *style;

	style = [[[NSMutableParagraphStyle alloc] init] autorelease];
	[style setLineBreakMode:NSLineBreakByTruncatingTail];
	return @{
		NSFontAttributeName: bold ? [NSFont boldSystemFontOfSize:size]
		                          : [NSFont systemFontOfSize:size],
		NSForegroundColorAttributeName: [NSColor colorWithWhite:1.0 alpha:alpha],
		NSParagraphStyleAttributeName: style,
	};
}

/*
	The cell's whole appearance, drawn into one image: the thumbnail (or an
	"Empty" placeholder) with the info bar composited over its bottom edge.
	Doing it here rather than with layered views keeps each cell a plain
	NSButton, which is what makes the grid below as simple as it is.
*/
static NSImage *cell_image(const bx1_state_slot *slot, NSString *empty_label)
{
	NSImage *image;
	NSImage *thumbnail = nil;
	NSRect bounds = NSMakeRect(0.0, 0.0, CellWidth, CellHeight);
	NSRect bar = NSMakeRect(0.0, 0.0, CellWidth, BarHeight);
	NSBezierPath *clip;
	NSString *left;
	NSString *right;
	NSSize rightSize;
	CGFloat rightWidth;

	if (slot->png != NULL && slot->png_len > 0) {
		NSData *data = [NSData dataWithBytes:slot->png length:(NSUInteger)slot->png_len];
		thumbnail = [[[NSImage alloc] initWithData:data] autorelease];
	}

	image = [[[NSImage alloc] initWithSize:bounds.size] autorelease];
	[image lockFocus];

	clip = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:6.0 yRadius:6.0];
	[clip addClip];

	if (thumbnail != nil) {
		// Emulator output is pixel art; smoothing it on the way down to
		// thumbnail size makes it look like a photograph of a screen.
		[[NSGraphicsContext currentContext]
			setImageInterpolation:NSImageInterpolationNone];
		[thumbnail drawInRect:bounds fromRect:NSZeroRect
		            operation:NSCompositingOperationSourceOver fraction:1.0];
	} else {
		[[NSColor colorWithWhite:0.0 alpha:0.7] setFill];
		NSRectFill(bounds);
		NSDictionary *attrs = text_attributes(15.0, NO, 0.3);
		NSSize size = [empty_label sizeWithAttributes:attrs];
		[empty_label drawAtPoint:NSMakePoint((CellWidth - size.width) / 2.0,
		                                     (CellHeight - size.height) / 2.0)
		          withAttributes:attrs];
	}

	[[NSColor colorWithWhite:0.0 alpha:0.55] setFill];
	NSRectFillUsingOperation(bar, NSCompositingOperationSourceOver);

	// "Slot 3   08/15 12:34" on the left, the disks on the right - the
	// order Bubilator88's SlotCell uses, and the one that stays readable
	// when a long title has to be truncated.
	left = bx1_ns_string(slot->caption);
	if (slot->detail != NULL && slot->detail[0] != '\0') {
		left = [left stringByAppendingFormat:@"   %@", bx1_ns_string(slot->detail)];
	}
	right = slot->disks != NULL ? bx1_ns_string(slot->disks) : @"";

	rightWidth = 0.0;
	if ([right length] > 0) {
		NSDictionary *attrs = text_attributes(10.0, YES, 0.9);
		rightSize = [right sizeWithAttributes:attrs];
		rightWidth = rightSize.width;
		if (rightWidth > CellWidth * 0.5) {
			rightWidth = CellWidth * 0.5;
		}
		[right drawInRect:NSMakeRect(CellWidth - 8.0 - rightWidth, 5.0,
		                             rightWidth, BarHeight - 8.0)
		   withAttributes:attrs];
	}
	[left drawInRect:NSMakeRect(8.0, 5.0,
	                            CellWidth - 24.0 - rightWidth, BarHeight - 8.0)
	  withAttributes:text_attributes(10.0, YES, 0.95)];

	[[NSColor colorWithWhite:1.0 alpha:0.15] setStroke];
	[clip setLineWidth:1.0];
	[clip stroke];

	[image unlockFocus];
	return image;
}

// A hairline the width of the window, the way Bubilator88's sheet puts a
// Divider under its title and above its button row.
static NSBox *divider(NSRect frame)
{
	NSBox *box = [[[NSBox alloc] initWithFrame:frame] autorelease];

	[box setBoxType:NSBoxSeparator];
	return box;
}

static NSTextField *heading(NSRect frame, NSString *text)
{
	NSTextField *label = [[[NSTextField alloc] initWithFrame:frame] autorelease];

	[label setStringValue:text];
	[label setEditable:NO];
	[label setSelectable:NO];
	[label setBordered:NO];
	[label setDrawsBackground:NO];
	[label setAlignment:NSTextAlignmentCenter];
	[label setFont:[NSFont boldSystemFontOfSize:
		[NSFont systemFontSizeForControlSize:NSControlSizeRegular]]];
	[label setTextColor:[NSColor labelColor]];
	return label;
}

/*
	Returns the chosen slot index, or -1 if the user cancelled. A slot with
	enabled == 0 is drawn dimmed and cannot be picked, which is how the
	Load side presents an empty slot (Bubilator88 does the same rather than
	hiding it - the slot number is half the point of the grid).

	A window of its own rather than an NSAlert: an alert insists on showing
	the application icon, and centres a lone button instead of putting it
	where a dialog's Cancel belongs. Bubilator88's sheet is a title, a
	divider, the grid, a divider, and Cancel on the right - which is what
	this builds. The modal session is still NSApp's own (runModalForWindow:
	/ stopModal), the one this app has verified does not leave the menu bar
	disabled behind it.
*/
int bx1_state_picker(const char *title, const bx1_state_slot *slots, int count,
                     const char *cancel_label, const char *empty_label)
{
	@autoreleasepool {
		NSString *empty = bx1_ns_string(empty_label);
		NSWindow *window;
		NSView *root;
		Bx1StatePickerTarget *target;
		NSScrollView *scroll;
		NSButton *cancel;
		NSView *content;
		NSRect frame = NSMakeRect(0.0, 0.0, WindowWidth, WindowHeight);
		CGFloat gridWidth = Columns * (CellWidth + CellGap) + CellGap;
		CGFloat gridBottom = FooterHeight;
		CGFloat gridHeight = WindowHeight - HeaderHeight - FooterHeight;
		CGFloat contentHeight;
		NSModalResponse response;
		int i;

		if (slots == NULL || count <= 0) {
			return -1;
		}

		target = [[[Bx1StatePickerTarget alloc] init] autorelease];
		[target setPicked:-1];

		contentHeight = ceil((CGFloat)count / Columns) * (CellHeight + CellGap) + CellGap;
		content = [[[NSView alloc] initWithFrame:
			NSMakeRect(0.0, 0.0, gridWidth, contentHeight)] autorelease];

		for (i = 0; i < count; i++) {
			NSButton *button;
			CGFloat column = (CGFloat)(i % (int)Columns);
			CGFloat row = (CGFloat)(i / (int)Columns);
			// NSView is bottom-up, the grid reads top-down.
			CGFloat y = contentHeight - (row + 1.0) * (CellHeight + CellGap);

			button = [[[NSButton alloc] initWithFrame:
				NSMakeRect(CellGap + column * (CellWidth + CellGap), y,
				           CellWidth, CellHeight)] autorelease];
			[button setBordered:NO];
			[button setImagePosition:NSImageOnly];
			[button setImage:cell_image(&slots[i], empty)];
			[button setTag:i];
			[button setTarget:target];
			[button setAction:@selector(pick:)];
			[button setEnabled:slots[i].enabled != 0];
			// setEnabled alone leaves an image button looking active.
			[button setAlphaValue:slots[i].enabled != 0 ? 1.0 : 0.4];
			[content addSubview:button];
		}

		scroll = [[[NSScrollView alloc] initWithFrame:
			NSMakeRect((WindowWidth - gridWidth - ScrollerWidth) / 2.0, gridBottom,
			           gridWidth + ScrollerWidth, gridHeight)] autorelease];
		[scroll setHasVerticalScroller:YES];
		[scroll setDrawsBackground:NO];
		[scroll setDocumentView:content];
		[[scroll contentView] scrollToPoint:
			NSMakePoint(0.0, contentHeight - gridHeight)];

		cancel = [[[NSButton alloc] initWithFrame:
			NSMakeRect(WindowWidth - Margin - CancelWidth,
			           (FooterHeight - CancelHeight) / 2.0,
			           CancelWidth, CancelHeight)] autorelease];
		[cancel setBezelStyle:NSBezelStyleRounded];
		[cancel setTitle:bx1_ns_string(cancel_label)];
		[cancel setKeyEquivalent:@"\033"];
		[cancel setTarget:target];
		[cancel setAction:@selector(cancel:)];

		root = [[[NSView alloc] initWithFrame:frame] autorelease];
		[root addSubview:heading(NSMakeRect(0.0, WindowHeight - HeaderHeight + 14.0,
		                                    WindowWidth, 20.0),
		                         bx1_ns_string(title))];
		[root addSubview:divider(NSMakeRect(0.0, WindowHeight - HeaderHeight,
		                                    WindowWidth, 1.0))];
		[root addSubview:scroll];
		[root addSubview:divider(NSMakeRect(0.0, FooterHeight, WindowWidth, 1.0))];
		[root addSubview:cancel];

		window = [[NSWindow alloc]
			initWithContentRect:frame
			          styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskFullSizeContentView
			            backing:NSBackingStoreBuffered
			              defer:NO];
		// A sheet has no title bar; this is the closest a standalone window
		// gets, and it keeps the whole top edge draggable.
		[window setTitlebarAppearsTransparent:YES];
		[window setTitleVisibility:NSWindowTitleHidden];
		[window setContentView:root];
		[window center];

		response = [NSApp runModalForWindow:window];
		[window orderOut:nil];
		[window release];

		if (response != PickedResponse) {
			return -1;
		}
		return (int)[target picked];
	}
}
