/*
	Skelton for retropc emulator

	Author : Takeda.Toshiya
	Date   : 2015.11.20-

	[ sdl dependent ]

	BubiX1turboZ: host independent OSD declarations.

	This header intentionally does NOT include SDL headers. The OSD layer only
	owns plain buffers (screen, sound, input state); SDL is used exclusively by
	the Nim application layer. Keeping the C++ side host independent makes the
	C++/Nim boundary a pure data boundary.
*/

#ifndef _SDL_OSD_H_
#define _SDL_OSD_H_

#include <pthread.h>
#include "../vm/vm.h"
#include "../common.h"
#include "../config.h"

class FIFO;
class FILEIO;

#define OSD_CONSOLE_BLUE	1 // text color contains blue
#define OSD_CONSOLE_GREEN	2 // text color contains green
#define OSD_CONSOLE_RED		4 // text color contains red
#define OSD_CONSOLE_INTENSITY	8 // text color is intensified

#define SCREEN_FILTER_NONE	0
#define SCREEN_FILTER_RGB	1
#define SCREEN_FILTER_RF	2

/// Off-screen ARGB8888 surface owned by the OSD layer.
typedef struct bitmap_s {
	inline bool initialized()
	{
		return (lpBmp != NULL);
	}
	inline scrntype_t* get_buffer(int y)
	{
		// top-down layout, unlike the win32 DIB which is bottom-up
		return lpBmp + width * y;
	}
	int width, height;
	scrntype_t* lpBmp;
} bitmap_t;

/// Font descriptor. Text rendering is a no-op in this port for now.
typedef struct font_s {
	inline bool initialized()
	{
		return (height != 0);
	}
	_TCHAR family[64];
	int width, height, rotate;
	bool bold, italic;
} font_t;

/// Pen descriptor used by the printer bitmap API.
typedef struct pen_s {
	inline bool initialized()
	{
		return (width != 0);
	}
	int width;
	uint8_t r, g, b;
} pen_t;

class OSD
{
private:
	int lock_count;
	pthread_mutex_t vm_mutex;

	// input
	uint8_t key_status[256];
	bool lost_focus;

#ifdef USE_JOYSTICK
	uint32_t joy_status[4];
#endif
#ifdef USE_MOUSE
	int32_t mouse_status[3];
	bool mouse_enabled;
#endif

	// screen
	bitmap_t vm_screen_buffer;

	int host_window_width, host_window_height;
	bool host_window_mode;
	int vm_screen_width, vm_screen_height;
	int vm_window_width, vm_window_height;
	int vm_window_width_aspect, vm_window_height_aspect;

	// sound
	int sound_rate, sound_samples;
	bool sound_available, sound_muted;

	// Sound ring buffer. update_sound() (driven once per bx1_run_frame call
	// from the Nim layer) appends here; the bridge drains it via pull_sound().
	// Guarded by its own mutex, distinct from vm_mutex, since the Nim audio
	// callback and the emulation thread touch it independently.
	pthread_mutex_t sound_mutex;
	int16_t* sound_ring_buffer;
	int sound_ring_capacity; // in stereo frames
	int sound_ring_head;     // next frame to read
	int sound_ring_count;    // frames currently buffered

	// Internal helpers (not part of the original win32 OSD API).
	void allocate_screen_buffer(bitmap_t *buffer, int width, int height);
	void release_screen_buffer(bitmap_t *buffer);
	void key_change(int code, bool pressed, bool repeat);

public:
	OSD()
	{
		lock_count = 0;
	}
	~OSD() {}

	// common
	VM_TEMPLATE* vm;

	void initialize(int rate, int samples);
	void release();
	void power_off();
	void suspend();
	void restore();
	void lock_vm();
	void unlock_vm();
	bool is_vm_locked()
	{
		return (lock_count != 0);
	}
	void force_unlock_vm();
	void sleep(uint32_t ms);

	// common debugger
#ifdef USE_DEBUGGER
	void start_waiting_in_debugger();
	void finish_waiting_in_debugger();
	void process_waiting_in_debugger();
#endif

	// common console (stubs; the debugger console is not exposed)
	void open_console(int width, int height, const _TCHAR* title);
	void close_console();
	unsigned int get_console_code_page();
	void set_console_text_attribute(unsigned short attr);
	void write_console(const _TCHAR* buffer, unsigned int length);
	int read_console_input(_TCHAR* buffer, unsigned int length);
	bool is_console_key_pressed(int vk);
	bool is_console_closed();
	void close_debugger_console();

