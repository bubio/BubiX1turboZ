## Headless tests for the Romaji to Kana input path (Control > Romaji to
## Kana in the original app, `config.romaji_to_kana` in the core).
##
## The machine runs with no BIOS ROMs and no window: what a keystroke turns
## into is observed through the bridge's key capture hook
## (`bx1_key_capture_start` / `bx1_key_capture_read`), which logs every key
## event the VM is handed - both the ones a host injects and the ones the
## auto key synthesizes while converting romaji. Nothing here needs a guest
## that can display hankaku kana, which is the point: the conversion is
## asserted as key presses, not as glyphs.
##
## The expectations are written from the X1 turbo's own keyboard legends,
## not copied from the core's tables, so that a table changing under a
## re-vendor is a test failure rather than a silent rewrite of what this
## suite believes. Two layouts matter, selected by `config.keyboard_type`
## (the keyboard's physical mode switch):
##
## * mode B (`1`, the core's default): the 50-on layout. `1`-`5` are
##   アイウエオ, `Q`-`T` are カキクケコ, `Z`-`B` are タチツテト, `N` is ヤ.
## * mode A (`0`): the JIS kana layout, the one printed on an ordinary
##   Japanese keyboard - `3` is あ, `T` is か.
##
## What this cannot catch, in the order it has actually bitten:
##
## 1. That an engaged kana lock yields a *kana character*. Everything here
##    stops at the VK codes handed to the VM and at the lock flag itself,
##    both upstream of the sub CPU's own decode (`PSUB::get_key`, which
##    reads `keycode_kb[]` for mode B). Twice now a defect has hidden in
##    exactly that space - first "0xf2 was sent" (it was, and no device
##    watched it), then "the lock is engaged" (it is, and that is one
##    variable away from the keystroke that set it). This one is covered
##    by hand instead: the conversion was confirmed in a title that takes
##    typed input, and reading the guest's text VRAM to automate it was
##    considered and dropped as not worth its cost.
## 2. An SDL `TextInput` event reaching `bx1_key_char` at all - if SDL
##    stops delivering those, every test here passes while the keyboard is
##    dead on a real machine.
## 3. The menu item's own closure: `romajikana.setRomajiToKana` is under
##    test below, the wiring from the checkmark to it is not.

import std/[os, unittest]
import bubix1/core
import bubix1/romajikana

const
  # Key capture entries are a VK code plus this bit on a release.
  release = bx1KeyCaptureRelease

  # VK codes that are named rather than derived from a kana legend.
  vkReturn = 0x0d
  vkShift = 0x10   ## generic; the OSD synthesizes it from the L/R pair
  vkA = 0x41
  vkF1 = 0x70      ## inside the function-key window EMU::key_down forwards
  vkLShift = 0xa0
  vkKanaLock = 0x15  ## the かな key as the X1's sub CPU sees it
  vkAutoKeyKana = 0xf2
    ## what the core's auto key presses when it means "kana". No X1 device
    ## watches this code - see romajikana.nim.

  keyboardModeA = 0
  keyboardModeB = 1

var h: Bx1Handle

proc tap(code: int): seq[uint16] =
  ## One press and release of `code`, the shape a single auto key
  ## character leaves in the capture log.
  @[uint16(code), uint16(code) or release]

proc shiftTap(code: int): seq[uint16] =
  ## The same for a shifted character. The auto key presses VK_LSHIFT; the
  ## OSD adds the generic VK_SHIFT the X1 keyboard matrix is indexed by,
  ## and drops it again when the last physical shift is released.
  @[uint16(vkLShift), uint16(vkShift), uint16(code),
    uint16(code) or release, uint16(vkLShift) or release,
    uint16(vkShift) or release]

proc runFrames(count: int) =
  for _ in 0 ..< count:
    discard bx1RunFrame(h)

