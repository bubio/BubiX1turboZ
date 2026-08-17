/*
	BubiX1turboZ - the Host > Volume panel, built as AppKit objects.

	The original opens a modal dialog of per-device L/R trackbars
	(IDD_VOLUME in x1turboz.rc). Same idea here, as a modeless window built
	once at startup and shown on demand - it edits the running machine live,
	where the original edited a copy and committed it on OK.

	The panel owns no state beyond what the controls display. Every user
	change is reported to the Nim side through one of the callbacks below,
	which decides what to store and what to push to the machine; every
	programmatic change comes back in through bx1_volume_set_level. That
	keeps the mixing rules (master, L/R link, which channels this machine
	actually has) in one place, on the side that can see the VM.
*/

#import <Cocoa/Cocoa.h>

// Decodes a core string that may not be UTF-8; defined in nativemenu.m.
// The device captions come from the core's own sound_device_caption table.
extern NSString *bx1_ns_string(const char *bytes);

// `device` is the core's sound device index, or -1 for the master.
// `channel` is 0 for L and 1 for R, and is always 0 for the master.
typedef void (*bx1_volume_change_fn)(int device, int channel, int value);
typedef void (*bx1_volume_link_fn)(int linked);
typedef void (*bx1_volume_reset_fn)(void);

// Range matches the core's own clamp on set_sound_device_volume.
static const int kMinLevel = -40;
static const int kMaxLevel = 0;

// Plain frames rather than auto layout: the panel is a fixed stack of
// identical rows whose only flexible dimension is the slider's width, and
// a constraint system for that would be more machinery than geometry.
static const CGFloat kMargin = 20.0;    // window content inset
static const CGFloat kInnerWidth = 340.0; // content width inside a group box
static const CGFloat kRowHeight = 22.0;
static const CGFloat kRowGap = 4.0;
static const CGFloat kLabelWidth = 28.0;
static const CGFloat kLabelGap = 6.0;
static const CGFloat kBoxPadX = 6.0;
static const CGFloat kBoxPadY = 6.0;
static const CGFloat kGroupGap = 10.0;
static const CGFloat kBarHeight = 28.0;
static const CGFloat kButtonWidth = 96.0;

static bx1_volume_change_fn change_fn = NULL;
static bx1_volume_link_fn link_fn = NULL;
static bx1_volume_reset_fn reset_fn = NULL;

static NSWindow *panel = nil;
// tag -> NSSlider, so a level can be set or read without holding AppKit
// pointers across the FFI boundary. Tags encode the device and channel;
// see tag_for() below.
static NSMutableDictionary *sliders_by_tag = nil;
// The group boxes are stacked as they are added and only positioned once
// the total height is known, which is not until bx1_volume_end.
static NSMutableArray *boxes = nil;
static NSBox *master_box = nil;
static NSButton *link_button = nil;
static NSButton *reset_button = nil;
static BOOL placed = NO;

// Master is device -1, so the tag of every slider stays non-negative.
static int tag_for(int device, int channel)
{
	return (device + 1) * 2 + channel;
}

static NSSlider *slider_for(int device, int channel)
{
	if (sliders_by_tag == nil) {
		return nil;
	}
	return [sliders_by_tag objectForKey:
		[NSNumber numberWithInt:tag_for(device, channel)]];
}

/*
	Puts a slider's knob on the whole decibel it reports, and writes that
	number into its tooltip.

	The range is whole decibels but the control underneath is continuous, so
	a knob dragged to -21.8 reports (and applies, and copies to the other
	channel) -22 while sitting visibly short of it. Writing the value back
	moves the knob onto the step it actually means, which is also what makes
	two linked channels line up exactly. The tooltip is the only place this
	panel shows a number at all, matching the original's dialog (IDD_VOLUME
	is trackbars only).
*/
static int snap(NSSlider *slider)
{
	int value;

	if (slider == nil) {
		return 0;
	}
	value = (int)lround([slider doubleValue]);
	if (value < kMinLevel) {
		value = kMinLevel;
	}
	if (value > kMaxLevel) {
		value = kMaxLevel;
	}
	[slider setDoubleValue:value];
	[slider setToolTip:[NSString stringWithFormat:@"%d dB", value]];
	return value;
}

@interface BX1VolumeTarget : NSObject
- (void)sliderMoved:(id)sender;
- (void)linkToggled:(id)sender;
- (void)resetClicked:(id)sender;
@end

@implementation BX1VolumeTarget

- (void)sliderMoved:(id)sender
{
	NSSlider *slider = (NSSlider *)sender;
	int tag = (int)[slider tag];
	int value = snap(slider);

	if (change_fn != NULL) {
		change_fn(tag / 2 - 1, tag % 2, value);
	}
}

- (void)linkToggled:(id)sender
{
	if (link_fn != NULL) {
		link_fn([(NSButton *)sender state] == NSControlStateValueOn ? 1 : 0);
	}
}

