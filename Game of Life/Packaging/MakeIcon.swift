import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let resolution = 1024
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: resolution, height: resolution,
                        bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ red: Double, _ green: Double, _ blue: Double) -> CGColor {
    CGColor(srgbRed: red, green: green, blue: blue, alpha: 1)
}

let tile = CGRect(x: 96, y: 96, width: 832, height: 832)
context.addPath(CGPath(roundedRect: tile, cornerWidth: 190, cornerHeight: 190, transform: nil))
context.clip()
let tones = [color(0.13, 0.14, 0.15), color(0.06, 0.067, 0.074)]
let gradient = CGGradient(colorsSpace: colorSpace, colors: tones as CFArray, locations: nil)!
context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: tile.maxY),
                           end: CGPoint(x: 0, y: tile.minY), options: [])
context.translateBy(x: 512, y: 512)
context.rotate(by: 12 * .pi / 180)
let glider: [(CGFloat, CGFloat, CGColor)] = [
    (0, 1, color(0.51, 0.65, 0.59)),
    (1, 0, color(0.63, 0.57, 0.68)),
    (-1, -1, color(0.59, 0.61, 0.60)),
    (0, -1, color(0.71, 0.66, 0.58)),
    (1, -1, color(0.66, 0.73, 0.69))
]
for (x, y, fill) in glider {
    let cell = CGRect(x: x * 151 - 58, y: y * 151 - 58, width: 116, height: 116)
    context.setFillColor(fill)
    context.addPath(CGPath(roundedRect: cell, cornerWidth: 11, cornerHeight: 11, transform: nil))
    context.fillPath()
}

let original = context.makeImage()!
var chunks = Data()
func appendLength(_ count: Int, to data: inout Data) {
    var length = UInt32(count).bigEndian
    withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
}

// Use PNG-backed ICNS records so the icon preserves its alpha and colour profile.
for (size, type) in [(128, "ic07"), (256, "ic08"), (512, "ic09"), (1024, "ic10")] {
    let resized = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                            bytesPerRow: 0, space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    resized.interpolationQuality = .high
    resized.draw(original, in: CGRect(x: 0, y: 0, width: size, height: size))
    let data = NSMutableData()
    let png = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(png, resized.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(png))
    chunks.append(contentsOf: type.utf8)
    appendLength(data.length + 8, to: &chunks)
    chunks.append(data as Data)
}
var icon = Data("icns".utf8)
appendLength(chunks.count + 8, to: &icon)
icon.append(chunks)
try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
