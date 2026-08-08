## Nim bindings for the BubiX1turboZ C ABI bridge (`src/bridge/bubix1_api.h`).
##
## Every proc here is a 1:1 `importc` wrapper; no policy lives in this
## module. See `bubix1_api.h` for the parameter/return semantics - the
## comments are not repeated here to avoid the two drifting apart.

{.pragma: bx1, header: "bubix1_api.h", cdecl.}

type
  Bx1Handle* = pointer

proc bx1Create*(baseDir: cstring, configPath: cstring): Bx1Handle
  {.importc: "bx1_create", bx1.}
proc bx1Destroy*(h: Bx1Handle) {.importc: "bx1_destroy", bx1.}
proc bx1SaveConfig*(h: Bx1Handle, configPath: cstring) {.importc: "bx1_save_config", bx1.}
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

proc bx1IsFloppyDiskAccessed*(h: Bx1Handle, drv: cint): cint
  {.importc: "bx1_is_floppy_disk_accessed", bx1.}
proc bx1IsTapeActive*(h: Bx1Handle): cint {.importc: "bx1_is_tape_active", bx1.}
proc bx1FloppyDiskIndicatorColor*(h: Bx1Handle, drv: cint): cint
  {.importc: "bx1_floppy_disk_indicator_color", bx1.}
proc bx1IsFloppyDiskInserted*(h: Bx1Handle, drv: cint): cint
  {.importc: "bx1_is_floppy_disk_inserted", bx1.}
proc bx1IsTapeInserted*(h: Bx1Handle): cint {.importc: "bx1_is_tape_inserted", bx1.}
proc bx1GetTapeMessage*(h: Bx1Handle): cstring {.importc: "bx1_get_tape_message", bx1.}

proc bx1SetFloppyWriteProtected*(h: Bx1Handle, drv, protect: cint)
  {.importc: "bx1_set_floppy_write_protected", bx1.}
proc bx1GetFloppyWriteProtected*(h: Bx1Handle, drv: cint): cint
  {.importc: "bx1_get_floppy_write_protected", bx1.}
proc bx1SetCorrectDiskTiming*(h: Bx1Handle, drv, enabled: cint)
  {.importc: "bx1_set_correct_disk_timing", bx1.}
proc bx1GetCorrectDiskTiming*(h: Bx1Handle, drv: cint): cint
  {.importc: "bx1_get_correct_disk_timing", bx1.}
proc bx1SetIgnoreDiskCrc*(h: Bx1Handle, drv, enabled: cint)
  {.importc: "bx1_set_ignore_disk_crc", bx1.}
proc bx1GetIgnoreDiskCrc*(h: Bx1Handle, drv: cint): cint
  {.importc: "bx1_get_ignore_disk_crc", bx1.}
proc bx1CreateBlankFloppyDisk*(h: Bx1Handle, path: cstring, mediaType: cint): cint
  {.importc: "bx1_create_blank_floppy_disk", bx1.}

proc bx1TapePushPlay*(h: Bx1Handle) {.importc: "bx1_tape_push_play", bx1.}
proc bx1TapePushStop*(h: Bx1Handle) {.importc: "bx1_tape_push_stop", bx1.}
proc bx1TapePushFastForward*(h: Bx1Handle) {.importc: "bx1_tape_push_fast_forward", bx1.}
proc bx1TapePushFastRewind*(h: Bx1Handle) {.importc: "bx1_tape_push_fast_rewind", bx1.}
proc bx1TapePushApssForward*(h: Bx1Handle) {.importc: "bx1_tape_push_apss_forward", bx1.}
proc bx1TapePushApssRewind*(h: Bx1Handle) {.importc: "bx1_tape_push_apss_rewind", bx1.}
proc bx1SetWaveShaper*(h: Bx1Handle, enabled: cint) {.importc: "bx1_set_wave_shaper", bx1.}
proc bx1GetWaveShaper*(h: Bx1Handle): cint {.importc: "bx1_get_wave_shaper", bx1.}

proc bx1SaveState*(h: Bx1Handle, path: cstring): cint {.importc: "bx1_save_state", bx1.}
proc bx1LoadState*(h: Bx1Handle, path: cstring): cint {.importc: "bx1_load_state", bx1.}
proc bx1GetStateFilePath*(h: Bx1Handle, num: cint): cstring
  {.importc: "bx1_get_state_file_path", bx1.}

