import Foundation

public struct Plot: Codable, Hashable, Sendable {
    public let x: Int
    public let y: Int

    public init(_ x: Int, _ y: Int) { self.x = x; self.y = y }

    public var neighbors: [Plot] {
        [Plot(x + 1, y), Plot(x, y + 1), Plot(x - 1, y), Plot(x, y - 1)]
    }

    public func distance(to other: Plot) -> Int { abs(x - other.x) + abs(y - other.y) }
}

public enum Ground: UInt8, Codable, Sendable {
    case grass, water, road, bridge, park, promenade, airport
    public var carriesTraffic: Bool { self == .road || self == .bridge }
}

public enum Zone: UInt8, Codable, Sendable { case homes, commerce, industry, civic }

public struct Building: Codable, Equatable, Sendable {
    public let level: Int
    public let style: Int
    public static let riversideTowerStyle = 120
}

public struct Lot: Codable, Equatable, Sendable {
    public var ground: Ground = .grass
    public var zone: Zone = .homes
    public var building: Building?
    public var detail = 0
}

struct CityRandom: Codable, Equatable {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }

    mutating func pick(_ count: Int) -> Int { Int(next() % UInt64(count)) }
}

public struct CityMap: Codable, Equatable {
    public static let side = 56
    public static let center = Plot(27, 26)
    public static let plots = (0..<side * side).map { Plot($0 % side, $0 / side) }
    let downtown: Plot
    private let river: CityRiver
    private(set) var lots: [Lot]
    public internal(set) var airport: Airport?

    init(random: inout CityRandom, generateLayout: Bool) {
        let layout = generateLayout ? CityLayout(random: &random) : nil
        river = layout?.river ?? .defaultRiver
        downtown = layout?.downtown ?? Plot(25, 23)
        lots = Self.plots.map { point in
            var lot = layout?.lot(at: point) ?? Self.defaultLot(at: point)
            lot.detail = random.pick(120)
            return lot
        }
        planAirport(random: &random, optional: generateLayout)
        let frontage = Self.plots.filter {
            (6...50).contains($0.x) && (7...49).contains($0.y) &&
                self[$0].ground == .grass && roadAccess(at: $0) != nil &&
                airport?.isApproach($0) != true && $0 != airport?.terminal
        }
        let civic: [Plot]
        if generateLayout {
            civic = frontage.min { $0.distance(to: downtown) < $1.distance(to: downtown) }.map { [$0] } ?? []
        } else {
            civic = [Plot(23, 24), Plot(17, 24), Plot(39, 18)]
        }
        for point in frontage {
            var lot = self[point]
            if civic.contains(point) {
                lot.zone = .civic
                lot.building = Building(level: 1, style: point.x)
            } else if !generateLayout && point == Plot(28, 24) {
                lot.building = Building(level: 5, style: Building.riversideTowerStyle)
            } else {
                let occupancy = lot.zone == .commerce ? 91 : 84
                if random.pick(100) < occupancy {
                    let limit = capacity(at: point)
                    let level = lot.zone == .commerce ? max(1, limit - random.pick(3)) : 1 + random.pick(limit)
                    lot.building = Building(level: level, style: random.pick(120))
                }
            }
            self[point] = lot
        }
    }

    private static func defaultLot(at point: Plot) -> Lot {
        var lot = Lot(ground: CityRiver.defaultRiver.ground(at: point))
        let x = point.x, y = point.y
        let acrossRiver = [7, 13, 19, 25, 31, 37, 43, 49].contains(y)
        let crossing = [19, 31, 43].contains(y)
        let avenue = [6, 12, 18, 24, 29, 38, 44, 50].contains(x)
        if lot.ground == .water {
            if crossing && (6...50).contains(x) { lot.ground = .bridge }
        } else if (avenue && (7...49).contains(y)) ||
                    (acrossRiver && (6...50).contains(x) && (lot.ground != .promenade || crossing)) {
            lot.ground = .road
        }
        if x >= 38 && (26...42).contains(y) {
            lot.zone = .industry
        } else if ((19...30).contains(x) && (15...29).contains(y)) ||
                    ((38...45).contains(x) && (15...22).contains(y)) {
            lot.zone = .commerce
        }
        if lot.ground == .grass {
            let park = ((20...23).contains(x) && (20...23).contains(y)) ||
                ((25...28).contains(x) && (32...35).contains(y)) ||
                ((13...16).contains(x) && (14...17).contains(y)) ||
                ((39...42).contains(x) && (8...11).contains(y))
            if park { lot.ground = .park }
        }
        return lot
    }

    var isValid: Bool {
        guard lots.count == Self.side * Self.side, contains(downtown), river.isValid else { return false }
        if let airport {
            guard airport.isValid, airport.perimeter.allSatisfy(isRoad),
                  self[airport.terminal].building == Building(level: 1, style: Airport.terminalStyle),
                  self[airport.terminal].ground == .grass,
                  self[airport.terminal].zone == .civic else { return false }
            return Self.plots.allSatisfy {
                (self[$0].ground == .airport) == (airport.contains($0) && $0 != airport.terminal)
            }
        }
        return !lots.contains { $0.ground == .airport || $0.building?.style == Airport.terminalStyle }
    }

    public func landscape(at point: Plot) -> Lot {
        let detail = Int(UInt(bitPattern: (point.x &* 15607) ^ (point.y &* 8821)) % 120)
        return Lot(ground: river.ground(at: point), detail: detail)
    }

    public func contains(_ plot: Plot) -> Bool {
        (0..<Self.side).contains(plot.x) && (0..<Self.side).contains(plot.y)
    }

    public subscript(_ plot: Plot) -> Lot {
        get { contains(plot) ? lots[plot.y * Self.side + plot.x] : landscape(at: plot) }
        set { lots[plot.y * Self.side + plot.x] = newValue }
    }

    public func isRoad(_ point: Plot) -> Bool { contains(point) && self[point].ground.carriesTraffic }
    public func roadAccess(at point: Plot) -> Plot? {
        point.neighbors.first { contains($0) && self[$0].ground == .road }
    }

    public func capacity(at point: Plot) -> Int {
        switch self[point].zone {
        case .civic, .industry: return 1
        case .homes: return point.distance(to: downtown) < 18 ? 3 : 2
        case .commerce:
            let distance = point.distance(to: downtown)
            let atJunction = point.neighbors.filter(isRoad).contains { access in
                access.neighbors.contains { isRoad($0) && $0.neighbors.filter(isRoad).count >= 3 }
            }
            return distance < 8 ? (atJunction ? 5 : 4) : distance < 17 ? 3 : 2
        }
    }

    public func route(from start: Plot, to end: Plot) -> [Plot]? {
        guard isRoad(start), isRoad(end) else { return nil }
        func index(_ plot: Plot) -> Int { plot.x + plot.y * Self.side }
        var previous = [Plot?](repeating: nil, count: lots.count)
        var queue = [start]
        previous[index(start)] = start
        var next = 0
        while next < queue.count {
            let point = queue[next]
            if point == end {
                var path = [end]
                while let parent = previous[index(path.last!)], parent != path.last! { path.append(parent) }
                return path.reversed()
            }
            for neighbor in point.neighbors where isRoad(neighbor) && previous[index(neighbor)] == nil {
                previous[index(neighbor)] = point
                queue.append(neighbor)
            }
            next += 1
        }
        return nil
    }
}
