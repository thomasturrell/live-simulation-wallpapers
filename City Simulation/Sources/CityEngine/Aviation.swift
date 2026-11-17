import Foundation

public struct Aircraft: Codable, Equatable {
    public enum Phase: UInt8, Codable, CaseIterable {
        case approach, landing, taxiIn, parked, pushback, taxiOut, holdingShort, lineUp, takeoff, climb, overflight
    }

    public let id: UInt64
    public let livery: Int
    public internal(set) var phase: Phase = .approach
    public internal(set) var elapsed = 0
    let standTime: Int
    let lane: Int
    let reverse: Bool
    let alongY: Bool

    public var duration: Int {
        let seconds: Int
        switch phase {
        case .approach: seconds = 22
        case .landing: seconds = 13
        case .taxiIn: seconds = 25
        case .parked: return standTime
        case .pushback: seconds = 6
        case .taxiOut: seconds = 19
        case .holdingShort: seconds = 4
        case .lineUp: seconds = 6
        case .takeoff: seconds = 12
        case .climb: seconds = 24
        case .overflight: seconds = 65
        }
        return seconds * City.ticksPerSecond
    }

    public struct Pose {
        public let x: Double, y: Double
        public let dx: Double, dy: Double
        /// Height above the ground in virtual pixels, shared by every renderer size.
        public let altitude: Double
        public let bank: Double
        public let gear: Bool
    }

    public func pose(at airport: Airport?) -> Pose {
        let t = Double(elapsed) / Double(duration)
        let sample = motion(t)
        var direction = sample.tangent
        if phase == .pushback { direction = -direction }
        let magnitude = hypot(direction.x, direction.y)
        if magnitude > 0 { direction /= magnitude }
        else { direction = SIMD2(1, 0) }

        let overflight = phase == .overflight
        let swapped = overflight ? alongY : airport?.alongY == true
        let reference = overflight ? SIMD2(Double(CityMap.center.x), Double(CityMap.center.y)) :
            SIMD2(Double(airport?.origin.x ?? 0), Double(airport?.origin.y ?? 0))
        let point = reference + (swapped ? SIMD2(sample.point.y, sample.point.x) : sample.point)
        let heading = swapped ? SIMD2(direction.y, direction.x) : direction
        let bank = sample.altitude > 10 ? max(-0.22, min(0.22, sample.bend * 0.00008)) : 0
        return Pose(x: point.x, y: point.y, dx: heading.x, dy: heading.y, altitude: sample.altitude,
                    bank: swapped ? -bank : bank, gear: phase != .overflight && (phase != .climb || t < 0.18))
    }

    private struct Motion {
        let point: SIMD2<Double>
        let tangent: SIMD2<Double>
        let altitude: Double
        let bend: Double
    }

    private func motion(_ t: Double) -> Motion {
        func p(_ u: Double, _ v: Double) -> SIMD2<Double> { SIMD2(u, v) }
        func sample(_ point: SIMD2<Double>, _ tangent: SIMD2<Double>, altitude: Double = 0, bend: Double = 0) -> Motion {
            Motion(point: point, tangent: tangent, altitude: altitude, bend: bend)
        }
        func cubic(_ a: SIMD2<Double>, _ b: SIMD2<Double>, _ c: SIMD2<Double>, _ d: SIMD2<Double>, _ t: Double,
                   altitude: Double = 0) -> Motion {
            let s = 1 - t
            let point = a * (s * s * s) + b * (3 * s * s * t) + c * (3 * s * t * t) + d * (t * t * t)
            // Exact derivatives keep a straight taxiway's heading constant. Subtracting
            // nearby positions amplified floating-point noise and made half-pixel details flicker.
            let ab: SIMD2<Double> = b - a
            let bc: SIMD2<Double> = c - b
            let cd: SIMD2<Double> = d - c
            let firstStart: SIMD2<Double> = ab * (s * s)
            let firstMiddle: SIMD2<Double> = bc * (2 * s * t)
            let firstEnd: SIMD2<Double> = cd * (t * t)
            let first: SIMD2<Double> = (firstStart + firstMiddle + firstEnd) * 3.0
            let secondStart: SIMD2<Double> = (bc - ab) * s
            let secondEnd: SIMD2<Double> = (cd - bc) * t
            let second: SIMD2<Double> = (secondStart + secondEnd) * 6.0
            var tangent = first
            if hypot(tangent.x, tangent.y) < 1e-10 {
                // At a stop, keep the limiting direction of travel instead of an arbitrary heading.
                tangent = t < 0.5 ? second : -second
                if hypot(tangent.x, tangent.y) < 1e-10 { tangent = d - a }
            }
            return sample(point, tangent, altitude: altitude, bend: first.x * second.y - first.y * second.x)
        }
        switch phase {
        case .approach:
            return cubic(p(-30, 8), p(-19.6, 5), p(-9.2, 5), p(1.2, 5), t, altitude: 150 * (1 - t))
        case .landing:
            // Integrating a steadily falling speed avoids a stop or a jump at touchdown.
            let u = 1.2 + 13 * (1.42 * t - 0.62 * t * t)
            return sample(p(u, 5), p(1, 0))
        case .taxiIn:
            let seconds = t * 25
            if seconds < 7 {
                return cubic(p(11.6, 5), p(12.02, 5), p(12.552, 3), p(11.6, 3), seconds / 7)
            }
            if seconds < 19 { return sample(p(11.6 - (seconds - 7) * 4.9 / 12, 3), p(-1, 0)) }
            return cubic(p(6.7, 3), p(6, 3), p(6, 1.65), p(6, 1.65), (seconds - 19) / 6)
        case .parked: return sample(p(6, 1.65), p(0, -1))
        case .pushback:
            let eased = t * t * (3 - 2 * t)
            return cubic(p(6, 1.65), p(6, 2.5), p(6.6, 3), p(7, 3), eased)
        case .taxiOut:
            let seconds = t * 19
            if seconds < 13 {
                return cubic(p(7, 3), p(7, 3), p(4.38, 3), p(2.3, 3), seconds / 13)
            }
            return cubic(p(2.3, 3), p(1.2, 3), p(1.2, 4.1), p(1.2, 4.1), (seconds - 13) / 6)
        case .holdingShort: return sample(p(1.2, 4.1), p(0, 1))
        case .lineUp:
            return cubic(p(1.2, 4.1), p(1.2, 4.15), p(1.8, 5), p(2, 5), t)
        case .takeoff:
            return sample(p(2 + 1.2 * t + 8.8 * t * t, 5), p(1, 0),
                          altitude: t > 0.65 ? 9 * pow((t - 0.65) / 0.35, 1.5) : 0)
        case .climb:
            return cubic(p(12, 5), p(24.53, 5), p(37, 5), p(50, 9), t, altitude: 9 + 156 * t)
        case .overflight:
            let altitude = 86.0
            // Height moves the sprite up on screen. Shift both ground axes equally to
            // compensate, keeping the airborne route over the visible heart of the city.
            let offset = altitude / 16
            let speed = reverse ? -84.0 : 84.0
            return sample(p((reverse ? 42 - 84 * t : -42 + 84 * t) + offset,
                            Double(lane) * 0.25 + sin(t * .pi) + offset),
                          p(speed, .pi * cos(t * .pi)), altitude: altitude,
                          bend: speed * -Double.pi * .pi * sin(t * .pi))
        }
    }

