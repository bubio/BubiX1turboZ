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
/// The *character* a keystroke produced, as opposed to the physical key
/// bx1_key_down reports - the equivalent of Win32's WM_CHAR, which the
/// original app forwards alongside WM_KEYDOWN. Send it for every typed
/// character; the core ignores it unless Romaji to Kana is on, and when
/// that is on it is the ONLY path by which ordinary keys reach the guest
/// (EMU::key_down stops forwarding them and feeds the auto key instead).
void bx1_key_char(bx1_handle h, int code);
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
/// Returns 1 if `path` is a readable file the request was handed to the
/// core for, 0 otherwise. Note that the disk is NOT necessarily inserted
/// by the time this returns: swapping a disk into an occupied drive makes
/// the core eject first and complete the insert about half a second later,
/// so poll bx1_is_floppy_disk_inserted() rather than assuming.
int bx1_open_floppy(bx1_handle h, int drv, const char* path, int bank);
void bx1_close_floppy(bx1_handle h, int drv);
/// Number of D88 banks in the currently mounted image (1 if not multi-disk).
int bx1_get_floppy_bank_count(bx1_handle h, int drv);
/// UTF-8 (or whatever encoding the D88 header used) disk name for `bank`;
/// empty string if out of range.
const char* bx1_get_floppy_bank_name(bx1_handle h, int drv, int bank);
/// Path and bank the core currently has on `drv`, or "" / -1 when the drive
/// is empty. Note that the core records the image file alone - never the
/// archive or playlist it came from - so this is a coarser answer than a
/// host that tracks its own mounts already has. bx1_vm_state_save/_load do
/// not touch this bookkeeping either way (they carry device state only).
const char* bx1_get_floppy_path(bx1_handle h, int drv);
int bx1_get_floppy_bank(bx1_handle h, int drv);

/// One disk inside a D88-family image, as bx1_scan_d88_banks reports it.
typedef struct {
	/// The 17 header bytes at offset 0x00, NUL-terminated. Whatever encoding
	/// the image was written in (Shift-JIS in practice); decoding is the
	/// host's job, exactly as for bx1_get_floppy_bank_name.
	char name[18];
	/// 0 = 2D, 1 = 2DD, 2 = 2HD, 3 = 1.44M, -1 = unknown. Same dense
	/// encoding bx1_create_blank_floppy_disk takes, not the header's own.
	int media_type;
	/// Header byte 0x1a; the medium's own flag, not the drive's.
	int write_protected;
} bx1_d88_bank;

/// Enumerates the disks in a D88-family image WITHOUT touching any drive, so
/// the host can offer a choice before committing one to a drive.
/// bx1_get_floppy_bank_count/_name cannot serve that purpose: the core only
/// fills them as a side effect of bx1_open_floppy, and it records neither the
/// media type nor the write-protect flag.
///
/// Writes at most `max_banks` entries into `out` and returns how many it
/// wrote. A readable image that is not D88-family (a solid .2d/.2hd dump)
/// counts as a single unnamed disk, so callers can treat every image the
/// same way. Returns 0 for an unreadable or malformed file.
int bx1_scan_d88_banks(const char* path, int max_banks, bx1_d88_bank* out);

/// play != 0: play back path as a CMT tape image. play == 0: record onto
/// it. Returns 1 if a tape is inserted after the call, 0 otherwise.
/// USE_TAPE=1 for X1turboZ, so there is only one deck.
int bx1_open_tape(bx1_handle h, const char* path, int play);
void bx1_close_tape(bx1_handle h);

/// drv: 0-3, matching bx1_open_floppy. Returns 1 while that drive's
/// motor is spun up and selected (i.e. the FDC is actively reading or
/// writing it right now), 0 otherwise - intended for a live activity
/// lamp, not "is a disk inserted" (see bx1_open_floppy for that).
int bx1_is_floppy_disk_accessed(bx1_handle h, int drv);
/// 1 while the tape deck is playing back or recording, 0 otherwise.
int bx1_is_tape_active(bx1_handle h);
/// 1 while drive `drv` should show its *second* activity color. The
/// original Windows status bar picks between two "on" lamp bitmaps with
/// this (access_on.bmp vs access_green.bmp); the core lights it only for a
/// drive currently configured as 2HD, so a 2D game never triggers it.
int bx1_floppy_disk_indicator_color(bx1_handle h, int drv);
int bx1_is_floppy_disk_inserted(bx1_handle h, int drv);
int bx1_is_tape_inserted(bx1_handle h);
/// The deck's own human-readable state, exactly as the original status bar
/// prints it after "CMT:" - "Play (37 %)", "Stop (End-of-Tape)", "Record",
/// "APSS Rewind", ... Never NULL; an empty string means no message. The
/// returned pointer is owned by the core and is only valid until the next
/// call into the emulator, so copy it before doing anything else.
const char* bx1_get_tape_message(bx1_handle h);

