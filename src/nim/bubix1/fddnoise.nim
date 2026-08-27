## Synthesized floppy drive noise for the core's own noise players.
##
## The core plays drive sounds from WAV files it loads while the FDC is
## being constructed (`MB8877::initialize`, which asks for `FDDSEEK.WAV`,
## `HEADDOWN.WAV` and `HEADUP.WAV`) and mixes them through its own sound
## pipeline. Feeding it files therefore costs nothing to wire up: the
## `Device > Sound > Play FDD Noise` toggle and the `Noise (FDD)` slider in
## `Host > Volume` already drive those players, and a save state carries
## their playback position like any other device's.
##
## The original Windows distribution ships the WAVs as data files. This
## project has none to ship, so it generates them - the same approach
## Bubilator88 takes for its drive sounds, except that the synthesis writes
## into the file the core already knows how to read instead of standing up
## a second audio path beside it.
##
## Files land in the core's single base directory (`paths.romsDir()`, what
## `create_local_path` resolves against - see docs/dev/VendorPatches.md).
## An existing file is never overwritten, so anyone who prefers real
## recordings can drop their own in; deleting them brings the generated
## ones back on the next launch.

import std/[math, os]
import ./applog

const
  SampleRate = 22050
    ## `NOISE::play` registers a core event per *sample* (noise.cpp), so the
    ## rate is a per-click cost in the main loop. A mechanical click holds
    ## nothing above a few kHz, so half of CD rate is free.
  PeakAmplitude = 8000
    ## About -12 dBFS. The players start at 0 dB with the volume slider
    ## centred, and `NOISE::mix` adds its sample to every frame of the
    ## buffer, so a full-scale click would sit on top of the music far too
    ## loudly. Leaving headroom lets the slider go up as well as down.

type
  Rng = object
    ## Deterministic noise source, so every install generates byte-identical
    ## files rather than a different click per machine.
    state: uint32

proc bipolar(r: var Rng): float =
  ## Uniform noise in -1.0 .. 1.0. Plain LCG: the spectrum only has to be
  ## broad, not statistically sound.
  r.state = r.state * 1103515245'u32 + 12345'u32
  float((r.state shr 16) and 0xffff'u32) / 32768.0 - 1.0

proc frames(durationMs: float): int =
  int(SampleRate.float * durationMs / 1000.0)

proc click(durationMs, decayFraction, thumpHz, thumpLevel, noiseLevel: float,
           seed: uint32): seq[float] =
  ## One mechanical impulse: a low sine "thump" for the mass that moved,
  ## plus a noise transient for the contact, both under a decaying
  ## envelope. `decayFraction` is the exponential time constant as a
  ## fraction of the total duration - smaller is sharper.
  let count = frames(durationMs)
  result = newSeq[float](count)
  var rng = Rng(state: seed)
  let tau = durationMs / 1000.0 * decayFraction
  # The exponential is still a few percent of full scale when the buffer
  # runs out, and playback simply stops there (noise.cpp drops the sample
  # to zero), which puts a click of its own at the end of every click. A
  # short linear ramp over the tail lands it on silence instead.
  let fade = max(1, frames(1.0))
  for i in 0 ..< count:
    let t = i.float / SampleRate.float
    let envelope = exp(-t / tau)
    let thump = sin(2.0 * PI * thumpHz * t) * thumpLevel
    # The noise decays faster than the tone (squared envelope): contact
    # noise dies away while the body of the drive is still ringing.
    var sample = envelope * thump + envelope * envelope * rng.bipolar() * noiseLevel
    let remaining = count - i
    if remaining <= fade:
      sample *= (remaining - 1).float / fade.float
    result[i] = sample

proc toPcm(samples: seq[float], gain: float): seq[int16] =
  result = newSeq[int16](samples.len)
  for i, s in samples:
    result[i] = int16(clamp(s * gain, -32768.0, 32767.0))

proc putU16(s: var string, value: uint16) =
  s.add char(value and 0xff)
  s.add char((value shr 8) and 0xff)

proc putU32(s: var string, value: uint32) =
  s.add char(value and 0xff)
  s.add char((value shr 8) and 0xff)
  s.add char((value shr 16) and 0xff)
  s.add char((value shr 24) and 0xff)

proc encodeWav(pcm: seq[int16]): string =
  ## Canonical 44-byte mono 16-bit WAV. The core's parser reads a fixed
  ## header, seeks past `fmt` chunk size minus 16, then walks chunks for
  ## `data` (noise.cpp), so the `fmt ` chunk must be exactly 16 bytes and
  ## carry no extension. Mono because `NOISE::get_sample` reads the left
  ## buffer for both channels - a right channel would be discarded.
  let dataSize = uint32(pcm.len * 2)
  result = newStringOfCap(44 + pcm.len * 2)
  result.add "RIFF"
  result.putU32 36'u32 + dataSize
  result.add "WAVE"
  result.add "fmt "
  result.putU32 16'u32
  result.putU16 1'u16                       # PCM
  result.putU16 1'u16                       # channels
  result.putU32 SampleRate.uint32
  result.putU32 uint32(SampleRate * 2)      # bytes per second
  result.putU16 2'u16                       # block align
  result.putU16 16'u16                      # bits per sample
  result.add "data"
  result.putU32 dataSize
  for sample in pcm:
    result.putU16 cast[uint16](sample)

proc writeWav(path: string, pcm: seq[int16]) =
  ## Written under a temporary name and moved into place: a half-written
  ## file would be skipped as "already there" forever after.
  let temp = path & ".tmp"
  writeFile(temp, encodeWav(pcm))
  moveFile(temp, path)

proc ensureFiles*(dir: string) =
  ## Generates any drive-noise WAV the core would look for and not find.
  ## Call before `bx1_create`, since the FDC loads them as it is built.
  ##
  ## Failures are reported and otherwise ignored: missing files only mean a
  ## silent drive, which is never a reason to keep the emulator from
  ## starting.
  # Relative levels are set here, once, by giving every sound the same
  # gain: the seek click is the loudest thing a drive does, so it defines
  # full scale and the head movements sit below it on their own merits.
  let sounds = {
    # The head stepper, once per track. Lowest and longest of the three.
    "FDDSEEK.WAV": click(12.0, 0.40, 50.0, 0.50, 0.15, 12345'u32),
    # Head load: the pad coming down onto the medium. Softer, and duller
    # than the step because nothing is being driven, only released.
    "HEADDOWN.WAV": click(10.0, 0.35, 40.0, 0.32, 0.10, 24680'u32),
    # Head unload: the same mechanism retracting. Shortest and quietest.
    "HEADUP.WAV": click(7.0, 0.30, 60.0, 0.22, 0.08, 13579'u32),
  }
  var peak = 0.0
  for (_, samples) in sounds:
    for s in samples:
      peak = max(peak, abs(s))
  if peak <= 0.0:
    return
  let gain = PeakAmplitude.float / peak

  for (name, samples) in sounds:
    var present = fileExists(dir / name)
    if name == "FDDSEEK.WAV":
      # The core tries three names in turn for the seek sound
      # (mb8877.cpp), and the one written here would shadow a user's file
      # under either of the others.
      present = present or fileExists(dir / "FDDSEEK1.WAV") or
                fileExists(dir / "SEEK.WAV")
    if present:
      continue
    try:
      writeWav(dir / name, toPcm(samples, gain))
    except CatchableError as e:
      applog.note "could not generate " & name & ": " & e.msg
