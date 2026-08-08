## Text rendering for the status bar, using the X1's own 8x8 ANK font ROM.
##
## The status bar needs to print the same wording the original Windows app
## does ("FD:", "CMT:", the tape deck's message). SDL2 has no text
## rendering of its own, and the two obvious ways to add it are both bad
## for this project:
##
## * SDL_ttf would be a Homebrew dependency, and phase 7 established that
##   the eventual .dmg must run on a Mac with no Homebrew at all.
## * The core's `draw_text_to_bitmap` OSD entry point is a deliberate no-op
##   (phase 3) and implementing it would mean a host font API anyway.
##
## `FNT0808.X1` (or `ANK8.ROM`, which the core prefers if present) is
## already required for the emulator to display anything, so it costs
## nothing extra and gives the status bar the machine's own glyphs. Layout
## is 256 characters x 8 bytes, one byte per scanline, most significant bit
## leftmost - verified by dumping 'A'. Codes 0x20-0x7E are plain ASCII;
## everything the status bar prints falls in that range.
##
## If neither ROM is present the module degrades to `ready == false` and
## every draw becomes a no-op, so a missing font never takes the app down.

import std/[os, strutils]
import sdl2

const
  GlyphWidth* = 8
  GlyphHeight* = 8
  GridCols = 16 # 16x16 glyphs = the full 256-character ROM in one texture

type
  AnkFont* = object
    ## A texture atlas of all 256 glyphs, drawn white-on-transparent so
    ## `SDL_SetTextureColorMod` can tint it per call site.
    texture: TexturePtr
    ready*: bool

proc load*(renderer: RendererPtr, romDir: string): AnkFont =
  ## Builds the atlas from the first font ROM found in `romDir`. Returns an
  ## object with `ready == false` (and no texture) if none is readable.
  ##
  ## Both names are tried in the same order the core's display.cpp uses, so
  ## a ROM set that works for the emulator works for the status bar too.
  var data: string
  for name in ["ANK8.ROM", "FNT0808.X1"]:
    # The core's own constants are upper case while real-world ROM dumps are
    # often lower case; macOS's default case-insensitive volume hides this,
    # but a case-sensitive one (or Linux later) would not.
    for candidate in [name, name.toLowerAscii()]:
      let path = romDir / candidate
      if fileExists(path):
        try:
          data = readFile(path)
        except IOError:
          continue
        break
    if data.len >= 256 * GlyphHeight:
      break
    data = ""
  if data.len < 256 * GlyphHeight:
    return AnkFont(ready: false)

  const atlasW = GridCols * GlyphWidth
  const atlasH = (256 div GridCols) * GlyphHeight
  var pixels = newSeq[uint32](atlasW * atlasH)
  for ch in 0 ..< 256:
    let ox = (ch mod GridCols) * GlyphWidth
    let oy = (ch div GridCols) * GlyphHeight
    for row in 0 ..< GlyphHeight:
      let bits = data[ch * GlyphHeight + row].uint8
      for col in 0 ..< GlyphWidth:
        if (bits and (0x80'u8 shr col)) != 0:
          pixels[(oy + row) * atlasW + ox + col] = 0xFFFFFFFF'u32

  let tex = renderer.createTexture(SDL_PIXELFORMAT_ARGB8888,
    SDL_TEXTUREACCESS_STATIC, atlasW.cint, atlasH.cint)
  if tex == nil:
    return AnkFont(ready: false)
  if tex.updateTexture(nil, addr pixels[0], cint(atlasW * 4)) != SdlSuccess:
    tex.destroy()
    return AnkFont(ready: false)
  # Glyph pixels are opaque white and the gaps are fully transparent, so the
  # atlas must blend rather than overwrite - without this the whole 8x8 cell
  # would punch a white block into the bar.
  discard tex.setTextureBlendMode(BlendMode_Blend)
  AnkFont(texture: tex, ready: true)

proc destroy*(f: var AnkFont) =
  if f.texture != nil:
    f.texture.destroy()
    f.texture = nil
  f.ready = false

proc width*(f: AnkFont, text: string): cint =
  ## Pixel width `text` will occupy. Zero when no font is loaded, which
  ## keeps right-aligned layout arithmetic correct in the degraded case.
  if f.ready: cint(text.len * GlyphWidth) else: 0

proc draw*(f: AnkFont, renderer: RendererPtr, x, y: cint, text: string,
           r, g, b: uint8): cint {.discardable.} =
  ## Draws `text` with its top-left corner at (x, y) and returns the x
  ## coordinate just past the last glyph, so call sites can lay a line out
  ## left to right without recomputing widths.
  result = x
  if not f.ready:
    return
  discard f.texture.setTextureColorMod(r, g, b)
  for ch in text:
    let code = ch.uint8.int
    var src = rect(cint((code mod GridCols) * GlyphWidth),
                   cint((code div GridCols) * GlyphHeight),
                   GlyphWidth.cint, GlyphHeight.cint)
    var dst = rect(result, y, GlyphWidth.cint, GlyphHeight.cint)
    renderer.copy(f.texture, addr src, addr dst)
    result += GlyphWidth
