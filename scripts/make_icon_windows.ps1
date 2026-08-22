# Regenerates assets/windows/app.ico from the same source artwork the
# other platforms' icons come from (assets/AppIcon.icon/Assets/BubiX1turboZ.png).
#
# Not part of any build script, the same way scripts/make_icon.sh (macOS)
# is not: app.ico is committed, so building or packaging never needs this
# to run. Run it by hand only when the source artwork changes. Needs
# PowerShell's System.Drawing (Windows only, which every machine that
# would run this already is).
#
# Usage: pwsh -File scripts/make_icon_windows.ps1
# Result: assets/windows/app.ico (16/32/48/256 px, PNG-compressed entries)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $root "assets\AppIcon.icon\Assets\BubiX1turboZ.png"
$dest = Join-Path $root "assets\windows\app.ico"
$sizes = @(16, 32, 48, 256)

$srcImage = [System.Drawing.Image]::FromFile($source)

$entries = @()
foreach ($size in $sizes) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($srcImage, 0, 0, $size, $size)
    $g.Dispose()

    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $entries += , @{ Size = $size; Png = $ms.ToArray() }
    $bmp.Dispose()
}
$srcImage.Dispose()

# ICO container: a 6-byte ICONDIR, one 16-byte ICONDIRENTRY per image, then
# the images themselves - each entry here a plain PNG, which every Windows
# version since Vista accepts directly (no BMP/DIB conversion needed).
$headerSize = 6 + 16 * $entries.Count
$stream = New-Object System.IO.MemoryStream
$writer = New-Object System.IO.BinaryWriter $stream

$writer.Write([uint16]0)   # reserved
$writer.Write([uint16]1)   # type: icon
$writer.Write([uint16]$entries.Count)

$offset = $headerSize
foreach ($e in $entries) {
    $b = if ($e.Size -ge 256) { 0 } else { $e.Size }
    $writer.Write([byte]$b)          # width (0 = 256)
    $writer.Write([byte]$b)          # height
    $writer.Write([byte]0)           # color count
    $writer.Write([byte]0)           # reserved
    $writer.Write([uint16]1)         # color planes
    $writer.Write([uint16]32)        # bits per pixel
    $writer.Write([uint32]$e.Png.Length)
    $writer.Write([uint32]$offset)
    $offset += $e.Png.Length
}
foreach ($e in $entries) {
    $writer.Write($e.Png)
}

[System.IO.File]::WriteAllBytes($dest, $stream.ToArray())
$writer.Dispose()
$stream.Dispose()

Write-Output "wrote $dest ($($entries.Count) sizes: $($sizes -join ', '))"
