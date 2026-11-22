import Foundation

public struct Construction: Codable, Equatable {
    public let plot: Plot
    public let replacement: Building?
    public let start: Int
    public let finish: Int
}

public struct City: Codable, Equatable {
    public static let ticksPerSecond = 30
    public static let dayLength = 8 * 60 * ticksPerSecond
    public static let defaultSeed: UInt64 = 0x7661_6C65_7269_6467
    private static let checkpointVersion = 7
    private static let environmentSeedSalt: UInt64 = 0x656E_7669_726F_6E6D

    public internal(set) var map: CityMap
    public internal(set) var vehicles: [Vehicle] = []
    public internal(set) var aviation: Aviation
    public private(set) var construction: Construction?
    public private(set) var tick = 0
    public private(set) var revision = 0
    public private(set) var environmentSeed: UInt64
    // Version 5 stored its journeys in right-hand traffic without a convention field.
    private var savedTrafficConvention: TrafficConvention?
    package var trafficConvention: TrafficConvention { savedTrafficConvention ?? .rightHand }
    var nextVehicle: UInt64 = 0
    private var nextProject = 270
    var random: CityRandom

    public init(seed: UInt64 = Self.defaultSeed) {
        self.init(seed: seed, trafficConvention: .default)
    }

    package init(seed: UInt64 = Self.defaultSeed, trafficConvention: TrafficConvention) {
        var generator = CityRandom(state: seed)
        map = CityMap(random: &generator, generateLayout: seed != Self.defaultSeed)
        random = generator
        environmentSeed = seed ^ Self.environmentSeedSalt
        aviation = Aviation(seed: seed)
        savedTrafficConvention = trafficConvention
        seedTraffic()
    }

    public init(displayUUID: UUID?) {
        let seed = displayUUID?.uuidString.utf8.reduce(Self.defaultSeed) {
            ($0 ^ UInt64($1)) &* 1_099_511_628_211
        }
        self.init(seed: seed ?? Self.defaultSeed)
    }

    public var dayFraction: Double {
        Double((tick % Self.dayLength + Self.dayLength * 10 / 24) % Self.dayLength) / Double(Self.dayLength)
    }

    public var darkness: Double {
        let solar = cos((dayFraction - 0.5) * 2 * .pi)
        return max(0, min(1, (0.22 - solar) * 1.14))
    }

    public var constructionStage: Int {
        guard let construction else { return 0 }
        return min(2, (tick - construction.start) * 3 / (construction.finish - construction.start))
    }

    public mutating func step() {
        tick += 1
        if let project = construction, tick >= project.finish {
            var lot = map[project.plot]
            if let building = project.replacement { lot.building = building }
            else { lot.ground = .road }
            map[project.plot] = lot
            construction = nil
            revision += 1
        } else if construction == nil, tick >= nextProject {
            planDevelopment()
            nextProject = tick + 570 + random.pick(360)
        }
        moveTraffic()
        aviation.step(tick: tick)
    }

    private mutating func planDevelopment() {
        if revision > 0, revision.isMultiple(of: 5) {
            let connections = CityMap.plots.filter { p in
                let lot = map[p]
                guard lot.ground == .grass, lot.building == nil,
                      (5...51).contains(p.x), (6...50).contains(p.y),
                      p.neighbors.filter(map.isRoad).count == 1 else { return false }
                return p.neighbors.filter {
                    map.contains($0) && map[$0].ground == .grass && map[$0].building == nil
                        && map.roadAccess(at: $0) == nil
                }.count >= 2
            }
            if !connections.isEmpty {
                let point = connections[random.pick(connections.count)]
                construction = Construction(plot: point, replacement: nil, start: tick, finish: tick + 210)
                return
            }
        }

        var residents = 0
        var jobs = 0
        for point in CityMap.plots {
            let lot = map[point]
            guard let building = lot.building else { continue }
            switch lot.zone {
            case .homes: residents += building.level * 6
            case .commerce: jobs += building.level * 7
            case .industry: jobs += 16
            case .civic: jobs += 8
            }
        }
        let demand: Zone = jobs * 2 > residents ? .homes : .commerce
        var best: (Plot, Int)?
        for point in CityMap.plots {
            let lot = map[point]
            guard lot.ground == .grass, lot.zone != .civic,
                  map.roadAccess(at: point) != nil,
                  (5...51).contains(point.x), (6...50).contains(point.y),
                  (lot.building?.level ?? 0) < map.capacity(at: point) else { continue }
            let proximity = max(0, 23 - point.distance(to: map.downtown))
            let score = (lot.zone == demand ? 14 : 0) + (lot.building == nil ? 14 : 0)
                + proximity + random.pick(45)
            if best == nil || score > best!.1 { best = (point, score) }
        }
        if let (point, _) = best {
            let current = map[point].building
            let replacement = Building(level: (current?.level ?? 0) + 1, style: current?.style ?? random.pick(120))
            construction = Construction(plot: point, replacement: replacement, start: tick, finish: tick + 180)
        }
    }

