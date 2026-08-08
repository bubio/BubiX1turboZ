/*
	BubiX1turboZ - C ABI bridge implementation.

	See bubix1_api.h for the exported surface and its rationale. Each
	function here is a thin pass-through to one EMU/OSD call; no policy
	(which drives to show, which config knobs to expose) lives on this
	side of the boundary - that belongs to the Nim UI layer.
*/

#include "bubix1_api.h"

#include "../core/emu.h"
#include "../core/config.h"
#include "../core/common.h"

namespace {
inline EMU* emu_of(bx1_handle h)
{
	return static_cast<EMU*>(h);
}
}

bx1_handle bx1_create(const char* base_dir)
{
	set_application_path(base_dir);
	initialize_config();
	return new EMU();
}

void bx1_destroy(bx1_handle h)
{
	delete emu_of(h);
}

void bx1_reset(bx1_handle h)
{
	emu_of(h)->reset();
}

void bx1_special_reset(bx1_handle h)
{
	emu_of(h)->special_reset();
}

int bx1_run_frame(bx1_handle h)
{
	return emu_of(h)->run();
}

void bx1_draw_screen(bx1_handle h)
{
	emu_of(h)->draw_screen();
}

void bx1_lock(bx1_handle h)
{
	emu_of(h)->lock_vm();
}

void bx1_unlock(bx1_handle h)
{
	emu_of(h)->unlock_vm();
}

const uint32_t* bx1_get_framebuffer(bx1_handle h)
{
	return (const uint32_t*)emu_of(h)->get_screen_buffer(0);
}

int bx1_get_screen_width(bx1_handle h)
{
	return emu_of(h)->get_vm_window_width();
}

int bx1_get_screen_height(bx1_handle h)
{
	return emu_of(h)->get_vm_window_height();
}

int bx1_get_aspect_height(bx1_handle h)
{
	return emu_of(h)->get_vm_window_height_aspect();
}

int bx1_get_actual_sound_rate(bx1_handle h)
{
	return emu_of(h)->get_sound_rate();
}

int bx1_pull_audio(bx1_handle h, int16_t* dst, int frames)
{
	return emu_of(h)->get_osd()->pull_sound(dst, frames);
}

void bx1_mute_sound(bx1_handle h)
{
	emu_of(h)->mute_sound();
}

void bx1_key_down(bx1_handle h, int vk_code, int repeat)
{
	emu_of(h)->key_down(vk_code, false, repeat != 0);
}

void bx1_key_up(bx1_handle h, int vk_code)
{
	emu_of(h)->key_up(vk_code, false);
}

void bx1_set_joy(bx1_handle h, int index, uint32_t status)
{
	if(index < 0 || index >= 4) {
		return;
	}
	emu_of(h)->get_osd()->get_joy_buffer()[index] = status;
}

void bx1_set_mouse(bx1_handle h, int dx, int dy, int buttons)
{
	int32_t* mouse = emu_of(h)->get_osd()->get_mouse_buffer();
	mouse[0] = dx;
	mouse[1] = dy;
	mouse[2] = buttons;
}

int bx1_open_floppy(bx1_handle h, int drv, const char* path, int bank)
{
	EMU* emu = emu_of(h);
	emu->open_floppy_disk(drv, path, bank);
	return emu->is_floppy_disk_inserted(drv) ? 1 : 0;
}

void bx1_close_floppy(bx1_handle h, int drv)
{
	emu_of(h)->close_floppy_disk(drv);
}

int bx1_get_floppy_bank_count(bx1_handle h, int drv)
{
	if(drv < 0 || drv >= USE_FLOPPY_DISK) {
		return 0;
	}
	return emu_of(h)->d88_file[drv].bank_num;
}

const char* bx1_get_floppy_bank_name(bx1_handle h, int drv, int bank)
{
	if(drv < 0 || drv >= USE_FLOPPY_DISK || bank < 0 || bank >= MAX_D88_BANKS) {
		return "";
	}
	return emu_of(h)->d88_file[drv].disk_name[bank];
}

int bx1_open_tape(bx1_handle h, const char* path, int play)
{
	EMU* emu = emu_of(h);
	if(play) {
		emu->play_tape(0, path);
	} else {
		emu->rec_tape(0, path);
	}
	return emu->is_tape_inserted(0) ? 1 : 0;
}

void bx1_close_tape(bx1_handle h)
{
	emu_of(h)->close_tape(0);
}

int bx1_save_state(bx1_handle h, const char* path)
{
	emu_of(h)->save_state(path);
	return 1;
}

int bx1_load_state(bx1_handle h, const char* path)
{
	emu_of(h)->load_state(path);
	return 1;
}

void bx1_set_monitor_type(bx1_handle h, int type)
{
	config.monitor_type = type;
	emu_of(h)->update_config();
}

void bx1_set_sound_type(bx1_handle h, int type)
{
	config.sound_type = type;
	emu_of(h)->update_config();
}

void bx1_set_volume(bx1_handle h, int device, int decibel_l, int decibel_r)
{
	emu_of(h)->set_sound_device_volume(device, decibel_l, decibel_r);
}
