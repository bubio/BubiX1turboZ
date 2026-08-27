/*
	Skelton for retropc emulator

	Author : Takeda.Toshiya
	Date   : 2015.11.26-

	[ sdl dependent ]

	BubiX1turboZ: input state.

	key_status / joy_status / mouse_status are injected from the host (Nim,
	via the C ABI bridge in src/bridge/) rather than polled here — see
	get_key_buffer() / get_joy_buffer() / get_mouse_buffer() in osd.h.

	Unlike win32, whose key_down()/key_up() disambiguate a single "shift"
	message into left/right shift by polling GetAsyncKeyState(), the host
	here always passes distinct VK_LSHIFT/VK_RSHIFT (etc.) codes directly
	(SDL gives distinct scancodes for left/right modifiers - see phase 5's
	keycode table). So key_down()/key_up() only need to merge those into the
	generic VK_SHIFT/VK_CONTROL/VK_MENU events the X1 keyboard device
	expects (vm/x1/keyboard.cpp indexes key_buf[] by the generic code).
*/

#include "osd.h"

// Test hook. Recording stays off until a test turns it on, so an ordinary
// run pays one always-false branch per key event and nothing else. The
// state is file scope rather than per-OSD for the reason given in osd.h:
// there is one machine, and the bridge reaches this without an instance.
namespace {
const int KEY_CAPTURE_MAX = 256;
uint16_t key_capture_log[KEY_CAPTURE_MAX];
int key_capture_count = 0;
int key_capture_dropped = 0;
bool key_capture_on = false;

// Appends one event in the form the tests read: the VK code, with
// OSD::KEY_CAPTURE_RELEASE set on a release. Overflow is counted, never
// wrapped - a test that overruns the log has to fail rather than compare
// a silently truncated prefix.
inline void capture_key(int code, bool pressed)
{
	if(!key_capture_on) {
		return;
	}
	if(key_capture_count >= KEY_CAPTURE_MAX) {
		if(key_capture_dropped < 0x7fffffff) {
			key_capture_dropped++;
		}
		return;
	}
	key_capture_log[key_capture_count++] =
		(uint16_t)(code | (pressed ? 0 : OSD::KEY_CAPTURE_RELEASE));
}
}

void OSD::start_key_capture()
{
	key_capture_count = key_capture_dropped = 0;
	key_capture_on = true;
}

// Drains the log into dst and empties it, so two consecutive calls see
// only what happened between them. Returns how many entries were written;
// *dropped, when not NULL, is how many events since the last call did not
// fit - in the log, or in dst.
int OSD::read_key_capture(uint16_t* dst, int max_entries, int* dropped)
{
	int written = key_capture_count < max_entries ? key_capture_count : max_entries;
	for(int i = 0; i < written; i++) {
		dst[i] = key_capture_log[i];
	}
	if(dropped != NULL) {
		*dropped = key_capture_dropped + (key_capture_count - written);
	}
	key_capture_count = key_capture_dropped = 0;
	return written;
}

void OSD::update_input()
{
	// Input state is injected by the host; nothing to poll here.
}

// Applies one press/release to key_status[code], merges left/right
// modifier keys into their generic VK_SHIFT/VK_CONTROL/VK_MENU counterpart,
// and forwards the resulting edge(s) to the VM.
void OSD::key_change(int code, bool pressed, bool repeat)
{
	if(code < 0 || code >= 256) {
		return;
	}
	if(pressed && key_status[code] != 0) {
		// already down: only a repeat, still forward it
		capture_key(code, true);
		vm->key_down(code, repeat);
		return;
	}
	if(!pressed && key_status[code] == 0) {
		return;
	}

	int generic = 0, left = 0, right = 0;
	if(code == VK_LSHIFT || code == VK_RSHIFT) {
		generic = VK_SHIFT; left = VK_LSHIFT; right = VK_RSHIFT;
	} else if(code == VK_LCONTROL || code == VK_RCONTROL) {
		generic = VK_CONTROL; left = VK_LCONTROL; right = VK_RCONTROL;
	} else if(code == VK_LMENU || code == VK_RMENU) {
		generic = VK_MENU; left = VK_LMENU; right = VK_RMENU;
	}
	uint8_t merged_before = generic != 0 ? (uint8_t)(key_status[left] | key_status[right]) : 0;

	key_status[code] = pressed ? 0x80 : 0;

	capture_key(code, pressed);
	if(pressed) {
		vm->key_down(code, repeat);
	} else {
		vm->key_up(code);
	}

	if(generic != 0) {
		uint8_t merged_after = key_status[left] | key_status[right];
		if(merged_before == 0 && merged_after != 0) {
			key_status[generic] = 0x80;
			capture_key(generic, true);
			vm->key_down(generic, false);
		} else if(merged_before != 0 && merged_after == 0) {
			key_status[generic] = 0;
			capture_key(generic, false);
			vm->key_up(generic);
		}
	}
}

void OSD::key_down(int code, bool extended, bool repeat)
{
	key_change(code, true, repeat);
}

void OSD::key_up(int code, bool extended)
{
	key_change(code, false, false);
}

void OSD::key_down_native(int code, bool repeat)
{
	key_change(code, true, repeat);
}

void OSD::key_up_native(int code)
{
	key_change(code, false, false);
}

#ifdef USE_MOUSE
void OSD::enable_mouse()
{
	mouse_enabled = true;
}

void OSD::disable_mouse()
{
	mouse_enabled = false;
	memset(mouse_status, 0, sizeof(mouse_status));
}

void OSD::toggle_mouse()
{
	if(mouse_enabled) {
		disable_mouse();
	} else {
		enable_mouse();
	}
}
#endif
