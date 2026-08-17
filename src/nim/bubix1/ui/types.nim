## Data types shared between a `ui` facade and its backends.
##
## They live apart from both so that a backend can be handed one without
## importing the facade that calls it. Nothing here knows what a platform
## is; anything that does belongs in a backend directory.

type
  SlotCell* = object
    ## One cell of the save-state picker. `disks` may hold raw D88 header
    ## bytes (Shift-JIS); it is passed through untouched and decoded by
    ## the backend, keeping this app's single decoding point (see
    ## diskset.nim).
    caption*: string      ## "Slot 3"
    detail*: string       ## when it was taken, "" for an empty slot
    disks*: string        ## what was in the drives, "" if nothing
    thumbnail*: seq[byte] ## PNG, empty for an empty slot
    enabled*: bool
