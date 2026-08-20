## The save state slot picker: a grid of thumbnails, one per slot.
##
## Follows Bubilator88's SaveStateSheetView rather than the original's two
## submenus of ten numbered items - a state is worth choosing by what it
## looks like, which a menu cannot show. See docs/dev/SaveState.md
## section 9.

import ../i18n
import ./types
export types.SlotCell

when defined(macosx):
  from ./macos/statepicker as backend import nil
elif defined(linux):
  from ./linux/statepicker as backend import nil
else:
  from ./stub/statepicker as backend import nil

proc choose*(title: string, cells: seq[SlotCell]): int =
  ## Returns the chosen index, or -1 if the user cancelled. Blocks the
  ## caller (and so the emulation loop) until then - drop the audio the
  ## machine could not produce meanwhile once it returns.
  if cells.len == 0:
    return -1
  backend.choose(title, cells, tr(msgButtonCancel), tr(msgSlotEmpty))
