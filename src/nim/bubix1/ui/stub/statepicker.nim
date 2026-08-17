## Does-nothing save-state picker for the platforms without a backend yet.

import ../types

proc choose*(title: string, cells: seq[SlotCell],
             cancelLabel, emptyLabel: string): int =
  ## -1, the answer a cancelled picker gives: no slot is read or written
  ## until a real one exists.
  -1
