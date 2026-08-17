## Does-nothing clipboard for the platforms without a backend yet.

proc text*(): string =
  ## Always empty, so Control > Paste types nothing.
  ""
