import AppKit
import WallpaperPalette

/// A three-component version of the artwork remains recognisable at Finder icon sizes.
func iconPNG() -> Data? {
    let palette = LifePalette(darkness: 0, colour: .green, generation: 0, seed: 42)
    guard let c = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    let tile = CGRect(x: 92, y: 92, width: 840, height: 840)
    c.addPath(CGPath(roundedRect: tile, cornerWidth: 184, cornerHeight: 184, transform: nil))
    c.clip()
    c.setFillColor(palette.background[0])
    c.fill(tile)
    c.translateBy(x: 512, y: 512)
    c.rotate(by: .pi / 10)
    c.setLineWidth(19)
    c.setLineJoin(.round)
    c.setStrokeColor(palette.cells[0])
    c.setFillColor(palette.cells[0])
    for sign in [-1.0, 1.0] {
        c.addLines(between: [CGPoint(x: -110, y: 0), .zero, CGPoint(x: 0, y: 162 * sign), CGPoint(x: 142, y: 162 * sign)])
        c.strokePath()
        c.addPath(CGPath(roundedRect: CGRect(x: 98, y: 162 * sign - 60, width: 165, height: 120),
                         cornerWidth: 28, cornerHeight: 28, transform: nil))
        c.fillPath()
    }
    c.addPath(CGPath(ellipseIn: CGRect(x: -264, y: -79, width: 158, height: 158), transform: nil))
    c.fillPath()
    guard let image = c.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
}
