## Host > Rec Sound / Stop / Capture Screen.
##
## The original hands both jobs to its OSD (`EMU::start_record_sound`,
## `EMU::capture_screen`), which on Win32 taps DirectSound and the D2D
## back buffer. This port's OSD has neither - those methods are empty
## (src/core/sdl/osd_sound.cpp, osd_screen.cpp) and the core is not to be
## modified - so both are done here instead, from data the host already
## holds:
##
## * the recording is written from the very buffer the SDL audio callback
##   hands to the sound device, so what lands in the file is exactly what
##   was played, and
## * the screenshot is written from the same framebuffer the renderer
##   uploads, so it is the guest's own 640x400 picture with no status bar,
##   scaling or filtering applied.
##
## Threading: `feedSound` runs on SDL's audio thread while everything else
## runs on the main thread. The caller must hold the audio device lock
## (`SDL_LockAudioDevice`) across `startSoundRecording` / `stopSoundRecording`
## so the file cannot be closed out from under a write in progress.

import std/[os, times]
import deflate
import paths

type
  SoundRecorder = object
    file: File
    open: bool
    dataBytes: int

var recorder: SoundRecorder

const
  Channels = 2
  BytesPerSample = 2
  BytesPerFrame = Channels * BytesPerSample

proc timestamp(): string =
  # The underscore is quoted because times' format DSL treats bare letters
  # and punctuation it knows as pattern characters.
  now().format("yyyy-MM-dd'_'HHmmss")

proc putLe32(buf: var array[44, byte], pos: int, value: uint32) =
  buf[pos] = byte(value)
  buf[pos + 1] = byte(value shr 8)
  buf[pos + 2] = byte(value shr 16)
  buf[pos + 3] = byte(value shr 24)

proc putLe16(buf: var array[44, byte], pos: int, value: uint16) =
  buf[pos] = byte(value)
  buf[pos + 1] = byte(value shr 8)

proc putTag(buf: var array[44, byte], pos: int, tag: string) =
  for i in 0 .. 3:
    buf[pos + i] = tag[i].byte

proc wavHeader(rate, dataBytes: int): array[44, byte] =
  ## Canonical 44-byte RIFF/WAVE header for 16-bit stereo PCM. Written once
  ## with a zero length and rewritten on stop, when the length is known.
  let byteRate = uint32(rate * BytesPerFrame)
  putTag(result, 0, "RIFF")
  putLe32(result, 4, uint32(36 + dataBytes))
  putTag(result, 8, "WAVE")
  putTag(result, 12, "fmt ")
  putLe32(result, 16, 16)                    # fmt chunk size
  putLe16(result, 20, 1)                     # PCM, uncompressed
  putLe16(result, 22, uint16(Channels))
  putLe32(result, 24, uint32(rate))
  putLe32(result, 28, byteRate)
  putLe16(result, 32, uint16(BytesPerFrame)) # block align
  putLe16(result, 34, uint16(BytesPerSample * 8))
  putTag(result, 36, "data")
  putLe32(result, 40, uint32(dataBytes))

proc isSoundRecording*(): bool =
  recorder.open

proc startSoundRecording*(rate: int): string =
  ## Begins a new recording and returns the file it writes to, or "" if the
  ## file could not be created (a full or unwritable Music folder - the one
  ## failure a user can actually hit). Recording while already recording is
  ## a no-op that returns "".
  if recorder.open:
    return ""
  let dir = paths.recordingsDir()
  try:
    createDir(dir)
  except OSError:
    return ""
  let path = dir / (timestamp() & ".wav")
  var f: File
  if not f.open(path, fmWrite):
    return ""
  var header = wavHeader(rate, 0)
  if f.writeBuffer(addr header[0], header.len) != header.len:
    f.close()
    return ""
  recorder.file = f
  recorder.dataBytes = 0
  recorder.open = true
  path

proc feedSound*(samples: pointer, frames: int) =
  ## Appends `frames` interleaved stereo int16 frames. Called from SDL's
  ## audio thread: no allocation, no exceptions, and a short write simply
  ## stops the recording rather than trying to recover.
  if not recorder.open or frames <= 0:
    return
  let want = frames * BytesPerFrame
  if recorder.file.writeBuffer(samples, want) != want:
    recorder.file.close()
    recorder.open = false
    return
  recorder.dataBytes += want

proc stopSoundRecording*(rate: int) =
  ## Rewrites the two length fields the header could not know up front,
  ## then closes the file. A recorder that already died on a write error
  ## is simply already closed.
  if not recorder.open:
    return
  var header = wavHeader(rate, recorder.dataBytes)
  try:
    recorder.file.setFilePos(0)
    discard recorder.file.writeBuffer(addr header[0], header.len)
  except IOError, OSError:
    discard
  recorder.file.close()
  recorder.open = false

proc saveScreenshot*(framebuffer: ptr UncheckedArray[uint32],
                     width, height: int): string =
  ## Writes one PNG of the guest's screen and returns its path, or "" if it
  ## could not be written. `framebuffer` is the core's ARGB8888 buffer,
  ## top-down, with `width` pixels per row.
  if framebuffer == nil or width <= 0 or height <= 0:
    return ""
  var rgb = newSeq[byte](width * height * 3)
  var dst = 0
  for i in 0 ..< width * height:
    # Read as a 32-bit word rather than as bytes, so the channel order does
    # not depend on the host's endianness. Alpha is discarded: the core
    # leaves it at 0 (DevelopmentPlan 1.4), and a fully transparent PNG is
    # not what anyone means by a screenshot.
    let px = framebuffer[i]
    rgb[dst] = byte(px shr 16)
    rgb[dst + 1] = byte(px shr 8)
    rgb[dst + 2] = byte(px)
    dst += 3
  let dir = paths.screenshotsDir()
  let path = dir / (timestamp() & ".png")
  try:
    createDir(dir)
    writeFile(path, encodePng(width, height, rgb))
  except OSError, IOError:
    return ""
  path
