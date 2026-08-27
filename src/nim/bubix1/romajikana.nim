## Turning Romaji to Kana on and off.
##
## Not a one-line setter around `bx1SetRomajiToKana`. What the conversion
## produces is a sequence of *ordinary* digit and letter keys - "ア" is the
## "1" key on the X1's 50-on keyboard - so it only becomes kana while the
## guest's own kana lock is engaged. Switching the option on without
## engaging that lock leaves the guest receiving "1" where "ア" was typed,
## which is the feature looking broken rather than absent.
##
## The core has markers for this (`EMU::set_auto_key_char` codes 1 and 0,
## documented at `bx1_key_char` in `src/bridge/bubix1_api.h`), and it sends
## them - but the key it presses for "kana" is VK code `0xf2`, and **no X1
## device watches that code**. The sub CPU toggles its kana lock on `0x15`
## (VK_KANA - `PSUB::key_down`, `src/core/vm/x1/psub.cpp`), which is also
## what a press of the host's own かな key arrives as (`keymap.nim`). So
## the lock is pressed here, as a keystroke. The start marker is still
## sent, for the other thing it does: clearing the half-typed romaji the
## core accumulates between characters.
##
## The かな keystroke has to go out while the option is off, and while the
## auto key is idle: `EMU::key_down` forwards ordinary keys in neither
## case, and `0x15` is not in the small window it keeps open for the
## cursor and function keys.
##
## That is also why switching *off* does not send the end marker (code 0,
## which would settle a half-typed trailing "n" as ン): sending it starts
## the auto key, and the かな keystroke that has to follow would then be
## dropped, leaving the guest locked into kana with no way back except the
## user's own かな key. A trailing "n" abandoned mid-syllable is the
## cheaper loss, and the accumulator it sits in is cleared by the start
## marker whenever the option comes back on.
##
## An auto key already in flight - a long paste - would swallow the かな
## keystroke for the same reason, so switching *on* stops it first. That
## costs the rest of the paste, which is the lesser harm: the alternative
## is the option going on with no lock behind it, which is precisely the
## broken-looking state this module exists to prevent. Switching off does
## not stop it - there the dropped keystroke only leaves a lock engaged,
## which the user's own かな key can still undo.
##
## The lock is only released again if this module is the one that engaged
## it. A user who pressed かな themselves and then used the menu keeps
## the lock they set.

import core

const
  startMarker = 1.cint
    ## The "start" code `EMU::set_auto_key_char` treats as a marker rather
    ## than as a character. Not reachable as typed text. Its counterpart,
    ## the "end" marker 0, is deliberately not sent - see above.
  vkKana = 0x15.cint
    ## The かな key as the X1's sub CPU sees it. Not 0xf2, which is the
    ## code the core's own auto key presses for the same intent and which
    ## reaches no device on this machine.

var lockEngagedByUs = false
  ## Whether the kana lock the guest holds is one switching on put there.
  ## Host state, not guest state: it says what this module owes the user
  ## when the option goes off again, and nothing else reads it.

proc toggleKanaLock(h: Bx1Handle) =
  bx1KeyDown(h, vkKana, 0)
  bx1KeyUp(h, vkKana)

proc setRomajiToKana*(h: Bx1Handle, enabled: bool) =
  ## Switches the conversion on or off, taking the guest's kana lock with
  ## it: engaged while it is on, released once it is off - the same intent
  ## the core's own markers carry, by the one mechanism this machine
  ## actually responds to.
  ##
  ## Also the way to react to the core turning the option off by itself,
  ## which a reset and an NMI both do: called with `false` afterwards, it
  ## releases the lock an NMI leaves behind (a full reset clears that
  ## itself). `bx1SetRomajiToKana` is idempotent, so calling this when the
  ## flag is already down is safe.
  if enabled:
    # EMU::key_down forwards ordinary keys only while the auto key is
    # idle, and the かな press below is an ordinary key.
    if bx1IsAutoKeyRunning(h) != 0:
      bx1StopAutoKey(h)
    lockEngagedByUs = bx1GetKanaLocked(h) == 0
    if lockEngagedByUs:
      toggleKanaLock(h)
    bx1SetRomajiToKana(h, 1)
    bx1KeyChar(h, startMarker)
  else:
    bx1SetRomajiToKana(h, 0)
    # A reset clears the guest's lock on its own (PSUB::reset); an NMI does
    # not (VM::special_reset only pulses the CPU's NMI line), so the state
    # is re-read rather than assumed.
    if lockEngagedByUs and bx1GetKanaLocked(h) != 0:
      toggleKanaLock(h)
    lockEngagedByUs = false