    var isValid: Bool {
        (0..<4).contains(livery) && (45 * City.ticksPerSecond...95 * City.ticksPerSecond).contains(standTime) &&
        (-8...8).contains(lane) && (0..<duration).contains(elapsed)
    }
}

/// Uses a separate seeded random stream for flight schedules and liveries.
public struct Aviation: Codable, Equatable {
    public internal(set) var aircraft: [Aircraft] = []
    var nextArrival: Int
    var nextOverflight: Int
    private var nextID: UInt64 = 0
    private var random: CityRandom

    init(seed: UInt64, tick: Int = 0) {
        var random = CityRandom(state: seed ^ 0x6169_7270_6F72_7473)
        nextArrival = tick + (24 + random.pick(19)) * City.ticksPerSecond
        nextOverflight = tick + (45 + random.pick(30)) * City.ticksPerSecond
        self.random = random
    }

    enum Event { case passengersArrive, passengersLeave }

    mutating func step(tick: Int, darkness: Double, airport: Airport?) -> [Event] {
        var events: [Event] = []
        for i in aircraft.indices {
            aircraft[i].elapsed += 1
            guard aircraft[i].elapsed >= aircraft[i].duration else { continue }
            switch aircraft[i].phase {
            case .climb:
                nextArrival = tick + (45 + random.pick(65) + (darkness > 0.65 ? 75 : 0)) * City.ticksPerSecond
            case .overflight:
                nextOverflight = tick + (85 + random.pick(95)) * City.ticksPerSecond
            default:
                aircraft[i].phase = Aircraft.Phase(rawValue: aircraft[i].phase.rawValue + 1)!
                aircraft[i].elapsed = 0
                if aircraft[i].phase == .parked { events.append(.passengersLeave) }
                if aircraft[i].phase == .taxiIn { events.append(.passengersArrive) }
            }
        }
        aircraft.removeAll { $0.elapsed >= $0.duration }
        if airport != nil, tick >= nextArrival, !aircraft.contains(where: { $0.phase != .overflight }) {
            aircraft.append(makeAircraft(phase: .approach))
        }
        if tick >= nextOverflight, !aircraft.contains(where: { $0.phase == .overflight }) {
            aircraft.append(makeAircraft(phase: .overflight))
        }
        return events
    }

    private mutating func makeAircraft(phase: Aircraft.Phase) -> Aircraft {
        let flight = Aircraft(id: nextID, livery: random.pick(4), phase: phase,
                              standTime: (45 + random.pick(51)) * City.ticksPerSecond,
                              lane: random.pick(17) - 8, reverse: random.pick(2) == 0, alongY: random.pick(2) == 0)
        nextID &+= 1
        return flight
    }

    func isValid(tick: Int, airport: Airport?) -> Bool {
        aircraft.count <= 2 && aircraft.allSatisfy { $0.isValid && $0.id < nextID } &&
        Set(aircraft.map(\.id)).count == aircraft.count &&
        aircraft.filter { $0.phase == .overflight }.count <= 1 &&
        aircraft.filter { $0.phase != .overflight }.count <= (airport == nil ? 0 : 1) &&
        (0...tick + 200 * City.ticksPerSecond).contains(nextArrival) &&
        (0...tick + 200 * City.ticksPerSecond).contains(nextOverflight)
    }
}
