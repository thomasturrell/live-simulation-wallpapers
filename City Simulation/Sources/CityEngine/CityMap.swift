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
    case grass, water, road, bridge, park, promenade
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
    public static let downtown = Plot(25, 23)
    public static let plots = (0..<side * side).map { Plot($0 % side, $0 / side) }
    private(set) var lots: [Lot]

    init(random: inout CityRandom) {
        lots = Self.plots.map { point in
            var lot = Self.landscape(at: point)
            lot.detail = random.pick(120)
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
        for point in Self.plots {
            var lot = self[point]
            guard lot.ground == .grass, roadAccess(at: point) != nil,
                  (6...50).contains(point.x), (7...49).contains(point.y) else { continue }
            if [Plot(23, 24), Plot(17, 24), Plot(39, 18)].contains(point) {
                lot.zone = .civic
                lot.building = Building(level: 1, style: point.x)
            } else if point == Plot(28, 24) {
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

    public static func landscape(at point: Plot) -> Lot {
        let bank = 31 + (point.y >= 35 ? 1 : 0) - (point.y < 13 ? 1 : 0)
        let detail = Int(UInt(bitPattern: (point.x &* 15607) ^ (point.y &* 8821)) % 120)
        if (bank...bank + 4).contains(point.x) { return Lot(ground: .water, detail: detail) }
        if point.x == bank - 1 || point.x == bank + 5 { return Lot(ground: .promenade, detail: detail) }
        return Lot(detail: detail)
    }

    public func contains(_ plot: Plot) -> Bool {
        (0..<Self.side).contains(plot.x) && (0..<Self.side).contains(plot.y)
    }

    public subscript(_ plot: Plot) -> Lot {
        get { contains(plot) ? lots[plot.y * Self.side + plot.x] : Self.landscape(at: plot) }
        set { lots[plot.y * Self.side + plot.x] = newValue }
    }

    public func isRoad(_ point: Plot) -> Bool { contains(point) && self[point].ground.carriesTraffic }
    public func roadAccess(at point: Plot) -> Plot? {
        point.neighbors.first { contains($0) && self[$0].ground == .road }
    }

    public func capacity(at point: Plot) -> Int {
        switch self[point].zone {
        case .civic, .industry: return 1
        case .homes: return point.distance(to: Self.downtown) < 18 ? 3 : 2
        case .commerce:
            let distance = point.distance(to: Self.downtown)
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