/// Write protection is a property of the mounted image, not of the drive,
/// so it resets when a new disk is inserted.
void bx1_set_floppy_write_protected(bx1_handle h, int drv, int protect);
int bx1_get_floppy_write_protected(bx1_handle h, int drv);
/// Emulate the real drive's rotation/seek delays instead of completing
/// transfers immediately. Needed by copy-protected titles that time the
/// FDC; costs speed, hence the per-drive switch (config.correct_disk_timing).
void bx1_set_correct_disk_timing(bx1_handle h, int drv, int enabled);
int bx1_get_correct_disk_timing(bx1_handle h, int drv);
/// Treat CRC errors on the medium as valid data (config.ignore_disk_crc).
/// Some protection schemes store deliberately corrupt sectors.
void bx1_set_ignore_disk_crc(bx1_handle h, int drv, int enabled);
int bx1_get_ignore_disk_crc(bx1_handle h, int drv);
/// media_type: 0 = 2D, 1 = 2DD, 2 = 2HD (mapped to the core's MEDIA_TYPE_*
/// constants internally). Creates an empty D88 at `path`; does not mount it.
int bx1_create_blank_floppy_disk(bx1_handle h, const char* path, int media_type);

/// The CMT deck's transport buttons, matching the original's CMT menu.
void bx1_tape_push_play(bx1_handle h);
void bx1_tape_push_stop(bx1_handle h);
void bx1_tape_push_fast_forward(bx1_handle h);
void bx1_tape_push_fast_rewind(bx1_handle h);
void bx1_tape_push_apss_forward(bx1_handle h);
void bx1_tape_push_apss_rewind(bx1_handle h);
/// Reshape the tape waveform before decoding it (config.wave_shaper), which
/// recovers data from noisy WAV rips. Irrelevant for clean T77/CMT images.
void bx1_set_wave_shaper(bx1_handle h, int enabled);
int bx1_get_wave_shaper(bx1_handle h);

// ----------------------------------------------------------------------
// State save/load
// ----------------------------------------------------------------------

/// These deliberately do NOT call EMU::save_state()/load_state(). Those
/// write three extra blocks - config, media_status_t and d88_file - whose
/// on-disk layout depends on _MAX_PATH and whose media bookkeeping the
/// host layer already keeps in a better form. What is written here is
/// exactly what the VM's devices serialize, wrapped by the host in its own
/// container format. See docs/dev/SaveState.md.

/// Writes the VM device state to `path` (raw, uncompressed; the host
/// compresses it as a container section). Locks the VM internally, so call
/// it on a frame boundary. Returns 1 on success, 0 if the file could not
/// be written or a device refused to serialize.
int bx1_vm_state_save(bx1_handle h, const char* path);

/// Applies a blob previously written by bx1_vm_state_save().
///
/// The current state is dumped to `rollback_path` first and restored if
/// the load fails: VM::process_state() returns false only *after* having
/// overwritten part of the machine, so without the snapshot a truncated or
/// mismatched blob would leave the emulator unusable with no way back.
/// `rollback_path` must be writable and is removed before returning; the
/// caller picks the location (the core would put it in its own base_dir,
/// which holds the ROMs).
///
/// Returns 1 on success. On 0 the machine is back to what it was, unless
/// the rollback dump itself could not be written - which is reported as 0
/// too, so a caller that must know can compare against the pre-call state.
int bx1_vm_state_load(bx1_handle h, const char* path, const char* rollback_path);

/// Identifies the vendored core's device state layout. The blob above is
/// opaque to this bridge - it is the vendored devices' own format, with
/// each device's private STATE_VERSION inside - so a state written by a
/// different core build cannot be detected any other way. Bump this by
/// hand whenever src/core/ is re-vendored, and refuse states that carry a
/// different value.
uint32_t bx1_core_state_id(void);

