/*
	Skelton for retropc emulator

	Author : Takeda.Toshiya
	Date   : 2015.11.20-

	[ sdl dependent ]

	BubiX1turboZ: lifecycle and VM-lock implementation.

	Unlike the win32 OSD, lock_vm()/unlock_vm() guard a real mutex here: the
	emulation runs on its own thread while the host (Nim) GUI thread reads
	the screen buffer and injects input concurrently (see the phase 1
	architecture notes in docs/dev/DevelopmentPlan.md).
*/

#include "osd.h"

void OSD::initialize(int rate, int samples)
{
	// Recursive: EMU::run() itself calls lock_vm()/unlock_vm() around
	// vm->run() (emu.cpp), so a caller that holds the lock across a call
	// into the core (e.g. bx1_lock() around bx1_run_frame()) would
	// self-deadlock on a default (non-recursive) mutex.
	pthread_mutexattr_t attr;
	pthread_mutexattr_init(&attr);
	pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
	pthread_mutex_init(&vm_mutex, &attr);
	pthread_mutexattr_destroy(&attr);
	lock_count = 0;

	// input
	memset(key_status, 0, sizeof(key_status));
	lost_focus = false;
#ifdef USE_JOYSTICK
	memset(joy_status, 0, sizeof(joy_status));
#endif
#ifdef USE_MOUSE
	memset(mouse_status, 0, sizeof(mouse_status));
	mouse_enabled = false;
#endif
#ifdef USE_AUTO_KEY
	now_auto_key = false;
#endif

	// screen: sized from the machine's default SCREEN_WIDTH/HEIGHT (x1.h),
	// matching what win32's initialize_screen() does for the initial buffer.
	host_window_width = WINDOW_WIDTH;
	host_window_height = WINDOW_HEIGHT;
	host_window_mode = true;
	vm_screen_width = SCREEN_WIDTH;
	vm_screen_height = SCREEN_HEIGHT;
	vm_window_width = WINDOW_WIDTH;
	vm_window_height = WINDOW_HEIGHT;
	vm_window_width_aspect = WINDOW_WIDTH_ASPECT;
	vm_window_height_aspect = WINDOW_HEIGHT_ASPECT;
	memset(&vm_screen_buffer, 0, sizeof(bitmap_t));
	allocate_screen_buffer(&vm_screen_buffer, vm_screen_width, vm_screen_height);
#ifdef USE_SCREEN_FILTER
	screen_skip_line = false;
#endif
	now_record_video = false;

	// sound
	sound_rate = rate;
	sound_samples = samples;
	sound_available = true;
	sound_muted = false;
	now_record_sound = false;
	pthread_mutex_init(&sound_mutex, NULL);
	sound_ring_capacity = samples * 8; // a few frames' worth of headroom
	sound_ring_buffer = (int16_t*)calloc(sound_ring_capacity * 2, sizeof(int16_t)); // stereo
	sound_ring_head = sound_ring_count = 0;
}

void OSD::release()
{
	release_screen_buffer(&vm_screen_buffer);

	pthread_mutex_lock(&sound_mutex);
	free(sound_ring_buffer);
	sound_ring_buffer = NULL;
	sound_ring_capacity = sound_ring_head = sound_ring_count = 0;
	pthread_mutex_unlock(&sound_mutex);
	pthread_mutex_destroy(&sound_mutex);

	pthread_mutex_destroy(&vm_mutex);
}

void OSD::power_off()
{
	// The host (Nim) owns process lifetime; nothing to do here.
}

void OSD::suspend()
{
	mute_sound();
}

void OSD::restore()
{
	sound_muted = false;
}

void OSD::lock_vm()
{
	pthread_mutex_lock(&vm_mutex);
	lock_count++;
}

void OSD::unlock_vm()
{
	if(--lock_count <= 0) {
		lock_count = 0;
	}
	pthread_mutex_unlock(&vm_mutex);
}

void OSD::force_unlock_vm()
{
	// Drop every level of recursion this thread may still hold after an
	// error. lock_count is only ever incremented/decremented under
	// vm_mutex by lock_vm/unlock_vm, so this is best-effort recovery,
	// matching win32's semantics.
	while(lock_count > 0) {
		lock_count--;
		pthread_mutex_unlock(&vm_mutex);
	}
}

void OSD::sleep(uint32_t ms)
{
	struct timespec ts;
	ts.tv_sec = ms / 1000;
	ts.tv_nsec = (long)(ms % 1000) * 1000000L;
	nanosleep(&ts, NULL);
}

#ifdef USE_DEBUGGER
// The debugger console is not exposed on this port (0.5.1 in
// DevelopmentPlan.md: USE_DEBUGGER stays defined, but its console I/O is
// stubbed out). debugger.cpp's "go" command wait loop has no OSD_SDL arm at
// all (see docs/dev/VendorPatches.md), so these are never actually called
// today; they exist to satisfy the link.
void OSD::start_waiting_in_debugger()
{
}

void OSD::finish_waiting_in_debugger()
{
}

void OSD::process_waiting_in_debugger()
{
}
#endif
