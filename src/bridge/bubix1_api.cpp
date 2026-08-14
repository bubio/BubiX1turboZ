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
// For MEDIA_TYPE_* (the D88 header's own media byte), used by
// bx1_create_blank_floppy_disk. emu.h does not pull this in.
#include "../core/vm/disk.h"

namespace {
inline EMU* emu_of(bx1_handle h)
{
	return static_cast<EMU*>(h);
}
}

bx1_handle bx1_create(const char* base_dir, const char* config_path)
{
	set_application_path(base_dir);

	// load_config() unconditionally calls initialize_config() itself
	// before applying any overrides (config.cpp: it's written to load a
	// complete config, not to patch one), so a default assigned before
	// calling it would just be wiped out. Only call it when there is
	// actually a file to read; otherwise fall back to
	// initialize_config() and our own default below.
	bool loaded = config_path != NULL && config_path[0] != '\0' && FILEIO::IsFileExisting(config_path);
	if(loaded) {
		load_config(config_path);
	} else {
		initialize_config();
	}

	// x1.h defines no MONITOR_TYPE_DEFAULT, so a fresh config leaves
	// config.monitor_type at 0 ("High Resolution" in the original app's
	// Device > Display menu). That mode has a genuine, pre-existing text
	// rendering bug confirmed against the original Windows build itself
	// (top half of each glyph missing outside the IPL's own hardcoded
	// font) - see docs/dev/DevelopmentPlan.md phase 5's open item. 1
	// ("Standard") renders correctly, so use that as the default on a
	// fresh install; a saved config.ini's own value always wins. Not a
	// core change: x1.h/config.cpp are untouched.
	if(!loaded) {
		config.monitor_type = 1;
	}

	EMU* emu = new EMU();
	// VM::update_dipswitch() (which is what actually latches
	// config.monitor_type into the I/O port the boot ROM reads at
	// 0x1ff0) only runs from VM::update_config(), never from the VM's
	// constructor. Without this call, the monitor_type set above (or
	// loaded from config.ini) has no effect until the user opens the
	// Settings menu and changes something, and the machine boots as if
	// monitor_type were still 0.
	emu->update_config();
	return emu;
}

void bx1_destroy(bx1_handle h)
{
	delete emu_of(h);
}

