import Foundation

extension Vehicle {
    // Ground-space dimensions include the full-size artwork and a small gap.
    var halfLength: Double { long ? 0.34 : 0.22 }
    var junctionClearance: Double { RoadGeometry.stopLineDistance + halfLength }
    var junctionExitClearance: Double { 5.0 / 16 + halfLength + 0.01 }
    func footprint(in convention: TrafficConvention) -> TrafficFootprint { footprint(at: distance, in: convention) }

    func path(through end: Double, in convention: TrafficConvention) -> [TrafficFootprint] {
        stride(from: distance, through: end + 0.025, by: 0.025).map { footprint(at: min($0, end), in: convention) }
    }

    func gap(to leader: Vehicle) -> Double? {
        let from = route[segment], to = route[segment + 1]
        let offset = distance - Double(segment)
        let other = leader.segment
        let ahead = leader.distance - Double(other)
        if leader.route[other] == from, leader.route[other + 1] == to { return ahead - offset }
        if other > 0, leader.route[other - 1] == from, leader.route[other] == to { return 1 + ahead - offset }
        return nil
    }

    func footprint(at distance: Double, in convention: TrafficConvention) -> TrafficFootprint {
        let pose = pose(at: distance, in: convention)
        let center = SIMD2(pose.x, pose.y)
        let length = hypot(pose.dx, pose.dy)
        let direction = length > 0 ? SIMD2(pose.dx, pose.dy) / length : SIMD2(1, 0)
        let bodyLength = pose.visibility < 0.65 ? 0.125 : halfLength
        let extent = direction * (bodyLength - TrafficFootprint.radius)
        return TrafficFootprint(front: center + extent, back: center - extent, visible: pose.visibility > 0.18)
    }
}

// A rounded vehicle body follows the same curve as the artwork, including
// turns and driveways. Unlike road-edge distances, it also detects cross traffic.
struct TrafficFootprint {
    static let radius = 0.12
    let front: SIMD2<Double>
    let back: SIMD2<Double>
    let visible: Bool
    fileprivate let bounds: TrafficBounds

    init(front: SIMD2<Double>, back: SIMD2<Double>, visible: Bool) {
        self.front = front
        self.back = back
        self.visible = visible
        bounds = TrafficBounds(minX: min(front.x, back.x), maxX: max(front.x, back.x),
                               minY: min(front.y, back.y), maxY: max(front.y, back.y))
    }

    func overlaps(_ other: Self, clearance: Double = 0) -> Bool {
        guard visible, other.visible else { return false }
        let margin = Self.radius * 2 + clearance
        guard bounds.overlaps(other.bounds, margin: margin) else { return false }
        return separationSquared(from: other) < margin * margin
    }

    func centerDistanceSquared(from other: Self) -> Double {
        let delta = (front + back - other.front - other.back) * 0.5
        return delta.x * delta.x + delta.y * delta.y
    }

    func separationSquared(from other: Self) -> Double {
        let a = front - back, b = other.front - other.back, delta = other.back - back
        let determinant = cross(a, b)
        if abs(determinant) > 0.0000001 {
            let t = cross(delta, b) / determinant
            let u = cross(delta, a) / determinant
            if (0...1).contains(t), (0...1).contains(u) { return 0 }
        }
        return min(pointDistance(front, other.back, other.front), pointDistance(back, other.back, other.front),
                   pointDistance(other.front, back, front), pointDistance(other.back, back, front))
    }

    private func pointDistance(_ point: SIMD2<Double>, _ start: SIMD2<Double>, _ end: SIMD2<Double>) -> Double {
        let line = end - start
        let squared = line.x * line.x + line.y * line.y
        let delta = point - start
        let fraction = squared > 0 ? max(0, min(1, (delta.x * line.x + delta.y * line.y) / squared)) : 0
        let gap = delta - line * fraction
        return gap.x * gap.x + gap.y * gap.y
    }

    private func cross(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { a.x * b.y - a.y * b.x }
}

// The bounds only reject distant reservations. Nearby paths retain every
// footprint sample and use the same rounded-body collision test.
struct TrafficPath {
    private let footprints: [TrafficFootprint]
    private let bounds: TrafficBounds?

    var isEmpty: Bool { footprints.isEmpty }

    init(_ footprints: [TrafficFootprint]) {
        self.footprints = footprints
        var bounds: TrafficBounds?
        for footprint in footprints where footprint.visible {
            bounds = bounds.map { $0.union(footprint.bounds) } ?? footprint.bounds
        }
        self.bounds = bounds
    }

    func overlaps(_ footprint: TrafficFootprint, clearance: Double = 0) -> Bool {
        guard footprint.visible, let bounds,
              bounds.overlaps(footprint.bounds, margin: TrafficFootprint.radius * 2 + clearance) else { return false }
        return footprints.contains { $0.overlaps(footprint, clearance: clearance) }
    }

    func overlaps(_ other: Self, clearance: Double = 0) -> Bool {
        guard let bounds, let otherBounds = other.bounds,
              bounds.overlaps(otherBounds, margin: TrafficFootprint.radius * 2 + clearance) else { return false }
        return footprints.contains { other.overlaps($0, clearance: clearance) }
    }
}

fileprivate struct TrafficBounds {
    let minX: Double
    let maxX: Double
    let minY: Double
    let maxY: Double

    func overlaps(_ other: Self, margin: Double) -> Bool {
        !(minX > other.maxX + margin || other.minX > maxX + margin
            || minY > other.maxY + margin || other.minY > maxY + margin)
    }

    func union(_ other: Self) -> Self {
        Self(minX: min(minX, other.minX), maxX: max(maxX, other.maxX),
             minY: min(minY, other.minY), maxY: max(maxY, other.maxY))
    }
}
