import CoreGraphics
import Foundation

struct Ink: Equatable {
    let rgb: UInt32
    init(_ rgb: UInt32) { self.rgb = rgb }

    var pixel: UInt32 {
        0xFF00_0000 | ((rgb & 0xFF) << 16) | (rgb & 0xFF00) | ((rgb >> 16) & 0xFF)
    }

    func mix(_ other: Ink, _ fraction: Double) -> Ink {
        var value: UInt32 = 0
        for shift in [0, 8, 16] {
            let a = Int((rgb >> shift) & 255)
            let b = Int((other.rgb >> shift) & 255)
            value |= UInt32(a + Int((Double(b - a) * fraction).rounded())) << shift
        }
        return Ink(value)
    }
}

struct Dot: Equatable {
    let x: Int
    let y: Int
    init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
    static func + (a: Dot, b: Dot) -> Dot { Dot(a.x + b.x, a.y + b.y) }
    func offset(_ dx: Int, _ dy: Int) -> Dot { Dot(x + dx, y + dy) }

    func iso(_ u: Int, _ v: Int, _ z: Int = 0) -> Dot {
        offset(u - v, ((u + v) >> 1) - z)
    }
}

struct Pixels {
    let width: Int
    let height: Int
    var storage: [UInt32]
    var depths: [Int16]
    var depth: Int16 = 0
    var overlay = false

    init(width: Int, height: Int, background: Ink) {
        self.width = width
        self.height = height
        storage = [UInt32](repeating: background.pixel, count: width * height)
        depths = [Int16](repeating: 0, count: width * height)
    }

    mutating func span(_ x1: Int, _ x2: Int, _ y: Int, _ ink: Ink) {
        guard y >= 0, y < height else { return }
        let start = max(0, x1), last = min(width - 1, x2)
        guard start <= last else { return }
        let row = y * width, pixel = ink.pixel
        if overlay {
            for x in start...last where depth >= depths[row + x] { storage[row + x] = pixel }
        } else if depth == 0 {
            for x in start...last { storage[row + x] = pixel }
        } else {
            for x in start...last {
                storage[row + x] = pixel
                depths[row + x] = depth
            }
        }
    }

    mutating func box(_ p: Dot, _ w: Int, _ h: Int, _ ink: Ink) {
        for y in p.y..<p.y + h { span(p.x, p.x + w - 1, y, ink) }
    }

    mutating func line(_ a: Dot, _ b: Dot, _ ink: Ink) {
        var x = a.x, y = a.y
        let dx = abs(b.x - x), dy = -abs(b.y - y)
        let sx = x < b.x ? 1 : -1, sy = y < b.y ? 1 : -1
        var error = dx + dy
        while true {
            span(x, x, y, ink)
            if x == b.x && y == b.y { break }
            let twice = error * 2
            if twice >= dy { error += dy; x += sx }
            if twice <= dx { error += dx; y += sy }
        }
    }

    mutating func polygon(_ points: [Dot], _ ink: Ink) {
        guard let minY = points.map(\.y).min(), let maxY = points.map(\.y).max(),
              minY < height, maxY >= 0 else { return }
        for y in max(0, minY)...min(height - 1, maxY) {
            let sample = Double(y) + 0.5
            var left = Double.infinity, right = -Double.infinity
            var a = points.last!
            for b in points {
                if (Double(a.y) > sample) != (Double(b.y) > sample) {
                    let x = Double(a.x) + (sample - Double(a.y)) * Double(b.x - a.x) / Double(b.y - a.y)
                    left = min(left, x)
                    right = max(right, x)
                }
                a = b
            }
            if left <= right { span(Int(ceil(left - 0.5)), Int(ceil(right - 0.5)) - 1, y, ink) }
        }
    }

    mutating func tile(_ p: Dot, _ u: Int, _ v: Int, _ width: Int, _ length: Int, _ ink: Ink) {
        polygon([p.iso(u, v), p.iso(u + width, v), p.iso(u + width, v + length), p.iso(u, v + length)], ink)
    }

    func image() -> CGImage {
        let data = storage.withUnsafeBytes { Data($0) }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: [.byteOrder32Big, CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)],
                       provider: CGDataProvider(data: data as CFData)!, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)!
    }
}
