## Win32 backend for ui/statepicker.nim: a grid of save-state slots, each
## an owner-draw button painting its own thumbnail with a translucent bar
## across the bottom - the same layout ui/macos/statepicker.m and
## ui/linux/statepicker.nim use, built here from raw GDI + GDI+ instead of
## AppKit or GTK.
##
## Modal by hand: the main window is disabled for the duration and a
## nested message loop (winshell.runModalLoop) blocks the caller until the
## picker's own WM_DESTROY fires, mirroring gtk_dialog_run's blocking
## return - see the facade's own doc comment on `choose`.

import ./win32
import ./winshell
import ../types

const
  ClassName = "BubiX1turboZStatePicker"
  Columns = 2
  CellWidth = 248'i32
  CellHeight = 155'i32
  CellGap = 12'i32
  BarHeight = 22'i32
  DisksAreaW = 96'i32       ## Reserved on the bar's right edge for the disk
                             ## list, so a long caption's ellipsis cannot run
                             ## into it - see drawCell.
  CancelId = 9999'i32
  EmptyBg = 0x1a1a1a'u32   ## RGB(0x1a,0x1a,0x1a): Colorref is 0x00BBGGRR,
                           ## but equal channels read the same either way.
  BarAlpha = 140'u8        ## ~55%, matching the Linux/macOS pickers' bar.

var
  curCells: seq[SlotCell]
  curBitmaps: seq[HBITMAP]
  curEmptyLabel: string
  chosen: int
  closed: bool
  pickerHwnd: HWND

proc cellRect(index: int): Rect =
  let col = index mod Columns
  let row = index div Columns
  let x = CellGap + col.int32 * (CellWidth + CellGap)
  let y = CellGap + row.int32 * (CellHeight + CellGap)
  Rect(left: x, top: y, right: x + CellWidth, bottom: y + CellHeight)

