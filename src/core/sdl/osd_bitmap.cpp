/*
	Skelton for retropc emulator

	Author : Takeda.Toshiya
	Date   : 2015.11.26-

	[ sdl dependent ]

	BubiX1turboZ: printer bitmap API (USE_PRINTER; used by vm/mz1p17.cpp).

	Geometric drawing (points/lines/rectangles/stretch) is implemented for
	real, since it is cheap and host independent. Text rendering and file
	output are intentionally no-ops for now: proper text needs a font
	renderer and PNG output needs a codec, neither of which is worth
	pulling in for dot-matrix printer emulation that no market X1 game
	depends on to boot or play. Revisit if a title turns out to need it.
*/

#include "osd.h"

#ifdef USE_PRINTER

static inline scrntype_t make_argb(uint8_t r, uint8_t g, uint8_t b)
{
	// Alpha is left at 0, matching vm_screen_buffer's convention (see
	// docs/dev/DevelopmentPlan.md 1.4: textures must use SDL_BLENDMODE_NONE).
	return ((scrntype_t)r << 16) | ((scrntype_t)g << 8) | (scrntype_t)b;
}

void OSD::create_bitmap(bitmap_t *bitmap, int width, int height)
{
	allocate_screen_buffer(bitmap, width, height);
}

void OSD::release_bitmap(bitmap_t *bitmap)
{
	release_screen_buffer(bitmap);
}

void OSD::create_font(font_t *font, const _TCHAR *family, int width, int height, int rotate, bool bold, bool italic)
{
	// Text rendering is not implemented; record the request so
	// font->initialized() is at least consistent, but draw_text_to_bitmap()
	// and get_text_width() do nothing with it.
	strncpy(font->family, family, sizeof(font->family) - 1);
	font->family[sizeof(font->family) - 1] = '\0';
	font->width = width;
	font->height = height ? height : 1;
	font->rotate = rotate;
	font->bold = bold;
	font->italic = italic;
}

void OSD::release_font(font_t *font)
{
	font->height = 0;
}

void OSD::create_pen(pen_t *pen, int width, uint8_t r, uint8_t g, uint8_t b)
{
	pen->width = width ? width : 1;
	pen->r = r;
	pen->g = g;
	pen->b = b;
}

void OSD::release_pen(pen_t *pen)
{
	pen->width = 0;
}

void OSD::clear_bitmap(bitmap_t *bitmap, uint8_t r, uint8_t g, uint8_t b)
{
	if(!bitmap->initialized()) {
		return;
	}
	scrntype_t color = make_argb(r, g, b);
	int count = bitmap->width * bitmap->height;
	for(int i = 0; i < count; i++) {
		bitmap->lpBmp[i] = color;
	}
}

int OSD::get_text_width(bitmap_t *bitmap, font_t *font, const char *text)
{
	return 0;
}

void OSD::draw_text_to_bitmap(bitmap_t *bitmap, font_t *font, int x, int y, const char *text, uint8_t r, uint8_t g, uint8_t b)
{
}

void OSD::draw_point_to_bitmap(bitmap_t *bitmap, int x, int y, uint8_t r, uint8_t g, uint8_t b)
{
	if(!bitmap->initialized() || x < 0 || y < 0 || x >= bitmap->width || y >= bitmap->height) {
		return;
	}
	bitmap->get_buffer(y)[x] = make_argb(r, g, b);
}

void OSD::draw_line_to_bitmap(bitmap_t *bitmap, pen_t *pen, int sx, int sy, int ex, int ey)
{
	if(!bitmap->initialized()) {
		return;
	}
	// Bresenham; pen width beyond 1px is not honored (dot-matrix printer
	// output does not need it to be legible).
	int dx = abs(ex - sx), sx_step = sx < ex ? 1 : -1;
	int dy = -abs(ey - sy), sy_step = sy < ey ? 1 : -1;
	int err = dx + dy;
	int x = sx, y = sy;
	for(;;) {
		draw_point_to_bitmap(bitmap, x, y, pen->r, pen->g, pen->b);
		if(x == ex && y == ey) {
			break;
		}
		int e2 = 2 * err;
		if(e2 >= dy) {
			err += dy;
			x += sx_step;
		}
		if(e2 <= dx) {
			err += dx;
			y += sy_step;
		}
	}
}

void OSD::draw_rectangle_to_bitmap(bitmap_t *bitmap, int x, int y, int width, int height, uint8_t r, uint8_t g, uint8_t b)
{
	if(!bitmap->initialized()) {
		return;
	}
	scrntype_t color = make_argb(r, g, b);
	int x0 = x < 0 ? 0 : x;
	int y0 = y < 0 ? 0 : y;
	int x1 = x + width > bitmap->width ? bitmap->width : x + width;
	int y1 = y + height > bitmap->height ? bitmap->height : y + height;
	for(int yy = y0; yy < y1; yy++) {
		scrntype_t* row = bitmap->get_buffer(yy);
		for(int xx = x0; xx < x1; xx++) {
			row[xx] = color;
		}
	}
}

void OSD::stretch_bitmap(bitmap_t *dest, int dest_x, int dest_y, int dest_width, int dest_height, bitmap_t *source, int source_x, int source_y, int source_width, int source_height)
{
	if(!dest->initialized() || !source->initialized() || dest_width <= 0 || dest_height <= 0 || source_width <= 0 || source_height <= 0) {
		return;
	}
	for(int yy = 0; yy < dest_height; yy++) {
		int dy = dest_y + yy;
		if(dy < 0 || dy >= dest->height) {
			continue;
		}
		int sy = source_y + yy * source_height / dest_height;
		if(sy < 0 || sy >= source->height) {
			continue;
		}
		scrntype_t* srow = source->get_buffer(sy);
		scrntype_t* drow = dest->get_buffer(dy);
		for(int xx = 0; xx < dest_width; xx++) {
			int dxp = dest_x + xx;
			if(dxp < 0 || dxp >= dest->width) {
				continue;
			}
			int sx = source_x + xx * source_width / dest_width;
			if(sx < 0 || sx >= source->width) {
				continue;
			}
			drow[dxp] = srow[sx];
		}
	}
}
#endif

void OSD::write_bitmap_to_file(bitmap_t *bitmap, const _TCHAR *file_path)
{
	// Not implemented: needs an image codec (PNG) that is not worth pulling
	// in for dot-matrix printer output. See file header comment.
}
