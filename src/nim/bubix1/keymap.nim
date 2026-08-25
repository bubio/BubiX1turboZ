## Maps SDL2 scancodes (physical key position, layout independent) to the
## win32 virtual-key codes the emulation core expects (`src/core/compat/vkcodes.h`).
##
## The authoritative reference for *which* VK codes matter is the X1's own
## keyboard matrix (`src/core/vm/x1/keyboard.cpp`), not win32's `keycode_conv`
## table (that one remaps VK->VK for user customization and defaults to
## identity - it says nothing about scancode->VK). OEM_* codes are assigned
## by physical position to match the JIS legends printed in that matrix's
## comments (e.g. VK_OEM_7 = the key left of Return, "^" on JIS).
##
## Coverage beyond the X1 matrix (F6-F12, media keys, etc.) is included
## where cheap, for the debugger/future use, but is not verified against
## real hardware. JIS-specific IME keys (kana/henkan/muhenkan) are
## best-effort; confirm against real hardware in phase 8.

import sdl2

const scancodeToVk*: array[512, int32] = block:
  var t: array[512, int32]
  for i in 0 ..< 512:
    t[i] = 0
  # Letters / digits (ASCII values match VK for 'A'-'Z' / '0'-'9').
  t[SDL_SCANCODE_A.int] = 0x41
  t[SDL_SCANCODE_B.int] = 0x42
  t[SDL_SCANCODE_C.int] = 0x43
  t[SDL_SCANCODE_D.int] = 0x44
  t[SDL_SCANCODE_E.int] = 0x45
  t[SDL_SCANCODE_F.int] = 0x46
  t[SDL_SCANCODE_G.int] = 0x47
  t[SDL_SCANCODE_H.int] = 0x48
  t[SDL_SCANCODE_I.int] = 0x49
  t[SDL_SCANCODE_J.int] = 0x4a
  t[SDL_SCANCODE_K.int] = 0x4b
  t[SDL_SCANCODE_L.int] = 0x4c
  t[SDL_SCANCODE_M.int] = 0x4d
  t[SDL_SCANCODE_N.int] = 0x4e
  t[SDL_SCANCODE_O.int] = 0x4f
  t[SDL_SCANCODE_P.int] = 0x50
  t[SDL_SCANCODE_Q.int] = 0x51
  t[SDL_SCANCODE_R.int] = 0x52
  t[SDL_SCANCODE_S.int] = 0x53
  t[SDL_SCANCODE_T.int] = 0x54
  t[SDL_SCANCODE_U.int] = 0x55
  t[SDL_SCANCODE_V.int] = 0x56
  t[SDL_SCANCODE_W.int] = 0x57
  t[SDL_SCANCODE_X.int] = 0x58
  t[SDL_SCANCODE_Y.int] = 0x59
  t[SDL_SCANCODE_Z.int] = 0x5a
  t[SDL_SCANCODE_0.int] = 0x30
  t[SDL_SCANCODE_1.int] = 0x31
  t[SDL_SCANCODE_2.int] = 0x32
  t[SDL_SCANCODE_3.int] = 0x33
  t[SDL_SCANCODE_4.int] = 0x34
  t[SDL_SCANCODE_5.int] = 0x35
  t[SDL_SCANCODE_6.int] = 0x36
  t[SDL_SCANCODE_7.int] = 0x37
  t[SDL_SCANCODE_8.int] = 0x38
  t[SDL_SCANCODE_9.int] = 0x39

  # Control keys.
  t[SDL_SCANCODE_RETURN.int] = 0x0d      # VK_RETURN
  t[SDL_SCANCODE_ESCAPE.int] = 0x1b      # VK_ESCAPE
  t[SDL_SCANCODE_BACKSPACE.int] = 0x08   # VK_BACK
  t[SDL_SCANCODE_TAB.int] = 0x09         # VK_TAB
  t[SDL_SCANCODE_SPACE.int] = 0x20       # VK_SPACE
  t[SDL_SCANCODE_CAPSLOCK.int] = 0x14    # VK_CAPITAL

  # OEM punctuation, mapped by physical position (US-layout scancode slot)
  # to the VK_OEM_* the X1 matrix expects; the JIS legend is what actually
  # prints on the keycap the emulator's keyboard.cpp comments describe.
  t[SDL_SCANCODE_MINUS.int] = 0xbd          # VK_OEM_MINUS  '-'
  t[SDL_SCANCODE_EQUALS.int] = 0xbb         # VK_OEM_PLUS   '=' slot -> ';' row7 col2 on X1
  t[SDL_SCANCODE_LEFTBRACKET.int] = 0xdb    # VK_OEM_4      '['
  t[SDL_SCANCODE_RIGHTBRACKET.int] = 0xdd   # VK_OEM_6      ']'
  t[SDL_SCANCODE_BACKSLASH.int] = 0xdc      # VK_OEM_5      '\'
  t[SDL_SCANCODE_SEMICOLON.int] = 0xba      # VK_OEM_1      ':' on JIS
  t[SDL_SCANCODE_APOSTROPHE.int] = 0xde     # VK_OEM_7      '^' on JIS
  t[SDL_SCANCODE_GRAVE.int] = 0xc0          # VK_OEM_3      '@' on JIS
  t[SDL_SCANCODE_COMMA.int] = 0xbc          # VK_OEM_COMMA  ','
  t[SDL_SCANCODE_PERIOD.int] = 0xbe         # VK_OEM_PERIOD '.'
  t[SDL_SCANCODE_SLASH.int] = 0xbf          # VK_OEM_2      '/'
  t[SDL_SCANCODE_NONUSBACKSLASH.int] = 0xe2 # VK_OEM_102    '_' (JIS Ro key)
  t[SDL_SCANCODE_INTERNATIONAL1.int] = 0xe2 # same physical key on some layouts

  # Function keys.
  t[SDL_SCANCODE_F1.int] = 0x70
  t[SDL_SCANCODE_F2.int] = 0x71
  t[SDL_SCANCODE_F3.int] = 0x72
  t[SDL_SCANCODE_F4.int] = 0x73
  t[SDL_SCANCODE_F5.int] = 0x74
  t[SDL_SCANCODE_F6.int] = 0x75
  t[SDL_SCANCODE_F7.int] = 0x76
  t[SDL_SCANCODE_F8.int] = 0x77
  t[SDL_SCANCODE_F9.int] = 0x78
  t[SDL_SCANCODE_F10.int] = 0x79
  t[SDL_SCANCODE_F11.int] = 0x7a
  t[SDL_SCANCODE_F12.int] = 0x7b

  # Navigation cluster.
  t[SDL_SCANCODE_PRINTSCREEN.int] = 0x2c  # VK_SNAPSHOT
  t[SDL_SCANCODE_SCROLLLOCK.int] = 0x91   # VK_SCROLL
  t[SDL_SCANCODE_PAUSE.int] = 0x13        # VK_PAUSE (X1 "BRK")
  t[SDL_SCANCODE_INSERT.int] = 0x2d       # VK_INSERT
  t[SDL_SCANCODE_HOME.int] = 0x24         # VK_HOME
  t[SDL_SCANCODE_PAGEUP.int] = 0x21       # VK_PRIOR
  t[SDL_SCANCODE_DELETE.int] = 0x2e       # VK_DELETE
  t[SDL_SCANCODE_END.int] = 0x23          # VK_END
  t[SDL_SCANCODE_PAGEDOWN.int] = 0x22     # VK_NEXT
  t[SDL_SCANCODE_RIGHT.int] = 0x27        # VK_RIGHT
  t[SDL_SCANCODE_LEFT.int] = 0x25         # VK_LEFT
  t[SDL_SCANCODE_DOWN.int] = 0x28         # VK_DOWN
  t[SDL_SCANCODE_UP.int] = 0x26           # VK_UP

  # Numeric keypad.
  t[SDL_SCANCODE_NUMLOCKCLEAR.int] = 0x90 # VK_NUMLOCK
  t[SDL_SCANCODE_KP_DIVIDE.int] = 0x6f    # VK_DIVIDE
  t[SDL_SCANCODE_KP_MULTIPLY.int] = 0x6a  # VK_MULTIPLY
  t[SDL_SCANCODE_KP_MINUS.int] = 0x6d     # VK_SUBTRACT
  t[SDL_SCANCODE_KP_PLUS.int] = 0x6b      # VK_ADD
  t[SDL_SCANCODE_KP_ENTER.int] = 0x6c     # VK_SEPARATOR (X1 matrix's "NPRET")
  t[SDL_SCANCODE_KP_1.int] = 0x61
  t[SDL_SCANCODE_KP_2.int] = 0x62
  t[SDL_SCANCODE_KP_3.int] = 0x63
  t[SDL_SCANCODE_KP_4.int] = 0x64
  t[SDL_SCANCODE_KP_5.int] = 0x65
  t[SDL_SCANCODE_KP_6.int] = 0x66
  t[SDL_SCANCODE_KP_7.int] = 0x67
  t[SDL_SCANCODE_KP_8.int] = 0x68
  t[SDL_SCANCODE_KP_9.int] = 0x69
  t[SDL_SCANCODE_KP_0.int] = 0x60
  t[SDL_SCANCODE_KP_PERIOD.int] = 0x6e    # VK_DECIMAL

  # Modifiers - distinct L/R codes; osd_input.cpp merges them into the
  # generic VK_SHIFT/VK_CONTROL/VK_MENU the X1 keyboard matrix expects.
  t[SDL_SCANCODE_LCTRL.int] = 0xa2    # VK_LCONTROL
  t[SDL_SCANCODE_RCTRL.int] = 0xa3    # VK_RCONTROL
  t[SDL_SCANCODE_LSHIFT.int] = 0xa0   # VK_LSHIFT
  t[SDL_SCANCODE_RSHIFT.int] = 0xa1   # VK_RSHIFT
  t[SDL_SCANCODE_LALT.int] = 0xa4     # VK_LMENU (X1 "GRAPH")
  t[SDL_SCANCODE_RALT.int] = 0xa5     # VK_RMENU

  # JIS IME keys (best-effort; confirm on real hardware in phase 8).
  t[SDL_SCANCODE_INTERNATIONAL3.int] = 0xdc  # Yen key -> shares VK_OEM_5 slot
  t[SDL_SCANCODE_INTERNATIONAL4.int] = 0x1c  # Henkan -> VK_CONVERT
  t[SDL_SCANCODE_INTERNATIONAL5.int] = 0x1d  # Muhenkan -> VK_NONCONVERT
  t[SDL_SCANCODE_LANG1.int] = 0x15           # Kana toggle -> VK_KANA
  t[SDL_SCANCODE_LANG2.int] = 0x15           # Eisu/Kana toggle (JIS Mac) -> VK_KANA
  t