void bx1_save_config(bx1_handle h, const char* config_path)
{
	save_config(config_path);
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

int bx1_get_buffered_audio_frames(bx1_handle h)
{
	return emu_of(h)->get_osd()->get_buffered_sound_frames();
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

void bx1_key_char(bx1_handle h, int code)
{
	emu_of(h)->key_char((char)code);
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
	if(path == NULL || !FILEIO::IsFileExisting(path)) {
		return 0;
	}
	emu->open_floppy_disk(drv, path, bank);
	// Not is_floppy_disk_inserted(): when the drive already holds a disk,
	// EMU::open_floppy_disk ejects it and defers the insert by half a
	// second of emulated time (floppy_disk_status[drv].wait_count, applied
	// later by update_media) so the guest sees a real disk change. Reading
	// the inserted flag here would therefore report failure for every swap,
	// including picking a different bank of the same D88. wait_count is
	// private to EMU, so success is reported for a readable file instead -
	// which is what a caller actually needs to know.
	return 1;
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

const char* bx1_get_floppy_path(bx1_handle h, int drv)
{
	if(drv < 0 || drv >= USE_FLOPPY_DISK) {
		return "";
	}
	return emu_of(h)->d88_file[drv].path;
}

int bx1_get_floppy_bank(bx1_handle h, int drv)
{
	if(drv < 0 || drv >= USE_FLOPPY_DISK) {
		return -1;
	}
	return emu_of(h)->d88_file[drv].cur_bank;
}

namespace {
/// The smallest a D88 disk header can be: 0x20 bytes of fixed fields plus
/// 164 track pointers. EMU::open_floppy_disk uses the same bound to decide
/// whether another disk follows.
const uint32_t D88_HEADER_SIZE = 0x2b0;

/// Maps the D88 header's own media byte to the dense index the rest of this
/// API uses (see bx1_create_blank_floppy_disk).
int dense_media_type(uint8_t header_byte)
{
	switch(header_byte) {
	case MEDIA_TYPE_2D:  return 0;
	case MEDIA_TYPE_2DD: return 1;
	case MEDIA_TYPE_2HD: return 2;
	case MEDIA_TYPE_144: return 3;
	}
	return -1;
}

bool is_d88_family(const char* path)
{
	return check_file_extension(path, _T(".d88")) || check_file_extension(path, _T(".d8e")) ||
	       check_file_extension(path, _T(".d77")) || check_file_extension(path, _T(".1dd"));
}
}

int bx1_scan_d88_banks(const char* path, int max_banks, bx1_d88_bank* out)
{
	if(path == NULL || out == NULL || max_banks <= 0 || !FILEIO::IsFileExisting(path)) {
		return 0;
	}
	if(!is_d88_family(path)) {
		// A solid dump carries no header at all, so there is nothing to
		// report beyond "one disk, unknown everything". Saying so lets the
		// caller run every image through the same code path.
		memset(&out[0], 0, sizeof(out[0]));
		out[0].media_type = -1;
		return 1;
	}

	FILEIO* fio = new FILEIO();
	int count = 0;
	if(fio->Fopen(path, FILEIO_READ_BINARY)) {
		fio->Fseek(0, FILEIO_SEEK_END);
		uint32_t file_size = fio->Ftell(), offset = 0;
		while(offset + D88_HEADER_SIZE <= file_size && count < max_banks) {
			bx1_d88_bank* bank = &out[count];
			memset(bank, 0, sizeof(*bank));

			fio->Fseek(offset, FILEIO_SEEK_SET);
			fio->Fread(bank->name, 17, 1);
			bank->name[17] = '\0';

			fio->Fseek(offset + 0x1a, FILEIO_SEEK_SET);
			bank->write_protected = fio->FgetUint8() != 0 ? 1 : 0;
			bank->media_type = dense_media_type(fio->FgetUint8());

			fio->Fseek(offset + 0x1c, FILEIO_SEEK_SET);
			const uint32_t disk_size = fio->FgetUint32_LE();
			count++;
			// EMU::open_floppy_disk trusts this self-describing size and
			// would spin on a zero, filling every bank with the same disk.
			// A size that cannot hold even a header ends the walk instead.
			if(disk_size < D88_HEADER_SIZE) {
				break;
			}
			offset += disk_size;
		}
		fio->Fclose();
	}
	delete fio;
	return count;
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

int bx1_is_floppy_disk_accessed(bx1_handle h, int drv)
{
	if(drv < 0 || drv >= USE_FLOPPY_DISK) {
		return 0;
	}
	// is_floppy_disk_accessed() returns a bitmask (bit N = drive N); this
	// reflects the disk controller's live motor/head state, not merely
	// "is a disk inserted", so it is the correct signal for an activity
	// lamp rather than bx1_open_floppy's return value.
	return (emu_of(h)->is_floppy_disk_accessed() & (1u << drv)) ? 1 : 0;
}

int bx1_is_tape_active(bx1_handle h)
{
	EMU* emu = emu_of(h);
	return (emu->is_tape_playing(0) || emu->is_tape_recording(0)) ? 1 : 0;
}

int bx1_floppy_disk_indicator_color(bx1_handle h, int drv)
{
	if(drv < 0 || drv >= USE_FLOPPY_DISK) {
		return 0;
	}
	return (emu_of(h)->floppy_disk_indicator_color() & (1u << drv)) ? 1 : 0;
}

int bx1_is_floppy_disk_inserted(bx1_handle h, int drv)
{
	return emu_of(h)->is_floppy_disk_inserted(drv) ? 1 : 0;
}

int bx1_is_tape_inserted(bx1_handle h)
{
	return emu_of(h)->is_tape_inserted(0) ? 1 : 0;
}

const char* bx1_get_tape_message(bx1_handle h)
{
	const _TCHAR* msg = emu_of(h)->get_tape_message(0);
	return msg != NULL ? msg : "";
}

void bx1_set_floppy_write_protected(bx1_handle h, int drv, int protect)
{
	// EMU overloads this name on the argument list: one setter taking
	// (drv, bool) and one getter taking (drv). Spelling out the bool keeps
	// the intended overload unambiguous.
	emu_of(h)->is_floppy_disk_protected(drv, protect != 0);
}

int bx1_get_floppy_write_protected(bx1_handle h, int drv)
{
	return emu_of(h)->is_floppy_disk_protected(drv) ? 1 : 0;
}

void bx1_set_correct_disk_timing(bx1_handle h, int drv, int enabled)
{
	if(drv < 0 || drv >= USE_FLOPPY_DISK) {
		return;
	}
	config.correct_disk_timing[drv] = (enabled != 0);
	emu_of(h)->update_config();
}

int bx1_get_correct_disk_timing(bx1_handle h, int drv)
{
	(void)h;
	if(drv < 0 || drv >= USE_FLOPPY_DISK) {
		return 0;
	}
	return config.correct_disk_timing[drv] ? 1 : 0;
}

void bx1_set_ignore_disk_crc(bx1_handle h, int drv, int enabled)
{
	if(drv < 0 || drv >= USE_FLOPPY_DISK) {
		return;
	}
	config.ignore_disk_crc[drv] = (enabled != 0);
	emu_of(h)->update_config();
}

int bx1_get_ignore_disk_crc(bx1_handle h, int drv)
{
	(void)h;
	if(drv < 0 || drv >= USE_FLOPPY_DISK) {
		return 0;
	}
	return config.ignore_disk_crc[drv] ? 1 : 0;
}

int bx1_create_blank_floppy_disk(bx1_handle h, const char* path, int media_type)
{
	// The core takes the D88 header's own encoding (0x00/0x10/0x20) rather
	// than a dense index; keep the bridge's argument dense so callers do
	// not have to know the on-disk format.
	static const uint8_t types[] = { MEDIA_TYPE_2D, MEDIA_TYPE_2DD, MEDIA_TYPE_2HD };
	if(media_type < 0 || media_type >= (int)(sizeof(types) / sizeof(types[0]))) {
		return 0;
	}
	return emu_of(h)->create_blank_floppy_disk(path, types[media_type]) ? 1 : 0;
}

void bx1_tape_push_play(bx1_handle h)
{
	emu_of(h)->push_play(0);
}

void bx1_tape_push_stop(bx1_handle h)
{
	emu_of(h)->push_stop(0);
}

void bx1_tape_push_fast_forward(bx1_handle h)
{
	emu_of(h)->push_fast_forward(0);
}

void bx1_tape_push_fast_rewind(bx1_handle h)
{
	emu_of(h)->push_fast_rewind(0);
}

void bx1_tape_push_apss_forward(bx1_handle h)
{
	emu_of(h)->push_apss_forward(0);
}

void bx1_tape_push_apss_rewind(bx1_handle h)
{
	emu_of(h)->push_apss_rewind(0);
}

void bx1_set_wave_shaper(bx1_handle h, int enabled)
{
	config.wave_shaper[0] = (enabled != 0);
	emu_of(h)->update_config();
}

int bx1_get_wave_shaper(bx1_handle h)
{
	(void)h;
	return config.wave_shaper[0] ? 1 : 0;
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

void bx1_set_cpu_power(bx1_handle h, int power)
{
	config.cpu_power = power;
	// EVENT caches config.cpu_power in its own `power` member: it reads the
	// config in its constructor and then only re-reads it from
	// EVENT::update_config(), which nothing but EMU::update_config() calls.
	// Without this the new multiplier is simply never picked up (the
	// original does the same thing - winmain.cpp calls update_config() right
	// after assigning config.cpu_power).
	emu_of(h)->update_config();
}

int bx1_get_cpu_power(bx1_handle h)
{
	(void)h;
	return config.cpu_power;
}

void bx1_set_full_speed(bx1_handle h, int enabled)
{
	(void)h;
	config.full_speed = (enabled != 0);
}

int bx1_get_full_speed(bx1_handle h)
{
	(void)h;
	return config.full_speed ? 1 : 0;
}

void bx1_set_drive_vm_in_opecode(bx1_handle h, int enabled)
{
	config.drive_vm_in_opecode = (enabled != 0);
	emu_of(h)->update_config();
}

int bx1_get_drive_vm_in_opecode(bx1_handle h)
{
	(void)h;
	return config.drive_vm_in_opecode ? 1 : 0;
}

void bx1_start_auto_key(bx1_handle h, const char* text)
{
	if(text == NULL || text[0] == '\0') {
		return;
	}
	EMU* emu = emu_of(h);
	// set_auto_key_list() takes a non-const buffer because it rewrites the
	// text in place while mapping characters to key codes; hand it a copy
	// rather than casting away const on the caller's string.
	//
	// Only ASCII survives the copy. The core reads the buffer as Shift-JIS,
	// treating 0x81-0x9f and 0xe0+ as lead bytes it skips two at a time, so
	// feeding it UTF-8 does not merely drop the non-ASCII characters - it
	// desynchronizes that scan and eats the first byte of whatever follows.
	// (Trace U+3042 = E3 81 82: 0xE3 skips 0x81, then 0x82 is itself in the
	// lead-byte range and skips the *next* character's first byte.) The host
	// clipboard is UTF-8, so filter here, matching bx1_key_char's caller.
	int len = (int)strlen(text);
	char* buf = new char[len + 1];
	int n = 0;
	for(int i = 0; i < len; i++) {
		if((unsigned char)text[i] < 0x80) {
			buf[n++] = text[i];
		}
	}
	buf[n] = '\0';
	if(n == 0) {
		delete[] buf;
		return;
	}
	emu->set_auto_key_list(buf, n);
	delete[] buf;
	emu->start_auto_key();
}

void bx1_stop_auto_key(bx1_handle h)
{
	emu_of(h)->stop_auto_key();
}

int bx1_is_auto_key_running(bx1_handle h)
{
	return emu_of(h)->is_auto_key_running() ? 1 : 0;
}

void bx1_set_romaji_to_kana(bx1_handle h, int enabled)
{
	(void)h;
	config.romaji_to_kana = (enabled != 0);
}

int bx1_get_romaji_to_kana(bx1_handle h)
{
	(void)h;
	return config.romaji_to_kana ? 1 : 0;
}

void bx1_set_monitor_type(bx1_handle h, int type)
{
	config.monitor_type = type;
	emu_of(h)->update_config();
}

int bx1_get_monitor_type(bx1_handle h)
{
	(void)h;
	return config.monitor_type;
}

void bx1_set_sound_type(bx1_handle h, int type)
{
	config.sound_type = type;
	emu_of(h)->update_config();
}

int bx1_get_sound_type(bx1_handle h)
{
	(void)h;
	return config.sound_type;
}

void bx1_set_volume(bx1_handle h, int device, int decibel_l, int decibel_r)
{
	emu_of(h)->set_sound_device_volume(device, decibel_l, decibel_r);
}

void bx1_set_scan_line(bx1_handle h, int enabled)
{
	config.scan_line = (enabled != 0);
	emu_of(h)->update_config();
}

int bx1_get_scan_line(bx1_handle h)
{
	(void)h;
	return config.scan_line ? 1 : 0;
}

void bx1_set_drive_type(bx1_handle h, int type)
{
	config.drive_type = type;
	emu_of(h)->update_config();
}

int bx1_get_drive_type(bx1_handle h)
{
	(void)h;
	return config.drive_type;
}

void bx1_set_keyboard_type(bx1_handle h, int type)
{
	config.keyboard_type = type;
	emu_of(h)->update_config();
}

int bx1_get_keyboard_type(bx1_handle h)
{
	(void)h;
	return config.keyboard_type;
}

void bx1_set_sound_noise_fdd(bx1_handle h, int enabled)
{
	config.sound_noise_fdd = (enabled != 0);
	emu_of(h)->update_config();
}

int bx1_get_sound_noise_fdd(bx1_handle h)
{
	(void)h;
	return config.sound_noise_fdd ? 1 : 0;
}

void bx1_set_sound_noise_cmt(bx1_handle h, int enabled)
{
	config.sound_noise_cmt = (enabled != 0);
	emu_of(h)->update_config();
}

int bx1_get_sound_noise_cmt(bx1_handle h)
{
	(void)h;
	return config.sound_noise_cmt ? 1 : 0;
}

void bx1_set_sound_tape_signal(bx1_handle h, int enabled)
{
	config.sound_tape_signal = (enabled != 0);
	emu_of(h)->update_config();
}

int bx1_get_sound_tape_signal(bx1_handle h)
{
	(void)h;
	return config.sound_tape_signal ? 1 : 0;
}

void bx1_set_sound_tape_voice(bx1_handle h, int enabled)
{
	config.sound_tape_voice = (enabled != 0);
	emu_of(h)->update_config();
}

int bx1_get_sound_tape_voice(bx1_handle h)
{
	(void)h;
	return config.sound_tape_voice ? 1 : 0;
}

int bx1_get_sound_volume_count(void)
{
	return USE_SOUND_VOLUME;
}

const char* bx1_get_sound_device_caption(int index)
{
	if(index < 0 || index >= USE_SOUND_VOLUME) {
		return "";
	}
	return sound_device_caption[index];
}

int bx1_get_volume_l(bx1_handle h, int device)
{
	(void)h;
	if(device < 0 || device >= USE_SOUND_VOLUME) {
		return 0;
	}
	return config.sound_volume_l[device];
}

int bx1_get_volume_r(bx1_handle h, int device)
{
	(void)h;
	if(device < 0 || device >= USE_SOUND_VOLUME) {
		return 0;
	}
	return config.sound_volume_r[device];
}
