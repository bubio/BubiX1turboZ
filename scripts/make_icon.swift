// Renders assets/BubiX1turboZ.icns from the artwork in assets/BubiX1turboZ.png.
//
// The artwork is a full-bleed rounded square, the shape iOS uses. macOS keeps
// its icons inside the canvas instead, so each variant is composed here: the
// artwork is drawn at the macOS icon grid's content size (824 of 1024) with a
// soft shadow beneath it, which is what makes the icon sit at the same visual
// weight as the stock ones in the Dock and the Finder.
//
// Every size is composed at its own resolution rather than downsampled from one
// finished bitmap, so the shadow stays proportional and the 16pt and 32pt
// variants keep their edges.
//
// Run scripts/make_icon.sh to regenerate; the resulting .icns is committed, so
// neither the build nor CI runs this.
//
// Usage: swift scripts/make_icon.swift <artwork.png> <output-directory>
//   Writes icon_<size>x<size>[@2x].png files for iconutil to consume.

import AppKit
import Foundation

/// One entry of the .iconset: a logical point size and a scale factor.
struct Variant {
    let points: Int
    let scale: Int
    var pixels: Int { points * scale }
    var filename: String {
        scale == 1 ? "icon_\(points)x\(points).png"
                   : "icon_\(points)x\(points)@\(scale)x.png"
    }
}

let variants: [Variant] = [16, 32, 128, 256, 512].flatMap {
    [Variant(points: $0, scale: 1), Variant(points: $0, scale: 2)]
}

/// Proportions of the macOS icon grid, expressed as fractions of the canvas.
let contentFraction: CGFloat = 824.0 / 1024.0
let shadowOffsetFraction: CGFloat = 10.0 / 1024.0
let shadowBlurFraction: CGFloat = 24.0 / 1024.0

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("error: \(message)\n".data(using: .utf8)!)
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(
        "usage: make_icon.swift <artwork.png> <output-directory>\n"
            .data(using: .utf8)!)
    exit(1)
}
let artworkURL = URL(fileURLWithPath: arguments[1])
let outputDir = URL(fileURLWithPath: arguments[2], isDirectory: true)

guard let source = CGImageSourceCreateWithURL(artworkURL as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil)
else { fail("could not read artwork at \(artworkURL.path)") }

for variant in variants {
    let size = CGFloat(variant.pixels)
    guard let ctx = CGContext(data: nil, width: variant.pixels, height: variant.pixels,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fail("could not create bitmap context") }

    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)

    let content = (size * contentFraction).rounded()
    let origin = ((size - content) / 2).rounded()
    let rect = CGRect(x: origin, y: origin, width: content, height: content)

    // The shadow is dropped only when it can still resolve: below roughly 32
    // pixels its blur would smear into the artwork's own dark edge and read as
    // a blurred outline rather than a shadow.
    if size >= 32 {
        ctx.setShadow(offset: CGSize(width: 0, height: -size * shadowOffsetFraction),
                      blur: size * shadowBlurFraction,
                      color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
    }
    ctx.draw(artwork, in: rect)

    guard let image = ctx.makeImage() else { fail("could not render \(variant.filename)") }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let png = rep.representation(using: .png, properties: [:])
    else { fail("could not encode \(variant.filename)") }
    try png.write(to: outputDir.appendingPathComponent(variant.filename))
}
