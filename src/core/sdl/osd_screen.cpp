/*
	Skelton for retropc emulator

	Author : Takeda.Toshiya
	Date   : 2015.11.20-

	[ sdl dependent ]

	BubiX1turboZ: screen buffer handling.

	This OSD does not render anything itself. draw_screen() only lets the VM
	fill vm_screen_buffer (ARGB8888, top-down); the Nim layer reads it back
	via get_vm_screen_buffer(0) and uploads it to an SDL texture.
*/

#include "osd.h"

void OSD::allocate_screen_buffer(bitmap_t *buffer, int width, int height)
{
	release_screen_buffer(buffer);
	buffer->width = width;
	buffer->height = height;
	buffer->lpBmp = (scrntype_t*)calloc((size_t)width * height, sizeof(scrntype_t));
}

void OSD::release_screen_buffer(bitmap_t *buffer)
{
	if(buffer->lpBmp != NULL) {
		free(buffer->lpBmp);
		buffer->lpBmp = NULL;
	}
	buffer->width = buffer->height = 0;
}

double OSD::get_window_mode_power(int mode)
{
	// This port does not offer a host window-scale menu (BluePrint's
	// "necessary features only" policy); a single 1x mode is all that is
	// exposed, so mode is ignored.
	return 1.0;
}

int OSD::get_window_mode_width(int mode)
{
	return vm_window_width;
}

int OSD::get_window_mode_height(int mode)
{
	return vm_window_height;
}

void OSD::set_host_window_size(int window_width, int window_height, bool window_mode)
{
	if(window_width != -1) {
		host_window_width = window_width;
	}
	if(window_height != -1) {
		host_window_height = window_height;
	}
	host_window_mode = window_mode;
}

void OSD::set_vm_screen_size(int screen_width, int screen_height, int window_width, int window_height, int window_width_aspect, int window_height_aspect)
{
	if(window_width == -1) {
		window_width = screen_width;
	}
	if(window_height == -1) {
		window_height = screen_height;
	}
	if(window_width_aspect == -1) {
		window_width_aspect = window_width;
	}
	if(window_height_aspect == -1) {
		window_height_aspect = window_height;
	}
	vm_window_width = window_width;
	vm_window_height = window_height;
	vm_window_width_aspect = window_width_aspect;
	vm_window_height_aspect = window_height_aspect;

	if(vm_screen_buffer.width != screen_width || vm_screen_buffer.height != screen_height) {
		vm_screen_width = screen_width;
		vm_screen_height = screen_height;
		allocate_screen_buffer(&vm_screen_buffer, screen_width, screen_height);
	}
}

void OSD::set_vm_screen_lines(int lines)
{
	// win32's implementation is a no-op too (see the commented-out call in
	// the original osd_screen.cpp); X1turboZ never actually changes its
	// scanline count at runtime.
}

scrntype_t* OSD::get_vm_screen_buffer(int y)
{
	return vm_screen_buffer.get_buffer(y);
}

int OSD::draw_screen()
{
	if(vm_screen_buffer.width != vm_screen_width || vm_screen_buffer.height != vm_screen_height) {
		allocate_screen_buffer(&vm_screen_buffer, vm_screen_width, vm_screen_height);
	}
#ifdef USE_SCREEN_FILTER
	screen_skip_line = false;
#endif
	vm->draw_screen();
	return 0;
}

void OSD::capture_screen()
{
	// Screenshot capture is a host UI feature; not implemented on the core
	// side (phase 0.6 group B).
}

bool OSD::start_record_video(int fps)
{
	return false;
}

void OSD::stop_record_video()
{
	now_record_video = false;
}

void OSD::restart_record_video()
{
}

void OSD::add_extra_frames(int extra_frames)
{
}
