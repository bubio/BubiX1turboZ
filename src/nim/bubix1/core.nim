## Nim bindings for the BubiX1turboZ C ABI bridge (`src/bridge/bubix1_api.h`).
##
## Every proc here is a 1:1 `importc` wrapper; no policy lives in this
## module. See `bubix1_api.h` for the parameter/return semantics - the
## comments are not repeated here to avoid the two drifting apart.

{.pragma: bx1, header: "bubix1_api.h", cdecl.}

type
  Bx1Handle* = pointer

proc bx1Create*(baseDir: cstring): Bx1Handle {.importc: "bx1_create", bx1.}
proc bx1Destroy*(h: Bx1Handle) {.importc: "bx1_destroy", bx1.}
proc bx1Reset*(h: Bx1Handle) {.importc: "bx1_reset", bx1.}
proc bx1SpecialReset*(h: Bx1Handle) {.importc: "bx1_special_reset", bx1.}

proc bx1RunFrame*(h: Bx1Handle): cint {.importc: "bx1_run_frame", bx1.}
proc bx1DrawScreen*(h: Bx1Handle) {.importc: "bx1_draw_screen", bx1.}
proc bx1Lock*(h: Bx1Handle) {.importc: "bx1_lock", bx1.}
proc bx1Unlock*(h: Bx1Handle) {.importc: "bx1_unlock", bx1.}

proc bx1GetFramebuffer*(h: Bx1Handle): ptr UncheckedArray[uint32]
  {.importc: "bx1_get_framebuffer", bx1.}
proc bx1GetScreenWidth*(h: Bx1Handle): cint {.importc: "bx1_get_screen_width", bx1.}
proc bx1GetScreenHeight*(h: Bx1Handle): cint {.importc: "bx1_get_screen_height", bx1.}
proc bx1GetAspectHeight*(h: Bx1Handle): cint {.importc: "bx1_get_aspect_height", bx1.}

proc bx1GetActualSoundRate*(h: Bx1Handle): cint
  {.importc: "bx1_get_actual_sound_rate", bx1.}
proc bx1PullAudio*(h: Bx1Handle, dst: ptr int16, frames: cint): cint
  {.importc: "bx1_pull_audio", bx1.}
proc bx1GetBufferedAudioFrames*(h: Bx1Handle): cint
  {.importc: "bx1_get_buffered_audio_frames", bx1.}
proc bx1MuteSound*(h: Bx1Handle) {.importc: "bx1_mute_sound", bx1.}

proc bx1KeyDown*(h: Bx1Handle, vkCode: cint, repeat: cint)
  {.importc: "bx1_key_down", bx1.}
proc bx1KeyUp*(h: Bx1Handle, vkCode: cint) {.importc: "bx1_key_up", bx1.}
proc bx1SetJoy*(h: Bx1Handle, index: cint, status: uint32)
  {.importc: "bx1_set_joy", bx1.}
proc bx1SetMouse*(h: Bx1Handle, dx, dy, buttons: cint)
  {.importc: "bx1_set_mouse", bx1.}

proc bx1OpenFloppy*(h: Bx1Handle, drv: cint, path: cstring, bank: cint): cint
  {.importc: "bx1_open_floppy", bx1.}
proc bx1CloseFloppy*(h: Bx1Handle, drv: cint) {.importc: "bx1_close_floppy", bx1.}
proc bx1GetFloppyBankCount*(h: Bx1Handle, drv: cint): cint
  {.importc: "bx1_get_floppy_bank_count", bx1.}
proc bx1GetFloppyBankName*(h: Bx1Handle, drv, bank: cint): cstring
  {.importc: "bx1_get_floppy_bank_name", bx1.}

proc bx1OpenTape*(h: Bx1Handle, path: cstring, play: cint): cint
  {.importc: "bx1_open_tape", bx1.}
proc bx1CloseTape*(h: Bx1Handle) {.importc: "bx1_close_tape", bx1.}

proc bx1SaveState*(h: Bx1Handle, path: cstring): cint {.importc: "bx1_save_state", bx1.}
proc bx1LoadState*(h: Bx1Handle, path: cstring): cint {.importc: "bx1_load_state", bx1.}

proc bx1SetMonitorType*(h: Bx1Handle, kind: cint) {.importc: "bx1_set_monitor_type", bx1.}
proc bx1SetSoundType*(h: Bx1Handle, kind: cint) {.importc: "bx1_set_sound_type", bx1.}
proc bx1SetVolume*(h: Bx1Handle, device, decibelL, decibelR: cint)
  {.importc: "bx1_set_volume", bx1.}