proc bx1SetCpuPower*(h: Bx1Handle, power: cint) {.importc: "bx1_set_cpu_power", bx1.}
proc bx1GetCpuPower*(h: Bx1Handle): cint {.importc: "bx1_get_cpu_power", bx1.}
proc bx1SetFullSpeed*(h: Bx1Handle, enabled: cint) {.importc: "bx1_set_full_speed", bx1.}
proc bx1GetFullSpeed*(h: Bx1Handle): cint {.importc: "bx1_get_full_speed", bx1.}
proc bx1SetDriveVmInOpecode*(h: Bx1Handle, enabled: cint)
  {.importc: "bx1_set_drive_vm_in_opecode", bx1.}
proc bx1GetDriveVmInOpecode*(h: Bx1Handle): cint
  {.importc: "bx1_get_drive_vm_in_opecode", bx1.}

proc bx1StartAutoKey*(h: Bx1Handle, text: cstring) {.importc: "bx1_start_auto_key", bx1.}
proc bx1StopAutoKey*(h: Bx1Handle) {.importc: "bx1_stop_auto_key", bx1.}
proc bx1IsAutoKeyRunning*(h: Bx1Handle): cint {.importc: "bx1_is_auto_key_running", bx1.}
proc bx1SetRomajiToKana*(h: Bx1Handle, enabled: cint)
  {.importc: "bx1_set_romaji_to_kana", bx1.}
proc bx1GetRomajiToKana*(h: Bx1Handle): cint {.importc: "bx1_get_romaji_to_kana", bx1.}

proc bx1SetMonitorType*(h: Bx1Handle, kind: cint) {.importc: "bx1_set_monitor_type", bx1.}
proc bx1GetMonitorType*(h: Bx1Handle): cint {.importc: "bx1_get_monitor_type", bx1.}
proc bx1SetSoundType*(h: Bx1Handle, kind: cint) {.importc: "bx1_set_sound_type", bx1.}
proc bx1GetSoundType*(h: Bx1Handle): cint {.importc: "bx1_get_sound_type", bx1.}
proc bx1SetVolume*(h: Bx1Handle, device, decibelL, decibelR: cint)
  {.importc: "bx1_set_volume", bx1.}
proc bx1SetScanLine*(h: Bx1Handle, enabled: cint) {.importc: "bx1_set_scan_line", bx1.}
proc bx1GetScanLine*(h: Bx1Handle): cint {.importc: "bx1_get_scan_line", bx1.}
proc bx1SetDriveType*(h: Bx1Handle, kind: cint) {.importc: "bx1_set_drive_type", bx1.}
proc bx1GetDriveType*(h: Bx1Handle): cint {.importc: "bx1_get_drive_type", bx1.}
proc bx1SetKeyboardType*(h: Bx1Handle, kind: cint) {.importc: "bx1_set_keyboard_type", bx1.}
proc bx1GetKeyboardType*(h: Bx1Handle): cint {.importc: "bx1_get_keyboard_type", bx1.}
proc bx1SetSoundNoiseFdd*(h: Bx1Handle, enabled: cint)
  {.importc: "bx1_set_sound_noise_fdd", bx1.}
proc bx1GetSoundNoiseFdd*(h: Bx1Handle): cint {.importc: "bx1_get_sound_noise_fdd", bx1.}
proc bx1SetSoundNoiseCmt*(h: Bx1Handle, enabled: cint)
  {.importc: "bx1_set_sound_noise_cmt", bx1.}
proc bx1GetSoundNoiseCmt*(h: Bx1Handle): cint {.importc: "bx1_get_sound_noise_cmt", bx1.}
proc bx1SetSoundTapeSignal*(h: Bx1Handle, enabled: cint)
  {.importc: "bx1_set_sound_tape_signal", bx1.}
proc bx1GetSoundTapeSignal*(h: Bx1Handle): cint
  {.importc: "bx1_get_sound_tape_signal", bx1.}
proc bx1SetSoundTapeVoice*(h: Bx1Handle, enabled: cint)
  {.importc: "bx1_set_sound_tape_voice", bx1.}
proc bx1GetSoundTapeVoice*(h: Bx1Handle): cint {.importc: "bx1_get_sound_tape_voice", bx1.}

proc bx1GetSoundVolumeCount*(): cint {.importc: "bx1_get_sound_volume_count", bx1.}
proc bx1GetSoundDeviceCaption*(index: cint): cstring
  {.importc: "bx1_get_sound_device_caption", bx1.}
proc bx1GetVolumeL*(h: Bx1Handle, device: cint): cint {.importc: "bx1_get_volume_l", bx1.}
proc bx1GetVolumeR*(h: Bx1Handle, device: cint): cint {.importc: "bx1_get_volume_r", bx1.}
