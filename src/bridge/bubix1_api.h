/*
	BubiX1turboZ - C ABI bridge between the vendored eX1turboZ core and the
	Nim application layer.

	This header is intentionally plain C: it is parsed by Nim's `importc` /
	`header` mechanism, not compiled as part of the C++ core. Every exported
	function is a thin, unopinionated wrapper around one EMU/OSD call - see
	src/bridge/bubix1_api.cpp for the mapping and docs/dev/DevelopmentPlan.md
	phase 4 for the design rationale.

	The opaque handle returned by bx1_create() wraps one EMU instance (which
	owns one OSD and one VM). Feature reduction (BluePrint: "no FDD 3/4, no
	HDD menu") happens in the Nim UI layer, not here - the bridge exposes
	everything the core actually has, same as the OSD layer below it.
*/

#ifndef BUBIX1_API_H
#define BUBIX1_API_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void* bx1_handle;

// ----------------------------------------------------------------------
// Lifecycle
// ----------------------------------------------------------------------

/// Creates one emulator instance. `base_dir` is the single directory the
/// core resolves ROM and on-disk state paths against (create_local_path);
/// the host is responsible for placing/symlinking ROMs there before
/// calling this (see docs/dev/VendorPatches.md, "get_application_path").
/// `config_path`: an INI file previously written by bx1_save_config(), or
/// NULL/empty to start from built-in defaults. Config must be loaded
/// before the VM is constructed (EMU's constructor reads config.sound_*
/// synchronously), so this happens inside bx1_create rather than as a
/// separate call.
bx1_handle bx1_create(const char* base_dir, const char* config_path);
void bx1_destroy(bx1_handle h);
/// Writes the current configuration (monitor/sound type, scanline, sound
/// volume, ...) to an INI file at `config_path`, creating it if needed.
void bx1_save_config(bx1_handle h, const char* config_path);
void bx1_reset(bx1_handle h);
/// NEW ON / IPL reset (USE_SPECIAL_RESET).
void bx1_special_reset(bx1_handle h);

// ----------------------------------------------------------------------
// Execution
// ----------------------------------------------------------------------

/// Advances the VM by one host tick. May internally run more than one VM
/// frame (returned count) when the OSD's sound-driven pacing needs it.
int bx1_run_frame(bx1_handle h);
/// Lets the VM render into its screen buffer; call once per host frame
/// before bx1_get_framebuffer(), independent of how many bx1_run_frame
/// calls preceded it (frame skipping).
void bx1_draw_screen(bx1_handle h);
void bx1_lock(bx1_handle h);
void bx1_unlock(bx1_handle h);

// ----------------------------------------------------------------------
// Screen
// ----------------------------------------------------------------------

/// ARGB8888, top-down, row stride == bx1_get_screen_width(). Alpha is
/// always 0 - use SDL_BLENDMODE_NONE (see docs/dev/DevelopmentPlan.md 1.4).
const uint32_t* bx1_get_framebuffer(bx1_handle h);
int bx1_get_screen_width(bx1_handle h);
int bx1_get_screen_height(bx1_handle h);
/// Aspect-corrected display height (WINDOW_HEIGHT_ASPECT = 480 for X1turboZ).
int bx1_get_aspect_height(bx1_handle h);

// ----------------------------------------------------------------------
// Sound
// ----------------------------------------------------------------------

/// The actual PCM sample rate the core is generating at - NOT necessarily
/// a "nice" number. For X1turboZ the 48000Hz table slot is overridden to
/// 62500Hz; open the host audio device at this rate, not a requested one.
int bx1_get_actual_sound_rate(bx1_handle h);
/// Drains up to `frames` interleaved int16 stereo frames into dst. Returns
/// the number of frames actually copied (may be less than requested).
int bx1_pull_audio(bx1_handle h, int16_t* dst, int frames);
/// Frames currently sitting in the ring buffer, not yet pulled. This is
/// the audio-clock pacing signal: keep calling bx1_run_frame while this
/// stays below the host's desired latency (docs/dev/DevelopmentPlan.md,
/// "frame sync is audio-clock driven").
int bx1_get_buffered_audio_frames(bx1_handle h);
void bx1_mute_sound(bx1_handle h);

