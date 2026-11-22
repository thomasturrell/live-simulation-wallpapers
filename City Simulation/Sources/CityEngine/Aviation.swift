import Foundation

public struct Aircraft: Codable, Equatable {
    // Checkpoint versions 5 and 6 stored the overflight as phase 10.
    fileprivate static let legacyOverflightPhase: UInt8 = 10
    fileprivate var phase: UInt8?

    public let id: UInt64
    public let livery: Int
    public internal(set) var elapsed = 0
    let lane: Int
    let reverse: Bool
    let alongY: Bool

    init(id: UInt64, livery: Int, lane: Int, reverse: Bool, alongY: Bool) {
        self.id = id
        self.livery = livery
        self.lane = lane
        self.reverse = reverse
        self.alongY = alongY
    }

    public var duration: Int { 65 * City.ticksPerSecond }

    public struct Pose {
        public let x: Double, y: Double
        public let dx: Double, dy: Double
        /// Height above the ground in virtual pixels, shared by every renderer size.
        public let altitude: Double
        public let bank: Double
    }

    public func pose() -> Pose {
        let t = Double(elapsed) / Double(duration)
        let altitude = 86.0
        // Height moves the sprite up on screen. Shift both ground axes equally to
        // compensate, keeping the airborne route over the visible heart of the city.
        let offset = altitude / 16
        let speed = reverse ? -84.0 : 84.0
        let along = (reverse ? 42 - 84 * t : -42 + 84 * t) + offset
        let across = Double(lane) * 0.25 + sin(t * .pi) + offset
        let drift = Double.pi * cos(t * .pi)
        let direction = SIMD2(speed, drift) / hypot(speed, drift)
        let bend = speed * -Double.pi * .pi * sin(t * .pi)
        let bank = max(-0.22, min(0.22, bend * 0.00008))
        return Pose(x: Double(CityMap.center.x) + (alongY ? across : along),
                    y: Double(CityMap.center.y) + (alongY ? along : across),
                    dx: alongY ? direction.y : direction.x,
                    dy: alongY ? direction.x : direction.y,
                    altitude: altitude, bank: alongY ? -bank : bank)
    }

    var isValid: Bool {
        phase == nil && (0..<4).contains(livery) &&
            (-8...8).contains(lane) && (0..<duration).contains(elapsed)
    }
}

/// Uses a separate seeded random stream for flight schedules and liveries.
public struct Aviation: Codable, Equatable {
    public internal(set) var aircraft: [Aircraft] = []
    var nextOverflight: Int
    private var nextID: UInt64 = 0
    private var random: CityRandom

    init(seed: UInt64, tick: Int = 0) {
        var random = CityRandom(state: seed ^ 0x6169_7270_6F72_7473)
        _ = random.next() // The former airport arrival draw preceded the first overflight.
        nextOverflight = tick + (45 + random.pick(30)) * City.ticksPerSecond
        self.random = random
    }

    mutating func step(tick: Int) {
        if !aircraft.isEmpty {
            aircraft[0].elapsed += 1
            if aircraft[0].elapsed >= aircraft[0].duration {
                aircraft.removeAll()
                nextOverflight = tick + (85 + random.pick(95)) * City.ticksPerSecond
            }
        } else if tick >= nextOverflight {
            let livery = random.pick(4)
            _ = random.next() // Preserve the overflight sequence from checkpoints that included stand times.
            aircraft.append(Aircraft(id: nextID, livery: livery, lane: random.pick(17) - 8,
                                     reverse: random.pick(2) == 0, alongY: random.pick(2) == 0))
            nextID &+= 1
        }
    }

    mutating func migrateLegacyFlights(hadAirport: Bool) -> Bool {
        let airportFlights = aircraft.compactMap(\.phase).filter { $0 < Aircraft.legacyOverflightPhase }
        guard airportFlights.count <= (hadAirport ? 1 : 0) else { return false }
        aircraft.removeAll { ($0.phase ?? Aircraft.legacyOverflightPhase) < Aircraft.legacyOverflightPhase }
        for index in aircraft.indices where aircraft[index].phase == Aircraft.legacyOverflightPhase {
            aircraft[index].phase = nil
        }
        return true
    }

    func isValid(tick: Int) -> Bool {
        aircraft.count <= 1 && aircraft.allSatisfy { $0.isValid && $0.id < nextID } &&
            (0...tick + 200 * City.ticksPerSecond).contains(nextOverflight)
    }
}