/// Config values that make the original's EMU::load_state() throw the VM
/// away and build a new one. Nothing here has a setter: this bridge cannot
/// reconstruct the VM (EMU::vm is protected and the only rebuild path is
/// inside EMU::load_state_tmp), so a host that drives process_state()
/// directly has to compare these against a state's recorded values and
/// refuse the load when they differ. Everything the UI *can* change has
/// its own setter elsewhere in this header.
int bx1_get_printer_type(bx1_handle h);
int bx1_get_serial_type(bx1_handle h);
int bx1_get_sound_frequency(bx1_handle h);
int bx1_get_sound_latency(bx1_handle h);

// ----------------------------------------------------------------------
// Speed control
// ----------------------------------------------------------------------

/// power: 0-4, meaning a CPU clock multiplier of 1/2/4/8/16 (the original's
/// Control > "CPU x1".."CPU x16"). Not a host frame rate: the VM really
/// runs that many Z80 cycles per emulated frame.
void bx1_set_cpu_power(bx1_handle h, int power);
int bx1_get_cpu_power(bx1_handle h);
/// Run the VM as fast as the host allows, ignoring the 61.94Hz frame clock.
void bx1_set_full_speed(bx1_handle h, int enabled);
int bx1_get_full_speed(bx1_handle h);
/// Re-check device timing at every M1/read/write cycle instead of once per
/// scheduled event. More accurate, considerably slower.
void bx1_set_drive_vm_in_opecode(bx1_handle h, int enabled);
int bx1_get_drive_vm_in_opecode(bx1_handle h);

// ----------------------------------------------------------------------
// Auto key (the original's Control > Paste / Stop / Romaji to Kana)
// ----------------------------------------------------------------------

/// Types `text` into the guest as if on the real keyboard. `text` must be
/// plain ASCII/JIS X 0201; the core drops anything it cannot map.
void bx1_start_auto_key(bx1_handle h, const char* text);
void bx1_stop_auto_key(bx1_handle h);
int bx1_is_auto_key_running(bx1_handle h);
/// Convert romaji in pasted text to kana keystrokes (config.romaji_to_kana).
void bx1_set_romaji_to_kana(bx1_handle h, int enabled);
int bx1_get_romaji_to_kana(bx1_handle h);

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
/// USE_DRIVE_TYPE: which device the IPL tries to boot from. Reaches the
/// guest as DIP switch bits 1-3 of I/O port 0x1ff0, so it only takes effect
/// on the next reset. 0 = 2D, 1 = 2DD, 2 = 2HD, 6 = 8-inch 1S.
void bx1_set_drive_type(bx1_handle h, int type);
int bx1_get_drive_type(bx1_handle h);
/// USE_KEYBOARD_TYPE: 0 = mode A, 1 = mode B (the X1's physical keyboard
/// mode switch, which changes how some keys are reported).
void bx1_set_keyboard_type(bx1_handle h, int type);
int bx1_get_keyboard_type(bx1_handle h);
/// Mechanical/analog sounds mixed in alongside the PSG and FM channels:
/// the drive's seek noise, the tape motor, the raw FSK signal, and any
/// voice track on the tape.
void bx1_set_sound_noise_fdd(bx1_handle h, int enabled);
int bx1_get_sound_noise_fdd(bx1_handle h);
void bx1_set_sound_noise_cmt(bx1_handle h, int enabled);
int bx1_get_sound_noise_cmt(bx1_handle h);
void bx1_set_sound_tape_signal(bx1_handle h, int enabled);
int bx1_get_sound_tape_signal(bx1_handle h);
void bx1_set_sound_tape_voice(bx1_handle h, int enabled);
int bx1_get_sound_tape_voice(bx1_handle h);

/// Number of independently mixable sound sources (USE_SOUND_VOLUME = 7 for
/// X1turboZ) and their display names ("PSG", "CZ-8BS1 #1", "Noise (FDD)",
/// ...). Both are compile-time constants of the core, hence no handle.
int bx1_get_sound_volume_count(void);
const char* bx1_get_sound_device_caption(int index);
/// Volumes are in decibels, clamped by the core to [-40, 0].
int bx1_get_volume_l(bx1_handle h, int device);
int bx1_get_volume_r(bx1_handle h, int device);

#ifdef __cplusplus
}
#endif

#endif // BUBIX1_API_H