	// common input
	void update_input();
	void key_down(int code, bool extended, bool repeat);
	void key_up(int code, bool extended);
	void key_down_native(int code, bool repeat);
	void key_up_native(int code);
	void key_lost_focus()
	{
		lost_focus = true;
	}
	// Test hook: a log of the key events actually handed to the VM, which
	// is what the headless tests under tests/ assert on - see
	// key_change() in osd_input.cpp for the recorded form. Static because
	// there is one machine, and the bridge reaches this without holding an
	// OSD instance (EMU keeps its own privately).
	//
	// Each entry is the VK code, with this bit set on a release.
	static const uint16_t KEY_CAPTURE_RELEASE = 0x100;
	static void start_key_capture();
	static int read_key_capture(uint16_t* dst, int max_entries, int* dropped);
#ifdef USE_MOUSE
	void enable_mouse();
	void disable_mouse();
	void toggle_mouse();
	bool is_mouse_enabled()
	{
		return mouse_enabled;
	}
#endif
	uint8_t* get_key_buffer()
	{
		return key_status;
	}
#ifdef USE_JOYSTICK
	uint32_t* get_joy_buffer()
	{
		return joy_status;
	}
#endif
#ifdef USE_MOUSE
	int32_t* get_mouse_buffer()
	{
		return mouse_status;
	}
#endif
#ifdef USE_AUTO_KEY
	bool now_auto_key;
#endif

	// common screen
	double get_window_mode_power(int mode);
	int get_window_mode_width(int mode);
	int get_window_mode_height(int mode);
	void set_host_window_size(int window_width, int window_height, bool window_mode);
	void set_vm_screen_size(int screen_width, int screen_height, int window_width, int window_height, int window_width_aspect, int window_height_aspect);
	void set_vm_screen_lines(int lines);
	int get_vm_window_width()
	{
		return vm_window_width;
	}
	int get_vm_window_height()
	{
		return vm_window_height;
	}
	int get_vm_window_width_aspect()
	{
		return vm_window_width_aspect;
	}
	int get_vm_window_height_aspect()
	{
		return vm_window_height_aspect;
	}
	// Stride (in pixels) and row count of the buffer get_vm_screen_buffer()
	// points into. Not part of the original win32 OSD API; added for the
	// C ABI bridge, which needs the buffer's own dimensions rather than the
	// host window size.
	int get_vm_screen_width()
	{
		return vm_screen_width;
	}
	int get_vm_screen_height()
	{
		return vm_screen_height;
	}
	scrntype_t* get_vm_screen_buffer(int y);
	int draw_screen();
	void capture_screen();
	bool start_record_video(int fps);
	void stop_record_video();
	void restart_record_video();
	void add_extra_frames(int extra_frames);
	bool now_record_video;
#ifdef USE_SCREEN_FILTER
	bool screen_skip_line;
#endif

	// common sound
	void update_sound(int* extra_frames);
	void mute_sound();
	void stop_sound();
	void start_record_sound();
	void stop_record_sound();
	void restart_record_sound();
	bool now_record_sound;

	// Not part of the original win32 OSD API; added for the C ABI bridge.
	int get_sound_rate()
	{
		return sound_rate;
	}
	// Drains up to `frames` stereo frames into dst (interleaved int16 L/R).
	// Returns the number of frames actually copied (may be less than
	// requested if the ring buffer has less data available).
	int pull_sound(int16_t* dst, int frames);
	// Frames currently sitting in the ring buffer. The host uses this as
	// the audio-clock pacing signal (see docs/dev/DevelopmentPlan.md,
	// "frame sync is audio-clock driven"): keep calling bx1_run_frame
	// while this stays below the desired latency.
	int get_buffered_sound_frames();

	// common printer
#ifdef USE_PRINTER
	void create_bitmap(bitmap_t *bitmap, int width, int height);
	void release_bitmap(bitmap_t *bitmap);
	void create_font(font_t *font, const _TCHAR *family, int width, int height, int rotate, bool bold, bool italic);
	void release_font(font_t *font);
	void create_pen(pen_t *pen, int width, uint8_t r, uint8_t g, uint8_t b);
	void release_pen(pen_t *pen);
	void clear_bitmap(bitmap_t *bitmap, uint8_t r, uint8_t g, uint8_t b);
	int get_text_width(bitmap_t *bitmap, font_t *font, const char *text);
	void draw_text_to_bitmap(bitmap_t *bitmap, font_t *font, int x, int y, const char *text, uint8_t r, uint8_t g, uint8_t b);
	void draw_line_to_bitmap(bitmap_t *bitmap, pen_t *pen, int sx, int sy, int ex, int ey);
	void draw_rectangle_to_bitmap(bitmap_t *bitmap, int x, int y, int width, int height, uint8_t r, uint8_t g, uint8_t b);
	void draw_point_to_bitmap(bitmap_t *bitmap, int x, int y, uint8_t r, uint8_t g, uint8_t b);
	void stretch_bitmap(bitmap_t *dest, int dest_x, int dest_y, int dest_width, int dest_height, bitmap_t *source, int source_x, int source_y, int source_width, int source_height);
#endif
	void write_bitmap_to_file(bitmap_t *bitmap, const _TCHAR *file_path);

	// common midi
#ifdef USE_MIDI
	void send_to_midi(uint8_t data);
	bool recv_from_midi(uint8_t *data);
#endif
};

#endif
