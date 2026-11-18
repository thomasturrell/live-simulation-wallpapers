import Foundation

extension Vehicle {
    // Ground-space dimensions include the full-size artwork and a small gap.
    var halfLength: Double { long ? 0.34 : 0.22 }
    var junctionClearance: Double { 0.5 + halfLength + 0.12 }
    var junctionExitClearance: Double { 5.0 / 16 + halfLength + 0.01 }
    var footprint: TrafficFootprint { footprint(at: distance) }

    func path(through end: Double) -> [TrafficFootprint] {
        stride(from: distance, through: end + 0.025, by: 0.025).map { footprint(at: min($0, end)) }
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

    func footprint(at distance: Double) -> TrafficFootprint {
        let pose = pose(at: distance)
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

    func overlaps(_ other: Self, clearance: Double = 0) -> Bool {
        guard visible, other.visible else { return false }
        let margin = Self.radius * 2 + clearance
        if min(front.x, back.x) > max(other.front.x, other.back.x) + margin
            || min(other.front.x, other.back.x) > max(front.x, back.x) + margin
            || min(front.y, back.y) > max(other.front.y, other.back.y) + margin
            || min(other.front.y, other.back.y) > max(front.y, back.y) + margin { return false }
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