proc drawTranslucentBar(dc: HDC, rect: Rect, alpha: uint8) =
  let w = rect.right - rect.left
  let h = rect.bottom - rect.top
  if w <= 0 or h <= 0:
    return
  let memDc = createCompatibleDC(dc)
  let bmp = createCompatibleBitmap(dc, w, h)
  let old = selectObject(memDc, bmp)
  var full = Rect(left: 0, top: 0, right: w, bottom: h)
  let blackBrush = createSolidBrush(0'u32)
  discard fillRect(memDc, addr full, blackBrush)
  discard deleteObject(blackBrush)
  let blend = BlendFunction(blendOp: AcSrcOver, sourceConstantAlpha: alpha)
  discard alphaBlend(dc, rect.left, rect.top, w, h, memDc, 0, 0, w, h, blend)
  discard selectObject(memDc, old)
  discard deleteObject(bmp)
  discard deleteDC(memDc)

proc drawCell(dis: ptr DrawItemStruct) =
  # DRAWITEMSTRUCT.itemID is documented as unused for a button control (it
  # only carries the item index for a listbox/combobox) - always 0 here,
  # which drew every cell as slot 0 regardless of which button was actually
  # being painted. ctlID is the field a button's WM_DRAWITEM actually
  # carries its control id in (confirmed empirically: with itemID, all ten
  # cells rendered pixel-identical to slot 0's).
  let idx = dis.ctlID.int
  if idx < 0 or idx >= curCells.len:
    return
  let cell = curCells[idx]
  let dc = dis.hDC
  let r = dis.rcItem
  let w = r.right - r.left
  let h = r.bottom - r.top
  let bmp = if idx < curBitmaps.len: curBitmaps[idx] else: nil
  if bmp != nil:
    let (bw, bh) = bitmapSize(bmp)
    if bw > 0 and bh > 0:
      let memDc = createCompatibleDC(dc)
      let old = selectObject(memDc, bmp)
      # Nearest-neighbour, not smoothed: the source is emulator pixel art,
      # matching the interpolation choice ui/linux/statepicker.nim makes.
      discard setStretchBltMode(dc, ColorOnColor)
      discard stretchBlt(dc, r.left, r.top, w, h, memDc, 0, 0, bw, bh, SrcCopy)
      discard selectObject(memDc, old)
      discard deleteDC(memDc)
  else:
    var full = r
    let bg = createSolidBrush(EmptyBg)
    discard fillRect(dc, addr full, bg)
    discard deleteObject(bg)
    discard setBkMode(dc, Transparent)
    discard setTextColor(dc, 0x808080'u32)
    var textRect = r
    discard drawTextW(dc, toWide(curEmptyLabel), -1, addr textRect,
      DtCenter or DtVcenter or DtSingleline)

  var barRect = Rect(left: r.left, top: r.bottom - BarHeight,
                     right: r.right, bottom: r.bottom)
  drawTranslucentBar(dc, barRect, BarAlpha)
  discard setBkMode(dc, Transparent)
  discard setTextColor(dc, 0x00ffffff'u32) # white
  var left = cell.caption
  if cell.detail.len > 0:
    left.add "   " & cell.detail
  # Disks (if any) get a reserved slice of the bar's right edge of their
  # own, the same fixed-width split ui/linux/statepicker.nim's GtkBox
  # lays out - otherwise the caption's own DT_END_ELLIPSIS has no reason to
  # stop short of the full bar width and a long one prints straight through
  # where the disk list is drawn.
  let hasDisks = cell.disks.len > 0
  let rightRectW = if hasDisks: DisksAreaW else: 0'i32
  var leftRect = Rect(left: barRect.left + 6, top: barRect.top,
                      right: barRect.right - 6 - rightRectW, bottom: barRect.bottom)
  discard drawTextW(dc, toWide(left), -1, addr leftRect,
    DtVcenter or DtSingleline or DtEnd_ellipsis)
  if hasDisks:
    var rightRect = Rect(left: barRect.right - 6 - rightRectW, top: barRect.top,
                         right: barRect.right - 6, bottom: barRect.bottom)
    discard drawTextW(dc, toWide(sjisToUtf8(cell.disks)), -1, addr rightRect,
      DtVcenter or DtSingleline or DtEnd_ellipsis or DtRight)

proc wndProc(hwnd: HWND, msg: uint32, wParam: WPARAM,
            lParam: LPARAM): LRESULT {.stdcall.} =
  case msg
  of WmDrawitem:
    drawCell(cast[ptr DrawItemStruct](cast[pointer](lParam)))
    return 1
  of WmCommand:
    let id = int32(wParam and 0xffff'u)
    if id == CancelId:
      chosen = -1
      discard destroyWindow(hwnd)
    elif id >= 0 and id.int < curCells.len:
      chosen = id.int
      discard destroyWindow(hwnd)
  of WmClose:
    chosen = -1
    discard destroyWindow(hwnd)
  of WmDestroy:
    closed = true
  else:
    return defWindowProcW(hwnd, msg, wParam, lParam)
  0

proc choose*(title: string, cells: seq[SlotCell],
             cancelLabel, emptyLabel: string): int =
  ensureCommonControls()
  winshell.ensureGdiplus() # pngToHBitmap below needs it up first.
  winshell.registerWindowClass(ClassName, wndProc)
  curCells = cells
  curEmptyLabel = emptyLabel
  chosen = -1
  closed = false
  curBitmaps.setLen 0
  for cell in cells:
    curBitmaps.add pngToHBitmap(cell.thumbnail)

  let rows = (cells.len + Columns - 1) div Columns
  let contentW = CellGap * (Columns + 1).int32 + CellWidth * Columns.int32
  let contentH = CellGap * (rows + 1).int32 + CellHeight * rows.int32
  const ButtonBarH = 44'i32
  let clientW = contentW
  let clientH = contentH + ButtonBarH

  pickerHwnd = createWindowExW(0, toWide(ClassName), toWide(title),
    WsCaption or WsSysmenu or WsClipChildren, 100, 100,
    clientW + 16, clientH + 40, winshell.mainHwnd, nil,
    getModuleHandleW(WideCString(nil)), nil)

  for i in 0 ..< cells.len:
    let r = cellRect(i)
    let btn = createWindowExW(0, toWide("BUTTON"), toWide(""),
      WsChild or WsVisible or BsOwnerdraw, r.left, r.top,
      r.right - r.left, r.bottom - r.top, pickerHwnd, cast[HMENU](i),
      getModuleHandleW(WideCString(nil)), nil)
    if not cells[i].enabled:
      discard enableWindow(btn, 0)

  discard createWindowExW(0, toWide("BUTTON"), toWide(cancelLabel),
    WsChild or WsVisible or BsPushbutton, (clientW - 90) div 2,
    contentH + 8, 90, 28, pickerHwnd, cast[HMENU](CancelId),
    getModuleHandleW(WideCString(nil)), nil)

  discard enableWindow(winshell.mainHwnd, 0)
  discard showWindow(pickerHwnd, SwShow)
  discard updateWindow(pickerHwnd)
  winshell.runModalLoop(proc (): bool = closed)
  discard enableWindow(winshell.mainHwnd, 1)
  discard setFocus(winshell.mainHwnd)

  for b in curBitmaps:
    if b != nil: discard deleteObject(b)
  curBitmaps.setLen 0
  chosen
