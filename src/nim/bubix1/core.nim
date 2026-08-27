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
  ## Rarely needed: every other proc here takes this lock for the length of
  ## its own call (the `vm_lock` guard in bubix1_api.cpp), so the two
  ## threads this app runs are never inside the core at the same time
  ## without anyone asking.
  ##
  ## Reach for it when a *pair* of calls has to be atomic, which is
  ## anything that reads through a pointer the core handed back: the lock
  ## is released when the call that returned the pointer does, and the
  ## emulation thread is free to rewrite what it points at from that
  ## instant. `bx1GetFramebuffer` and the three `cstring` getters below are
  ## the ones this applies to.
proc bx1Unlock*(h: Bx1Handle) {.importc: "bx1_unlock", bx1.}

proc bx1VmLockUsers*(): cint {.importc: "bx1_vm_lock_users", bx1.}
  ## How many threads hold the VM lock or are waiting for it. Read by the
  ## emulation thread between frames, where it holds nothing itself, so a
  ## non-zero answer means the application's thread wants the machine and
  ## this one should stand aside - the lock is not fair, and a loop that
  ## reacquires it without pause would starve the UI.

proc bx1GetFramebuffer*(h: Bx1Handle): ptr UncheckedArray[uint32]
  {.importc: "bx1_get_framebuffer", bx1.}
  ## Valid only while the VM lock is held; see `bx1Lock`.
proc bx1GetScreenWidth*(h: Bx1Handle): cint {.importc: "bx1_get_screen_width", bx1.}
proc bx1GetScreenHeight*(h: Bx1Handle): cint {.importc: "bx1_get_screen_height", bx1.}
proc bx1GetAspectHeight*(h: Bx1Handle): cint {.importc: "bx1_get_aspect_height", bx1.}

proc bx1SetWindowMode*(h: Bx1Handle, mode: cint) {.importc: "bx1_set_window_mode", bx1.}
proc bx1GetWindowMode*(h: Bx1Handle): cint {.importc: "bx1_get_window_mode", bx1.}
proc bx1SetWindowStretchType*(h: Bx1Handle, kind: cint)
  {.importc: "bx1_set_window_stretch_type", bx1.}
proc bx1GetWindowStretchType*(h: Bx1Handle): cint
  {.importc: "bx1_get_window_stretch_type", bx1.}
proc bx1SetFullscreenStretchType*(h: Bx1Handle, kind: cint)
  {.importc: "bx1_set_fullscreen_stretch_type", bx1.}
proc bx1GetFullscreenStretchType*(h: Bx1Handle): cint
  {.importc: "bx1_get_fullscreen_stretch_type", bx1.}

proc bx1GetActualSoundRate*(h: Bx1Handle): cint
  {.importc: "bx1_get_actual_sound_rate", bx1.}
proc bx1GetActualSoundLatency*(h: Bx1Handle): cdouble
  {.importc: "bx1_get_actual_sound_latency", bx1.}
proc bx1SetSoundStrictRendering*(h: Bx1Handle, enabled: cint)
  {.importc: "bx1_set_sound_strict_rendering", bx1.}
proc bx1GetSoundStrictRendering*(h: Bx1Handle): cint
  {.importc: "bx1_get_sound_strict_rendering", bx1.}
proc bx1PullAudio*(h: Bx1Handle, dst: ptr int16, frames: cint): cint
  {.importc: "bx1_pull_audio", bx1.}
proc bx1GetBufferedAudioFrames*(h: Bx1Handle): cint
  {.importc: "bx1_get_buffered_audio_frames", bx1.}
proc bx1MuteSound*(h: Bx1Handle) {.importc: "bx1_mute_sound", bx1.}

proc bx1KeyDown*(h: Bx1Handle, vkCode: cint, repeat: cint)
  {.importc: "bx1_key_down", bx1.}