- (void)resetClicked:(id)sender
{
	(void)sender;
	if (reset_fn != NULL) {
		reset_fn();
	}
}

@end

// Controls hold their target weakly, so this must outlive them all.
// Deliberately allocated once and never released.
static BX1VolumeTarget *target = nil;

void bx1_volume_set_callbacks(bx1_volume_change_fn change,
	bx1_volume_link_fn link, bx1_volume_reset_fn reset)
{
	change_fn = change;
	link_fn = link;
	reset_fn = reset;
}

static NSTextField *make_label(NSRect frame, NSString *text)
{
	NSTextField *label = [[NSTextField alloc] initWithFrame:frame];

	[label setStringValue:text];
	[label setBezeled:NO];
	[label setDrawsBackground:NO];
	[label setEditable:NO];
	[label setSelectable:NO];
	return label;
}

// One "L" / "R" label and the slider beside it, laid out from the top of
// `parent` downwards. `row` counts from 0.
static void add_row(NSView *parent, int row, NSString *label,
	int device, int channel)
{
	CGFloat height = [parent frame].size.height;
	CGFloat y = height - (row + 1) * kRowHeight - row * kRowGap;
	CGFloat sliderX = kLabelWidth + kLabelGap;
	NSTextField *caption;
	NSSlider *slider;

	caption = make_label(NSMakeRect(0.0, y, kLabelWidth, kRowHeight), label);
	[parent addSubview:caption];
	[caption release];

	slider = [[NSSlider alloc] initWithFrame:
		NSMakeRect(sliderX, y, kInnerWidth - sliderX, kRowHeight)];
	[slider setMinValue:kMinLevel];
	[slider setMaxValue:kMaxLevel];
	[slider setTag:tag_for(device, channel)];
	[slider setTarget:target];
	[slider setAction:@selector(sliderMoved:)];
	[parent addSubview:slider];
	[sliders_by_tag setObject:slider
		forKey:[NSNumber numberWithInt:tag_for(device, channel)]];
	[slider release];
}

/*
	A titled group box holding `rows` slider rows.

	The box is sized from the rows rather than the other way round, so the
	panel never has to hardcode what a group occupies on screen. That is
	-setFrameFromContentFrame: rather than -sizeToFit: the latter shrinks
	the box to enclose the subviews it can measure, which for a plain view
	holding no layout constraints is not the width the rows were laid out
	at, and the panel came out a fraction of its intended width.
*/
static NSBox *make_group(NSString *title, int device, int rows,
	NSString *const *labels)
{
	CGFloat innerHeight = rows * kRowHeight + (rows - 1) * kRowGap;
	NSRect inner = NSMakeRect(0.0, 0.0, kInnerWidth, innerHeight);
	NSView *content;
	NSBox *box;
	int i;

	// No autoresizing mask, deliberately. With one, the box stretches the
	// content view when it lays itself out and takes the sliders with it,
	// which put their right ends about ten points beyond the box's own
	// border. Every frame in this file is set explicitly instead.
	content = [[NSView alloc] initWithFrame:inner];
	for (i = 0; i < rows; i++) {
		add_row(content, i, labels[i], device, i);
	}
	box = [[NSBox alloc] initWithFrame:NSZeroRect];
	[box setTitle:title];
	[box setContentViewMargins:NSMakeSize(kBoxPadX, kBoxPadY)];
	[box setContentView:content];
	[content release];
	[box setFrameFromContentFrame:inner];
	return box;
}

void bx1_volume_begin(const char *title, const char *master_title,
	const char *link_label, const char *reset_label)
{
	NSString *master_labels[1];
	NSRect frame = NSMakeRect(0.0, 0.0, 100.0, 100.0);

	if (target == nil) {
		target = [[BX1VolumeTarget alloc] init];
	}
	if (sliders_by_tag == nil) {
		sliders_by_tag = [[NSMutableDictionary alloc] init];
	}
	if (boxes == nil) {
		boxes = [[NSMutableArray alloc] init];
	}

	// Not resizable: nothing here reads better wider, and every row is
	// already as tall as it needs to be.
	panel = [[NSWindow alloc] initWithContentRect:frame
		styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
		backing:NSBackingStoreBuffered
		defer:YES];
	[panel setTitle:bx1_ns_string(title)];
	// A window created here is released when closed by default, which for a
	// panel that is shown and hidden repeatedly means the second open would
	// message a freed object. Closing must only order it out.
	[panel setReleasedWhenClosed:NO];

	// Above the devices, since it acts on all of them. The master is this
	// port's own: the core has no master level - volume exists per device
	// only - so it is mixed in on the Nim side.
	master_labels[0] = @"L+R";
	master_box = make_group(bx1_ns_string(master_title), -1, 1, master_labels);

	link_button = [[NSButton alloc] initWithFrame:NSZeroRect];
	[link_button setButtonType:NSButtonTypeSwitch];
	[link_button setTitle:bx1_ns_string(link_label)];
	[link_button setTarget:target];
	[link_button setAction:@selector(linkToggled:)];
	[link_button sizeToFit];

	reset_button = [[NSButton alloc] initWithFrame:
		NSMakeRect(0.0, 0.0, kButtonWidth, kBarHeight)];
	[reset_button setBezelStyle:NSBezelStyleRounded];
	[reset_button setTitle:bx1_ns_string(reset_label)];
	[reset_button setTarget:target];
	[reset_button setAction:@selector(resetClicked:)];
}