## Translates one SDL scancode to a win32 VK code, or 0 if unmapped.
##
## `arrowsAsTenkey` and `numberRowAsTenkey` are host-side substitutes for a
## physical ten-key pad, which 65%/TKL keyboards do not have: with either on,
## the named cluster sends the X1 matrix's ten-key VK codes
## (`src/core/vm/x1/keyboard.cpp`) instead of its own. They override the
## static table rather than being baked into it because they are runtime
## preferences (Host > Keyboard, hostconfig.nim), not something fixed at
## compile time.
proc toVk*(scancode: Scancode, arrowsAsTenkey = false,
           numberRowAsTenkey = false): int32 =
  if arrowsAsTenkey:
    case scancode
    of SDL_SCANCODE_UP: return 0x68    # VK_NUMPAD8 ("N8", up on the X1 ten-key)
    of SDL_SCANCODE_DOWN: return 0x62  # VK_NUMPAD2 ("N2", down)
    of SDL_SCANCODE_LEFT: return 0x64  # VK_NUMPAD4 ("N4", left)
    of SDL_SCANCODE_RIGHT: return 0x66 # VK_NUMPAD6 ("N6", right)
    else: discard
  if numberRowAsTenkey:
    case scancode
    of SDL_SCANCODE_0: return 0x60     # VK_NUMPAD0
    of SDL_SCANCODE_1: return 0x61
    of SDL_SCANCODE_2: return 0x62
    of SDL_SCANCODE_3: return 0x63
    of SDL_SCANCODE_4: return 0x64
    of SDL_SCANCODE_5: return 0x65
    of SDL_SCANCODE_6: return 0x66
    of SDL_SCANCODE_7: return 0x67
    of SDL_SCANCODE_8: return 0x68
    of SDL_SCANCODE_9: return 0x69
    else: discard
  let i = scancode.int
  if i >= 0 and i < scancodeToVk.len:
    result = scancodeToVk[i]
  else:
    result = 0