proc bx1KeyUp*(h: Bx1Handle, vkCode: cint) {.importc: "bx1_key_up", bx1.}
proc bx1KeyChar*(h: Bx1Handle, code: cint) {.importc: "bx1_key_char", bx1.}
proc bx1GetCapsLocked*(h: Bx1Handle): cint {.importc: "bx1_get_caps_locked", bx1.}
proc bx1GetKanaLocked*(h: Bx1Handle): cint {.importc: "bx1_get_kana_locked", bx1.}
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
  ## Points into storage the core owns and rewrites on a disk change, so
  ## the conversion to a Nim string has to happen with the VM lock held -
  ## see the note above `bx1Lock`. Currently unreferenced.
proc bx1GetFloppyPath*(h: Bx1Handle, drv: cint): cstring
  {.importc: "bx1_get_floppy_path", bx1.}
  ## Same: copy it under the lock. Currently unreferenced (the disk menus
  ## are built from `bx1ScanD88Banks`, which fills a caller-owned array).
proc bx1GetFloppyBank*(h: Bx1Handle, drv: cint): cint
  {.importc: "bx1_get_floppy_bank", bx1.}

type
  Bx1D88Bank* {.importc: "bx1_d88_bank", header: "bubix1_api.h", bycopy.} = object
    ## One disk inside a D88-family image. `name` is raw header bytes in
    ## whatever encoding the image used, so it must be decoded host-side.
    name*: array[18, char]
    mediaType* {.importc: "media_type".}: cint
    writeProtected* {.importc: "write_protected".}: cint

proc bx1ScanD88Banks*(path: cstring, maxBanks: cint, outBanks: ptr Bx1D88Bank): cint
  {.importc: "bx1_scan_d88_banks", bx1.}

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
  ## Copy it under the lock; see `bx1Lock`. Currently unreferenced (no UI
  ## opens a tape).

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

proc bx1VmStateSave*(h: Bx1Handle, path: cstring): cint
  {.importc: "bx1_vm_state_save", bx1.}
proc bx1VmStateLoad*(h: Bx1Handle, path, rollbackPath: cstring): cint
  {.importc: "bx1_vm_state_load", bx1.}
proc bx1CoreStateId*(): uint32 {.importc: "bx1_core_state_id", bx1.}
proc bx1GetPrinterType*(h: Bx1Handle): cint {.importc: "bx1_get_printer_type", bx1.}
proc bx1GetSerialType*(h: Bx1Handle): cint {.importc: "bx1_get_serial_type", bx1.}
proc bx1GetSoundFrequency*(h: Bx1Handle): cint
  {.importc: "bx1_get_sound_frequency", bx1.}
proc bx1GetSoundLatency*(h: Bx1Handle): cint {.importc: "bx1_get_sound_latency", bx1.}
proc bx1SetSoundFrequency*(h: Bx1Handle, index: cint)
  {.importc: "bx1_set_sound_frequency", bx1.}
proc bx1SetSoundLatency*(h: Bx1Handle, index: cint)
  {.importc: "bx1_set_sound_latency", bx1.}

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
proc bx1GetVmSoundType*(h: Bx1Handle): cint {.importc: "bx1_get_vm_sound_type", bx1.}
proc bx1SetVolume*(h: Bx1Handle, device, decibelL, decibelR: cint)
  {.importc: "bx1_set_volume", bx1.}
proc bx1ApplyVolume*(h: Bx1Handle, device, decibelL, decibelR: cint)
  {.importc: "bx1_apply_volume", bx1.}
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

const bx1KeyCaptureRelease* = 0x100'u16
  ## Set on a captured entry that is a key release; the low byte is the VK
  ## code either way. Mirrors `BX1_KEY_CAPTURE_RELEASE`, which the bridge
  ## itself checks against the core's own spelling with a `static_assert`.

proc bx1KeyCaptureStart*(h: Bx1Handle) {.importc: "bx1_key_capture_start", bx1.}
proc bx1KeyCaptureRead*(h: Bx1Handle, dst: ptr uint16, maxEntries: cint,
                        dropped: ptr cint): cint
  {.importc: "bx1_key_capture_read", bx1.}
