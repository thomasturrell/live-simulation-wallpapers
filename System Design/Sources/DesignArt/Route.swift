import CoreGraphics
import DesignEngine

/// The stroke, arrowhead, label and travelling pulse all use the same sampled centreline.
struct Route {
    let path: CGPath
    let samples: [CGPoint]
    private let lengths: [CGFloat]
    var length: CGFloat { lengths.last ?? 0 }

    init(source: CGRect, target: CGRect, obstacles: [CGRect], layout: Arrangement, returning: Bool) {
        let blocked = obstacles.map { $0.insetBy(dx: -10, dy: -10) }
        let from = Self.ports(source), to = Self.ports(target)
        let start = source.centre, end = target.centre
        var best = [start, end]
        var cost = CGFloat.infinity
        let all = blocked + [source.insetBy(dx: 1, dy: 1), target.insetBy(dx: 1, dy: 1)]
        func consider(_ vertices: [CGPoint], penalty: CGFloat = 0) {
            var score = penalty + CGFloat(vertices.count - 2) * 9
            for (a, b) in zip(vertices, vertices.dropFirst()) {
                score += hypot(b.x - a.x, b.y - a.y)
                if score >= cost { return }
                for rect in all where Self.segment(a, b, intersects: rect) { score += 20_000 }
            }
            if score < cost {
                best = vertices
                cost = score
            }
        }

        for (a, da) in from {
            let p = CGPoint(x: a.x + da.x * 20, y: a.y + da.y * 20)
            for (b, db) in to {
                let q = CGPoint(x: b.x + db.x * 20, y: b.y + db.y * 20)
                let organic = [.radial, .mesh, .cycle].contains(layout) && !returning
                if organic { consider([a, b]) }
                consider([a, p, CGPoint(x: p.x, y: q.y), q, b])
                consider([a, p, CGPoint(x: q.x, y: p.y), q, b])
                let offsets = returning ? [54.0, -54.0] : [0.0]
                for offset in offsets {
                    let x = (p.x + q.x) / 2 + offset, y = (p.y + q.y) / 2 + offset
                    consider([a, p, CGPoint(x: x, y: p.y), CGPoint(x: x, y: q.y), q, b])
                    consider([a, p, CGPoint(x: p.x, y: y), CGPoint(x: q.x, y: y), q, b])
                }
                if cost > 20_000 || returning {
                    let box = source.union(target)
                    let xLanes = [box.minX - 40, box.maxX + 40] + blocked.flatMap { [$0.minX - 12, $0.maxX + 12] }
                    let yLanes = [box.minY - 40, box.maxY + 40] + blocked.flatMap { [$0.minY - 12, $0.maxY + 12] }
                    for x in xLanes { consider([a, p, CGPoint(x: x, y: p.y), CGPoint(x: x, y: q.y), q, b]) }
                    for y in yLanes { consider([a, p, CGPoint(x: p.x, y: y), CGPoint(x: q.x, y: y), q, b]) }
                }
            }
        }
        var vertices: [CGPoint] = []
        for p in best where vertices.last != p {
            if vertices.count >= 2 {
                let a = vertices[vertices.count - 2], b = vertices.last!
                if (a.x == b.x && b.x == p.x) || (a.y == b.y && b.y == p.y) { vertices.removeLast() }
            }
            vertices.append(p)
        }
        let stroke = CGMutablePath()
        stroke.move(to: vertices[0])
        var samples = [vertices[0]]
        let radius: CGFloat = layout == .tree ? 3 : (layout == .cycle || layout == .mesh ? 45 : 17)
        for i in vertices.indices.dropFirst().dropLast() {
            let a = vertices[i - 1], b = vertices[i], c = vertices[i + 1]
            let ab = hypot(a.x - b.x, a.y - b.y), bc = hypot(b.x - c.x, b.y - c.y)
            let r = min(radius, ab * 0.45, bc * 0.45)
            let p = lerp(b, a, r / max(1, ab)), q = lerp(b, c, r / max(1, bc))
            stroke.addLine(to: p)
            samples.append(p)
            stroke.addQuadCurve(to: q, control: b)
            for j in 1...8 {
                let t = CGFloat(j) / 8
                samples.append(lerp(lerp(p, b, t), lerp(b, q, t), t))
            }
        }
        if vertices.count == 2, layout == .cycle || layout == .mesh {
            let a = vertices[0], b = vertices[1], mid = lerp(a, b, 0.5)
            let distance = max(1, hypot(b.x - a.x, b.y - a.y))
            let bend = min(48, distance * 0.18) / distance
            let control = CGPoint(x: mid.x - (b.y - a.y) * bend, y: mid.y + (b.x - a.x) * bend)
            let curve = (0...16).map { step in
                let t = CGFloat(step) / 16
                return lerp(lerp(a, control, t), lerp(control, b, t), t)
            }
            if !zip(curve, curve.dropFirst()).contains(where: { p, q in all.contains { Self.segment(p, q, intersects: $0) } }) {
                stroke.addQuadCurve(to: b, control: control)
                samples = curve
            }
        }
        if samples.last != vertices.last {
            stroke.addLine(to: vertices.last!)
            samples.append(vertices.last!)
        }
        self.samples = samples
        path = stroke
        var lengths: [CGFloat] = [0]
        for (a, b) in zip(samples, samples.dropFirst()) { lengths.append(lengths.last! + hypot(b.x - a.x, b.y - a.y)) }
        self.lengths = lengths
    }

    func point(at fraction: CGFloat) -> CGPoint {
        let offset = max(0, min(1, fraction)) * length
        for i in lengths.indices.dropFirst() where lengths[i] >= offset {
            let t = (offset - lengths[i - 1]) / max(0.0001, lengths[i] - lengths[i - 1])
            return lerp(samples[i - 1], samples[i], t)
        }
        return samples.last!
    }

    func intersects(_ rect: CGRect) -> Bool {
        zip(samples, samples.dropFirst()).contains { Self.segment($0, $1, intersects: rect) }
    }

    private static func ports(_ r: CGRect) -> [(CGPoint, CGPoint)] {
        [(CGPoint(x: r.maxX, y: r.midY), CGPoint(x: 1, y: 0)), (CGPoint(x: r.minX, y: r.midY), CGPoint(x: -1, y: 0)),
         (CGPoint(x: r.midX, y: r.maxY), CGPoint(x: 0, y: 1)), (CGPoint(x: r.midX, y: r.minY), CGPoint(x: 0, y: -1))]
    }

    private static func segment(_ a: CGPoint, _ b: CGPoint, intersects r: CGRect) -> Bool {
        var lo: CGFloat = 0, hi: CGFloat = 1
        for (p, d, low, high) in [(a.x, b.x - a.x, r.minX, r.maxX), (a.y, b.y - a.y, r.minY, r.maxY)] {
            if abs(d) < 0.0001 {
                if p < low || p > high { return false }
            } else {
                let u = (low - p) / d, v = (high - p) / d
                lo = max(lo, min(u, v))
                hi = min(hi, max(u, v))
                if lo > hi { return false }
            }
        }
        return true
    }
}
