import AppKit
import WallpaperPalette

/// A three-component version of the artwork remains recognisable at Finder icon sizes.
func iconPNG(size: Int = 1024) -> Data? {
    let palette = LifePalette(darkness: 0, colour: .green, generation: 0, seed: 42)
    guard let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    let scale = CGFloat(size) / 1024
    c.scaleBy(x: scale, y: scale)
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

func iconICNS() -> Data? {
    // Keep the standard and Retina representations at each Finder icon size.
    let representations = [
        ("icp4", 16), ("ic11", 32),
        ("icp5", 32), ("ic12", 64),
        ("ic07", 128), ("ic13", 256),
        ("ic08", 256), ("ic14", 512),
        ("ic09", 512), ("ic10", 1024)
    ]
    var chunks = Data()
    for (type, size) in representations {
        guard let png = iconPNG(size: size) else { return nil }
        chunks.append(contentsOf: type.utf8)
        appendLength(png.count + 8, to: &chunks)
        chunks.append(png)
    }

    var icon = Data("icns".utf8)
    appendLength(chunks.count + 8, to: &icon)
    icon.append(chunks)
    return icon
}

private func appendLength(_ count: Int, to data: inout Data) {
    var length = UInt32(count).bigEndian
    withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
}
