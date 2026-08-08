/*
	Skelton for retropc emulator

	Author : Takeda.Toshiya
	Date   : 2015.11.26-

	[ sdl dependent ]

	BubiX1turboZ: sound ring buffer.

	Unlike win32's OSD, which paces vm->create_sound() calls off a
	DirectSound playback cursor (only synthesizing once the host has
	consumed roughly half its buffer), this OSD gates on the ring buffer's
	own occupancy: skip create_sound() while it is already comfortably
	full. This matters because vm->create_sound() advances the VM
	internally by however many frames it takes to fill one sound_samples
	chunk (~6 VM frames at 62500Hz/100ms latency and 61.94fps) and reports
	that count via extra_frames, which EMU::run() (emu.cpp) uses to skip
	its own vm->run() call for this tick. Calling create_sound() on every
	single update_sound() tick - as an earlier version of this file did -
	means every bx1_run_frame() call from the host advances the VM by a
	whole chunk instead of one frame, so a host loop paced at 61.94Hz runs
	the machine several times too fast while still looking correct in a
	framebuffer/audio-presence smoke test (see docs/dev/DevelopmentPlan.md
	phase 4/5 notes). Gating below reproduces win32's "only synthesize
	when the buffer actually needs it" behavior without touching any host
	audio API.

	Playback pacing (calling bx1_run_frame while
	bx1_get_buffered_audio_frames() stays under the desired latency) is
	the Nim layer's job - see the phase 1 architecture note "frame sync is
	audio-clock driven" in docs/dev/DevelopmentPlan.md.
*/

#include "osd.h"

void OSD::update_sound(int* extra_frames)
{
	*extra_frames = 0;
	if(!sound_available) {
		return;
	}

	pthread_mutex_lock(&sound_mutex);
	// Keep roughly two chunks buffered - enough headroom that a host tick
	// jitter doesn't underrun, but not so much that audio (and, since
	// this is also the VM-advance trigger, gameplay) lags noticeably
	// behind host real time.
	bool need_more = sound_ring_count < 2 * sound_samples;
	pthread_mutex_unlock(&sound_mutex);
	if(!need_more) {
		// Ring buffer already has enough headroom; let this tick advance
		// the VM by exactly one frame via the plain vm->run() path in
		// EMU::run() instead.
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

int OSD::get_buffered_sound_frames()
{
	pthread_mutex_lock(&sound_mutex);
	int n = sound_ring_count;
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
