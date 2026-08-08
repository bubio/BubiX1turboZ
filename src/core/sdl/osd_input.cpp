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

	if(pressed) {
		vm->key_down(code, repeat);
	} else {
		vm->key_up(code);
	}

	if(generic != 0) {
		uint8_t merged_after = key_status[left] | key_status[right];
		if(merged_before == 0 && merged_after != 0) {
			key_status[generic] = 0x80;
			vm->key_down(generic, false);
		} else if(merged_before != 0 && merged_after == 0) {
			key_status[generic] = 0;
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