void bx1_volume_add_device(int device, const char *caption)
{
	NSString *labels[2];
	NSBox *box;

	if (panel == nil) {
		return;
	}
	labels[0] = @"L";
	labels[1] = @"R";
	box = make_group(bx1_ns_string(caption), device, 2, labels);
	[boxes addObject:box];
	[box release];
}

void bx1_volume_end(void)
{
	CGFloat boxWidth;
	CGFloat contentWidth;
	CGFloat y = kMargin;
	NSView *content;
	NSInteger i;

	if (panel == nil || master_box == nil) {
		return;
	}
	// Every box was built around the same inner width, so they all fit the
	// same frame; the window is then sized to whatever that came to.
	boxWidth = [master_box frame].size.width;
	contentWidth = boxWidth + kMargin * 2;

	content = [panel contentView];

	// Laid out from the bottom up, which is the direction AppKit's
	// coordinates already run in: the button bar sits on the bottom margin,
	// the device groups stack above it in order, and the master goes on top.
	[link_button setFrameOrigin:NSMakePoint(kMargin,
		y + (kBarHeight - [link_button frame].size.height) / 2.0)];
	[reset_button setFrameOrigin:NSMakePoint(
		contentWidth - kMargin - kButtonWidth, y)];
	[content addSubview:link_button];
	[content addSubview:reset_button];
	y += kBarHeight + kGroupGap;

	for (i = (NSInteger)[boxes count] - 1; i >= 0; i--) {
		NSBox *box = [boxes objectAtIndex:i];

		[box setFrameOrigin:NSMakePoint(kMargin, y)];
		[content addSubview:box];
		y += [box frame].size.height + kGroupGap;
	}

	[master_box setFrameOrigin:NSMakePoint(kMargin, y)];
	[content addSubview:master_box];
	y += [master_box frame].size.height + kMargin;

	[panel setContentSize:NSMakeSize(contentWidth, y)];
}

void bx1_volume_set_level(int device, int channel, int value)
{
	NSSlider *slider = slider_for(device, channel);

	if (slider == nil) {
		return;
	}
	[slider setDoubleValue:value];
	// Through snap() rather than setting the tooltip here, so a level
	// arriving from the Nim side is displayed by exactly the same rule as
	// one the user dragged.
	(void)snap(slider);
}

int bx1_volume_get_level(int device, int channel)
{
	NSSlider *slider = slider_for(device, channel);

	return slider == nil ? 0 : (int)lround([slider doubleValue]);
}

/*
	Greys the rows whose board this machine does not have.

	The row stays rather than vanishing: the original lists every channel of
	the table unconditionally, and a row that disappears looks like the app
	lost the device. Greyed says what the original's own (commented out)
	EnableWindow calls were reaching for - the channel exists, this machine
	just has no board behind it. The sliders are disabled rather than the box
	around them, which has no visible disabled state.
*/
void bx1_volume_set_device_enabled(int device, int enabled)
{
	[slider_for(device, 0) setEnabled:(enabled != 0)];
	[slider_for(device, 1) setEnabled:(enabled != 0)];
}

void bx1_volume_set_linked(int linked)
{
	[link_button setState:
		(linked ? NSControlStateValueOn : NSControlStateValueOff)];
}

/*
	Shows the panel, centering it over the emulator window the first time
	only - moving it back on every open would undo wherever the user had put
	it. The emulator window is the app's main window; if the app is not
	active there is nothing to center on and the screen is used instead.
*/
void bx1_volume_show(void)
{
	if (panel == nil) {
		return;
	}
	if (!placed) {
		NSWindow *over = [NSApp mainWindow];

		if (over != nil && over != panel) {
			NSRect ref = [over frame];
			NSRect own = [panel frame];

			[panel setFrameOrigin:NSMakePoint(
				NSMidX(ref) - own.size.width / 2.0,
				NSMidY(ref) - own.size.height / 2.0)];
			// Only now, so a first open that found no main window (the app
			// was not active) still gets centered properly next time rather
			// than being stuck wherever the screen-centered fallback put it.
			placed = YES;
		} else {
			[panel center];
		}
	}
	[panel makeKeyAndOrderFront:nil];
}

void bx1_volume_hide(void)
{
	[panel orderOut:nil];
}