proc settle(maxFrames = 1200) =
  ## Runs until the auto key has emptied its buffer. It emits one phase per
  ## frame, so a several-kana conversion needs a few dozen; the cap is only
  ## there so a defect cannot hang the suite.
  var frames = 0
  while bx1IsAutoKeyRunning(h) != 0 and frames < maxFrames:
    discard bx1RunFrame(h)
    inc frames
  # doAssert, not unittest's check: this runs outside a test's own scope,
  # where check has no status to report into and would let the case go on
  # to compare a half-finished capture.
  doAssert frames < maxFrames,
    "the auto key did not drain within " & $maxFrames & " frames"
  # A few more, so a release issued on the last phase is logged too.
  runFrames(4)

proc captured(): seq[uint16] =
  var buf: array[512, uint16]
  var dropped: cint = 0
  let count = bx1KeyCaptureRead(h, addr buf[0], buf.len.cint, addr dropped)
  # Never compare a truncated prefix: a case that overruns the log has to
  # fail outright.
  doAssert dropped == 0, "key capture overflowed, " & $dropped & " event(s) lost"
  for i in 0 ..< count:
    result.add buf[i]

proc beginCase(keyboardType: int, kanaLock = true, romajiOn = true) =
  ## Puts the machine in the state every case assumes, and starts a fresh
  ## capture.
  ##
  ## The flush comes first and matters: `EMU::set_auto_key_char` keeps the
  ## romaji typed so far in a function-static buffer that nothing clears -
  ## not a reset, not destroying the handle - so a case ending mid-syllable
  ## ("kan") would otherwise shift its leftovers into the next one. Code 0
  ## is the core's own "end" marker, which flushes and clears it, and it
  ## only reaches the core while the option is on.
  bx1SetRomajiToKana(h, 1)
  bx1KeyChar(h, 0)
  settle()
  # A reset clears the guest's kana lock (PSUB::reset) and turns the option
  # off again (EMU::reset), so both are set explicitly afterwards.
  bx1Reset(h)
  bx1SetKeyboardType(h, keyboardType.cint)
  if kanaLock:
    # The guest's kana lock, without which the keys the conversion sends
    # arrive as digits and letters. Pressed before the option goes on,
    # because EMU::key_down stops forwarding ordinary keys once it is, and
    # before the capture starts, so it stays out of the expectations.
    bx1KeyDown(h, vkKanaLock.cint, 0)
    bx1KeyUp(h, vkKanaLock.cint)
    settle()
  if romajiOn:
    bx1SetRomajiToKana(h, 1)
    settle()
  bx1KeyCaptureStart(h)

proc typeText(text: string) =
  for ch in text:
    bx1KeyChar(h, ch.ord.cint)
  settle()

