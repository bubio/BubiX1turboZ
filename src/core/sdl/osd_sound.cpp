/*
	Skelton for retropc emulator

	Author : Takeda.Toshiya
	Date   : 2015.11.26-

	[ sdl dependent ]

	BubiX1turboZ: sound ring buffer.

	Unlike win32's OSD, which paces vm->create_sound() calls off a DirectSound
	playback cursor, this OSD just synthesizes one chunk per update_sound()
	call and appends it to a ring buffer. Playback pacing (calling
	bx1_run_frame repeatedly based on how much the SDL audio callback has
	consumed) is the Nim layer's job — see the phase 1 architecture note
	"frame sync is audio-clock driven" in docs/dev/DevelopmentPlan.md.
*/

#include "osd.h"

void OSD::update_sound(int* extra_frames)
{
	*extra_frames = 0;
	if(!sound_available) {
		return;
	}

	uint16_t* sound_buffer = vm->create_sound(extra_frames);

	pthread_mutex_lock(&sound_mutex);
	if(sound_ring_buffer != NULL) {
		int16_t* src = sound_muted || sound_buffer == NULL ? NULL : (int16_t*)sound_buffer;
		for(int i = 0; i < sound_samples; i++) {
			int write_pos = (sound_ring_head + sound_ring_count) % sound_ring_capacity;
			if(sound_ring_count >= sound_ring_capacity) {
				// Ring buffer overrun: the host is not draining fast enough.
				// Drop the oldest frame rather than block the emulation
				// thread or grow the buffer unbounded.
				sound_ring_head = (sound_ring_head + 1) % sound_ring_capacity;
				sound_ring_count--;
			}
			if(src != NULL) {
				sound_ring_buffer[write_pos * 2 + 0] = src[i * 2 + 0];
				sound_ring_buffer[write_pos * 2 + 1] = src[i * 2 + 1];
			} else {
				sound_ring_buffer[write_pos * 2 + 0] = 0;
				sound_ring_buffer[write_pos * 2 + 1] = 0;
			}
			sound_ring_count++;
		}
	}
	pthread_mutex_unlock(&sound_mutex);
}

int OSD::pull_sound(int16_t* dst, int frames)
{
	pthread_mutex_lock(&sound_mutex);
	int n = frames < sound_ring_count ? frames : sound_ring_count;
	for(int i = 0; i < n; i++) {
		int read_pos = (sound_ring_head + i) % sound_ring_capacity;
		dst[i * 2 + 0] = sound_ring_buffer[read_pos * 2 + 0];
		dst[i * 2 + 1] = sound_ring_buffer[read_pos * 2 + 1];
	}
	sound_ring_head = (sound_ring_head + n) % sound_ring_capacity;
	sound_ring_count -= n;
	pthread_mutex_unlock(&sound_mutex);
	return n;
}

void OSD::mute_sound()
{
	sound_muted = true;
}

void OSD::stop_sound()
{
	sound_muted = true;
	pthread_mutex_lock(&sound_mutex);
	sound_ring_head = sound_ring_count = 0;
	pthread_mutex_unlock(&sound_mutex);
}

void OSD::start_record_sound()
{
	// Sound recording is a host UI feature; not implemented on the core
	// side (phase 0.6 group B).
}

void OSD::stop_record_sound()
{
	now_record_sound = false;
}

void OSD::restart_record_sound()
{
}
