/*
	Skelton for retropc emulator

	Author : Takeda.Toshiya
	Date   : 2015.11.26-

	[ sdl dependent ]

	BubiX1turboZ: debugger console stubs (phase 0.6 group D).

	USE_DEBUGGER stays defined (see docs/dev/DevelopmentPlan.md 0.5.1), but
	no interactive console is exposed on this port. These are no-op/closed
	stand-ins so debugger.cpp links; nothing here is reachable from a normal
	run.
*/

#include "osd.h"

void OSD::open_console(int width, int height, const _TCHAR* title)
{
}

void OSD::close_console()
{
}

unsigned int OSD::get_console_code_page()
{
	return 0;
}

void OSD::set_console_text_attribute(unsigned short attr)
{
}

void OSD::write_console(const _TCHAR* buffer, unsigned int length)
{
}

int OSD::read_console_input(_TCHAR* buffer, unsigned int length)
{
	return 0;
}

bool OSD::is_console_key_pressed(int vk)
{
	return false;
}

bool OSD::is_console_closed()
{
	return true;
}

void OSD::close_debugger_console()
{
}
