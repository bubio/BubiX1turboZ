/*
	Skelton for retropc emulator

	Author : Takeda.Toshiya
	Date   : 2015.11.26-

	[ sdl dependent ]

	BubiX1turboZ: MIDI stub (phase 0.6 group C: USE_MIDI is defined for
	X1turboZ, so these must exist, but no market X1 game depends on MIDI
	I/O to boot or play - see docs/dev/DevelopmentPlan.md 0.6).
*/

#include "osd.h"

#ifdef USE_MIDI
void OSD::send_to_midi(uint8_t data)
{
}

bool OSD::recv_from_midi(uint8_t *data)
{
	return false;
}
#endif