suite "romaji to kana":
  setup:
    # A directory with no ROMs in it, deliberately: with no SUB/KBD ROM the
    # VM runs its pseudo sub CPU (VM::pseudo_sub_cpu), which is the path
    # that owns the kana lock these tests depend on.
    let romless = getAppDir() / "romless"
    createDir(romless)
    for _ in walkDir(romless):
      doAssert false, romless & " is not empty; a SUB/KBD ROM there would " &
        "move the kana lock to the KEYBOARD device and invalidate these tests"
    h = bx1Create(romless.cstring, "".cstring)
    require h != nil

  teardown:
    bx1Destroy(h)

  test "vowels are the 50-on layout's number row":
    beginCase(keyboardModeB)
    typeText("aiueo")
    # ア イ ウ エ オ = the "1" to "5" keys.
    check captured() == tap(0x31) & tap(0x32) & tap(0x33) & tap(0x34) & tap(0x35)

  test "a consonant plus a vowel is one key":
    beginCase(keyboardModeB)
    typeText("ka")
    check captured() == tap(0x51) # カ = the "Q" key

  test "a contracted syllable is two keys, the second shifted":
    beginCase(keyboardModeB)
    typeText("kya")
    # キ = "W"; ャ = shift + "N" (ヤ), the small kana being the shifted
    # legend of its full-size one.
    check captured() == tap(0x57) & shiftTap(0x4e)

  test "a doubled consonant becomes a small tsu":
    beginCase(keyboardModeB)
    typeText("tta")
    # ッ = shift + "C" (ツ), then タ = "Z".
    check captured() == shiftTap(0x43) & tap(0x5a)

  test "nn is a single n kana":
    beginCase(keyboardModeB)
    typeText("nn")
    check captured() == tap(0xe2) # ン = the key right of the "M" row

  test "a trailing n is flushed by the key that follows it":
    beginCase(keyboardModeB)
    typeText("kan\r")
    # カ, then the pending "n" resolved to ン because Return cannot start a
    # syllable, then Return itself.
    check captured() == tap(0x51) & tap(0xe2) & tap(vkReturn)

  test "a syllable left unfinished does not leak into the next case":
    # The regression test for the function-static accumulator beginCase
    # flushes: "kan" ends with a pending "n".
    beginCase(keyboardModeB)
    typeText("kan")
    check captured() == tap(0x51)
    # Without the flush the pending "n" would combine with what follows and
    # give ナ ("N") instead of ア. kanaLock is off here so that the start
    # marker, which clears the accumulator as a side effect of its own, is
    # not the thing being relied on.
    beginCase(keyboardModeB, kanaLock = false)
    typeText("a")
    check captured() == tap(0x31)

  test "the core's own kana key press reaches no X1 device":
    # The start marker presses 0xf2 when the lock is off. The VM is handed
    # it - so it is captured - but PSUB::key_down only toggles the lock on
    # 0x15, and nothing else looks at 0xf2 either. This is the whole reason
    # romajikana.nim presses the lock as a keystroke of its own.
    beginCase(keyboardModeB, kanaLock = false)
    check bx1GetKanaLocked(h) == 0
    bx1KeyChar(h, 1)
    settle()
    check captured() == tap(vkAutoKeyKana)
    check bx1GetKanaLocked(h) == 0

  test "the kana key the sub CPU watches does toggle the lock":
    beginCase(keyboardModeB, kanaLock = false)
    check bx1GetKanaLocked(h) == 0
    # Sent with the option off, the way romajikana.nim orders it: with it
    # on, EMU::key_down would drop this before the VM ever saw it.
    bx1SetRomajiToKana(h, 0)
    bx1KeyDown(h, vkKanaLock.cint, 0)
    bx1KeyUp(h, vkKanaLock.cint)
    settle()
    check bx1GetKanaLocked(h) == 1

  test "the end marker flushes a pending n":
    beginCase(keyboardModeB)
    typeText("kan")
    check captured() == tap(0x51)
    bx1KeyChar(h, 0)
    settle()
    # ン, then the core's own (inert) kana key press.
    check captured() == tap(0xe2) & tap(vkAutoKeyKana)

  test "the app's own toggle takes the guest's kana lock with it":
    # bubix1/romajikana is what the menu item calls, and this is what it
    # exists for: without the lock, everything the conversion sends lands
    # as digits and letters. The closest layer 1 gets to the application.
    beginCase(keyboardModeB, kanaLock = false, romajiOn = false)
    check bx1GetKanaLocked(h) == 0

    romajikana.setRomajiToKana(h, true)
    settle()
    check bx1GetRomajiToKana(h) == 1
    check bx1GetKanaLocked(h) == 1
    # Only the lock: the start marker's own kana press is skipped once the
    # guest is already locked (EMU::set_auto_key_char).
    check captured() == tap(vkKanaLock)

    typeText("kan")
    check captured() == tap(0x51) # カ, with the "n" still undecided

    romajikana.setRomajiToKana(h, false)
    settle()
    check bx1GetRomajiToKana(h) == 0
    check bx1GetKanaLocked(h) == 0
    # Only the lock being released. The pending "n" is *not* flushed: the
    # end marker that would settle it starts the auto key, and the かな
    # keystroke behind it would then be dropped by EMU::key_down, which is
    # the worse failure of the two - see romajikana.nim.
    check captured() == tap(vkKanaLock)

  test "switching on with a paste in flight still engages the lock":
    # EMU::key_down forwards ordinary keys only while the auto key is idle,
    # so the かな press would be swallowed mid-paste - leaving the option on
    # with no lock behind it, which is the failure this module exists to
    # prevent. setRomajiToKana stops the paste rather than lose the lock.
    beginCase(keyboardModeB, kanaLock = false, romajiOn = false)
    bx1StartAutoKey(h, "HELLO".cstring)
    discard bx1RunFrame(h)
    check bx1IsAutoKeyRunning(h) != 0

    romajikana.setRomajiToKana(h, true)
    settle()
    check bx1GetKanaLocked(h) == 1

  test "a kana lock the user set is not the app's to release":
    beginCase(keyboardModeB, kanaLock = false, romajiOn = false)
    # The user's own かな key, before the option is ever touched.
    bx1KeyDown(h, vkKanaLock.cint, 0)
    bx1KeyUp(h, vkKanaLock.cint)
    settle()
    check bx1GetKanaLocked(h) == 1

    romajikana.setRomajiToKana(h, true)
    settle()
    check bx1GetKanaLocked(h) == 1 # already locked; nothing to press

    romajikana.setRomajiToKana(h, false)
    settle()
    check bx1GetKanaLocked(h) == 1 # and nothing to release

  test "an NMI keeps the guest's kana lock while clearing the option":
    # The asymmetry the host's status poll has to clean up after:
    # EMU::special_reset clears config.romaji_to_kana, but VM::special_reset
    # only pulses the CPU's NMI line - PSUB is never reset, so its lock
    # survives. A full reset does clear it (PSUB::reset).
    beginCase(keyboardModeB, kanaLock = false, romajiOn = false)
    romajikana.setRomajiToKana(h, true)
    settle()
    check bx1GetKanaLocked(h) == 1

    bx1SpecialReset(h)
    settle()
    check bx1GetRomajiToKana(h) == 0
    check bx1GetKanaLocked(h) == 1

    # What bubix1turboz.nim's poll calls once it sees the flag gone.
    romajikana.setRomajiToKana(h, false)
    settle()
    check bx1GetKanaLocked(h) == 0

  test "mode A uses the JIS kana layout instead":
    beginCase(keyboardModeA)
    typeText("a")
    check captured() == tap(0x33) # あ = the "3" key on a JIS kana keyboard
    beginCase(keyboardModeA)
    typeText("ka")
    check captured() == tap(0x54) # か = the "T" key

  test "with the option off, characters are ignored and keys pass through":
    beginCase(keyboardModeB)
    bx1SetRomajiToKana(h, 0)
    bx1KeyChar(h, 'a'.ord.cint)
    runFrames(8)
    check captured().len == 0
    bx1KeyDown(h, vkA.cint, 0)
    bx1KeyUp(h, vkA.cint)
    runFrames(8)
    check captured() == tap(vkA)

  test "with the option on, ordinary keys stop reaching the guest":
    # EMU::key_down stops forwarding them and expects key_char to feed the
    # auto key instead, so a host that sends only key events makes the
    # keyboard dead rather than merely unconverted.
    beginCase(keyboardModeB)
    bx1KeyDown(h, vkA.cint, 0)
    bx1KeyUp(h, vkA.cint)
    runFrames(8)
    check captured().len == 0

  test "with the option on, function keys still reach the guest":
    # The window EMU::key_down keeps open for keys that produce no
    # character: the cursor block, the editing keys, and F1-F12.
    beginCase(keyboardModeB)
    bx1KeyDown(h, vkF1.cint, 0)
    bx1KeyUp(h, vkF1.cint)
    settle()
    check captured() == tap(vkF1)

  test "a reset turns the option off":
    # What the menu's own re-sync after a reset exists for: the core clears
    # the flag, and a UI that kept its checkmark would be lying.
    beginCase(keyboardModeB)
    check bx1GetRomajiToKana(h) == 1
    check bx1GetKanaLocked(h) == 1
    bx1Reset(h)
    check bx1GetRomajiToKana(h) == 0
    # Unlike an NMI, a full reset takes the guest's lock with it.
    check bx1GetKanaLocked(h) == 0
    bx1SpecialReset(h)
    check bx1GetRomajiToKana(h) == 0
