/*
	BubiX1turboZ - the save state slot picker (see statepicker.m).
*/

#ifndef BUBIX1_STATEPICKER_H
#define BUBIX1_STATEPICKER_H

#ifdef __cplusplus
extern "C" {
#endif

/// One cell of the grid. Every string is UTF-8 except `disks`, which may
/// carry the raw bytes of a D88 disk name (Shift-JIS in practice) and is
/// decoded on this side - see statepicker.m.
typedef struct {
	const char *caption; ///< "Slot 3"
	const char *detail;  ///< when it was taken, or "" for an empty slot
	const char *disks;   ///< what was in the drives, or ""
	const unsigned char *png; ///< thumbnail, or NULL for an empty slot
	int png_len;
	int enabled;         ///< 0 draws the cell dimmed and unclickable
} bx1_state_slot;

/// Runs the picker app-modally. Returns the chosen index, or -1 if the
/// user cancelled.
int bx1_state_picker(const char *title, const bx1_state_slot *slots, int count);

#ifdef __cplusplus
}
#endif

#endif