// ----------------------------------------------------------------------
// Input
// ----------------------------------------------------------------------

/// vk_code values must match src/core/compat/vkcodes.h (Microsoft SDK
/// numbering - see docs/dev/VendorPatches.md). Pass distinct
/// VK_LSHIFT/VK_RSHIFT (etc.) codes; the OSD merges them into the generic
/// VK_SHIFT event the VM expects.
void bx1_key_down(bx1_handle h, int vk_code, int repeat);
void bx1_key_up(bx1_handle h, int vk_code);
/// index: 0-3. status: bit N set means button N held (raw physical state;
/// the core remaps this through config.joy_buttons before the VM sees it).
void bx1_set_joy(bx1_handle h, int index, uint32_t status);
/// dx/dy are deltas since the last call; buttons is a bitmask (bit0=left,
/// bit1=right, bit2=middle).
void bx1_set_mouse(bx1_handle h, int dx, int dy, int buttons);

// ----------------------------------------------------------------------
// Media
// ----------------------------------------------------------------------

/// drv: 0-3 (USE_FLOPPY_DISK=4); the Nim UI only needs to expose 0-1 per
/// BluePrint's "no FDD 3/4" policy, but the bridge does not enforce that.
/// Returns 1 if the disk is inserted after the call, 0 otherwise.
int bx1_open_floppy(bx1_handle h, int drv, const char* path, int bank);
void bx1_close_floppy(bx1_handle h, int drv);
/// Number of D88 banks in the currently mounted image (1 if not multi-disk).
int bx1_get_floppy_bank_count(bx1_handle h, int drv);
/// UTF-8 (or whatever encoding the D88 header used) disk name for `bank`;
/// empty string if out of range.
const char* bx1_get_floppy_bank_name(bx1_handle h, int drv, int bank);

/// play != 0: play back path as a CMT tape image. play == 0: record onto
/// it. Returns 1 if a tape is inserted after the call, 0 otherwise.
/// USE_TAPE=1 for X1turboZ, so there is only one deck.
int bx1_open_tape(bx1_handle h, const char* path, int play);
void bx1_close_tape(bx1_handle h);

// ----------------------------------------------------------------------
// State save/load
// ----------------------------------------------------------------------

/// Always returns 1: the core's save_state()/load_state() are fire-and
/// -forget (void return) with no success/failure signal of their own.
int bx1_save_state(bx1_handle h, const char* path);
int bx1_load_state(bx1_handle h, const char* path);

// ----------------------------------------------------------------------
// Configuration
// ----------------------------------------------------------------------

/// type: USE_MONITOR_TYPE values (15kHz/24kHz for X1turboZ).
void bx1_set_monitor_type(bx1_handle h, int type);
int bx1_get_monitor_type(bx1_handle h);
/// type: USE_SOUND_TYPE values (0 = PSG only, 1 = +1 CZ-8BS1 FM board,
/// 2 = +2 CZ-8BS1 FM boards).
void bx1_set_sound_type(bx1_handle h, int type);
int bx1_get_sound_type(bx1_handle h);
/// device: USE_SOUND_VOLUME channel index. decibel_l/decibel_r: passed
/// straight through to EMU::set_sound_device_volume.
void bx1_set_volume(bx1_handle h, int device, int decibel_l, int decibel_r);
/// USE_SCANLINE: draws every other output line black instead of
/// duplicating it, approximating a CRT's scanline gaps.
void bx1_set_scan_line(bx1_handle h, int enabled);
int bx1_get_scan_line(bx1_handle h);

#ifdef __cplusplus
}
#endif

#endif // BUBIX1_API_H
