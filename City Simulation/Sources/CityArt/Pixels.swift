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
    // The integer coordinates preserve the original sprites' rounding. Fine artwork
    // also retains the fractional projection through subsequent offsets.
    private let fraction: CGPoint
    var point: CGPoint { CGPoint(x: CGFloat(x) + fraction.x, y: CGFloat(y) + fraction.y) }

    init(_ x: Int, _ y: Int, fraction: CGPoint = .zero) {
        self.x = x
        self.y = y
        self.fraction = fraction
    }

    func offset(_ dx: Int, _ dy: Int) -> Dot { Dot(x + dx, y + dy, fraction: fraction) }

    func projectedOffset(_ dx: Double, _ dy: Double) -> Dot {
        let ix = dx.rounded(), iy = dy.rounded()
        return Dot(x + Int(ix), y + Int(iy),
                   fraction: CGPoint(x: fraction.x + dx - ix, y: fraction.y + dy - iy))
    }

    func iso(_ u: Int, _ v: Int, _ z: Int = 0) -> Dot {
        Dot(x + u - v, y + ((u + v) >> 1) - z,
            fraction: CGPoint(x: fraction.x, y: fraction.y + Double((u + v) & 1) * 0.5))
    }
}

struct Pixels {
    let width: Int
    let height: Int
    let rasterScale: Int
    let rasterWidth: Int
    let rasterHeight: Int
    var storage: [UInt32]
    var depths: [Int16]
    var depth: Int16 = 0
    var overlay = false

    init(width: Int, height: Int, background: Ink, rasterScale: Int = 1) {
        self.width = width
        self.height = height
        self.rasterScale = rasterScale
        rasterWidth = width * rasterScale
        rasterHeight = height * rasterScale
        storage = [UInt32](repeating: background.pixel, count: rasterWidth * rasterHeight)
        depths = [Int16](repeating: 0, count: rasterWidth * rasterHeight)
    }

    mutating func span(_ x1: Int, _ x2: Int, _ y: Int, _ ink: Ink) {
        if rasterScale > 1 {
            let row = y * rasterScale
            for dy in 0..<(rasterScale + 1) / 2 {
                rasterSpan(x1 * rasterScale, (x2 + 1) * rasterScale - 1, row + dy, ink)
            }
        } else {
            rasterSpan(x1, x2, y, ink)
        }
    }

    private mutating func rasterSpan(_ x1: Int, _ x2: Int, _ y: Int, _ ink: Ink) {
        guard y >= 0, y < rasterHeight else { return }
        let start = max(0, x1), last = min(rasterWidth - 1, x2)
        guard start <= last else { return }
        let row = y * rasterWidth, pixel = ink.pixel
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
        let x = rasterScale == 1 ? p.x : Int((p.point.x * Double(rasterScale)).rounded(.down))
        let y = rasterScale == 1 ? p.y : Int((p.point.y * Double(rasterScale)).rounded(.down))
        for row in y..<y + h * rasterScale { rasterSpan(x, x + w * rasterScale - 1, row, ink) }
    }

    mutating func line(_ a: Dot, _ b: Dot, _ ink: Ink, width: Double = 0.65) {
        if rasterScale > 1 {
            let start = a.point, end = b.point
            let dx = end.x - start.x, dy = end.y - start.y
            let length = hypot(dx, dy)
            let nx = length > 0 ? -dy / length : 0, ny = length > 0 ? dx / length : 1
            let half = width * 0.5
            func corner(_ point: CGPoint, _ cap: Double, _ side: Double) -> CGPoint {
                CGPoint(x: point.x + half * (cap * ny + side * nx),
                        y: point.y + half * (-cap * nx + side * ny))
            }
            fillPolygon([corner(start, -1, -1), corner(end, 1, -1),
                         corner(end, 1, 1), corner(start, -1, 1)], ink)
            return
        }
        var x = a.x, y = a.y
        let dx = abs(b.x - x), dy = -abs(b.y - y)
        let sx = x < b.x ? 1 : -1, sy = y < b.y ? 1 : -1
        var error = dx + dy
        while true {
            rasterSpan(x, x, y, ink)
            if x == b.x && y == b.y { break }
            let twice = error * 2
            if twice >= dy { error += dy; x += sx }
            if twice <= dx { error += dx; y += sy }
        }
    }

    mutating func polygon(_ points: [Dot], _ ink: Ink, bottomInk: Ink? = nil) {
        let vertices = rasterScale == 1 ? points.map { CGPoint(x: $0.x, y: $0.y) } : points.map(\.point)
        fillPolygon(vertices, ink, bottomInk: bottomInk)
    }

    /// Scan-convert logical geometry directly onto the backing raster. Both the
    /// colour buffer and the occlusion mask use these same subpixel samples.
    private mutating func fillPolygon(_ vertices: [CGPoint], _ ink: Ink, bottomInk: Ink? = nil) {
        let scale = Double(rasterScale)
        let points = rasterScale == 1 ? vertices : vertices.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
        guard let top = points.map(\.y).min(), let bottom = points.map(\.y).max() else { return }
        let minY = Int(floor(top)), maxY = Int(ceil(bottom))
        guard minY < rasterHeight, maxY >= 0 else { return }
        for y in max(0, minY)...min(rasterHeight - 1, maxY) {
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
            if left <= right {
                let tone = bottomInk.map { ink.mix($0, (sample - top) / (bottom - top)) } ?? ink
                rasterSpan(Int(ceil(left - 0.5)), Int(ceil(right - 0.5)) - 1, y, tone)
            }
        }
    }

    mutating func oval(at center: Dot, radiusX: Double, radiusY: Double, top: Ink, bottom: Ink) {
        let scale = Double(rasterScale), point = center.point
        let rx = radiusX * scale, ry = radiusY * scale
        let cx = point.x * scale, cy = point.y * scale
        let first = max(0, Int(ceil(cy - ry - 0.5))), last = min(rasterHeight, Int(ceil(cy + ry - 0.5)))
        guard first < last else { return }
        for y in first..<last {
            let dy = (Double(y) + 0.5 - cy) / ry
            let half = rx * sqrt(max(0, 1 - dy * dy))
            rasterSpan(Int(ceil(cx - half - 0.5)), Int(ceil(cx + half - 0.5)) - 1, y,
                       top.mix(bottom, (dy + 1) * 0.5))
        }
    }

    mutating func tile(_ p: Dot, _ u: Int, _ v: Int, _ width: Int, _ length: Int, _ ink: Ink) {
        polygon([p.iso(u, v), p.iso(u + width, v), p.iso(u + width, v + length), p.iso(u, v + length)], ink)
    }

    func image() -> CGImage {
        let data = storage.withUnsafeBytes { Data($0) }
        return CGImage(width: rasterWidth, height: rasterHeight, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: rasterWidth * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: [.byteOrder32Big, CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)],
                       provider: CGDataProvider(data: data as CFData)!, decode: nil,
                       shouldInterpolate: rasterScale > 1, intent: .defaultIntent)!
    }
}