    public func checkpoint() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(Checkpoint(version: Self.checkpointVersion, city: self))
    }

    public init?(checkpoint: Data) {
        guard checkpoint.count <= 2_000_000,
              let saved = try? PropertyListDecoder().decode(Checkpoint.self, from: checkpoint) else { return nil }
        self = saved.city
        switch (saved.version, savedTrafficConvention) {
        case (5, nil): savedTrafficConvention = .rightHand
        case (6, .some), (Self.checkpointVersion, .some): break
        default: return nil
        }
        if saved.version < Self.checkpointVersion {
            let hadAirport = map.hasLegacyAirport
            if hadAirport {
                guard let terminal = map.removeLegacyAirport(seed: environmentSeed ^ Self.environmentSeedSalt) else { return nil }
                vehicles.removeAll { $0.origin == terminal || $0.destination == terminal }
            }
            guard aviation.migrateLegacyFlights(hadAirport: hadAirport) else { return nil }
        }
        guard isValid else { return nil }
    }

    private struct Checkpoint: Codable {
        let version: Int
        let city: City
    }

    private var isValid: Bool {
        guard map.isValid, (0..<Int.max / 2).contains(tick),
              (0...tick).contains(revision), nextProject >= tick,
              vehicles.count <= 60, aviation.isValid(tick: tick) else { return false }
        for point in CityMap.plots {
            let lot = map[point]
            guard (0..<120).contains(lot.detail) else { return false }
            if let building = lot.building {
                guard lot.ground == .grass, map.roadAccess(at: point) != nil,
                      (1...map.capacity(at: point)).contains(building.level),
                      (0...Building.riversideTowerStyle).contains(building.style) else { return false }
            }
        }
        if let construction {
            guard map.contains(construction.plot), map[construction.plot].ground == .grass,
                  (0...tick).contains(construction.start),
                  (tick + 1...tick + 210).contains(construction.finish),
                  (180...210).contains(construction.finish - construction.start) else { return false }
            if let replacement = construction.replacement {
                guard map.roadAccess(at: construction.plot) != nil,
                      (1...map.capacity(at: construction.plot)).contains(replacement.level),
                      (0..<120).contains(replacement.style),
                      replacement.level == (map[construction.plot].building?.level ?? 0) + 1 else { return false }
            } else if map[construction.plot].building != nil || map.roadAccess(at: construction.plot) == nil {
                return false
            }
        }
        return Set(vehicles.map(\.id)).count == vehicles.count && vehicles.allSatisfy { vehicle in
            guard vehicle.id < nextVehicle, (4...map.lots.count).contains(vehicle.route.count),
                  (21...29).contains(vehicle.pace), (0..<8).contains(vehicle.color),
                  (0..<(vehicle.route.count - 1) * vehicle.pace).contains(vehicle.progress),
                  map.contains(vehicle.origin), map.contains(vehicle.destination),
                  vehicle.route.allSatisfy(map.isRoad) else { return false }
            return vehicle.origin.distance(to: vehicle.route[0]) == 1 &&
                vehicle.destination.distance(to: vehicle.route.last!) == 1 &&
                zip(vehicle.route, vehicle.route.dropFirst()).allSatisfy { $0.distance(to: $1) == 1 }
        }
    }
}
