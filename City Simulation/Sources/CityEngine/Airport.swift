import Foundation

/// The 14 × 7 design is fitted into a compact 12 × 6 lot site.
/// u follows the runway; v runs from the terminal to the airfield.
public struct Airport: Codable, Equatable, Sendable {
    public static let length = 12
    public static let width = 6
    public static let scale = 6.0 / 7.0
    public static let terminalStyle = 121
    public let origin: Plot
    public let alongY: Bool
    private static let entranceColumn = 6

    public func position(_ u: Double, _ v: Double) -> SIMD2<Double> {
        let x = (u + 0.5) * Self.scale - 0.5
        let y = (v + 0.5) * Self.scale - 0.5
        return SIMD2(Double(origin.x) + (alongY ? y : x), Double(origin.y) + (alongY ? x : y))
    }

    func designPosition(_ point: SIMD2<Double>) -> SIMD2<Double> {
        let x = point.x - Double(origin.x), y = point.y - Double(origin.y)
        let local = alongY ? SIMD2(y, x) : SIMD2(x, y)
        return (local + 0.5) / Self.scale - 0.5
    }

    public func plot(_ u: Int, _ v: Int) -> Plot {
        Plot(origin.x + (alongY ? v : u), origin.y + (alongY ? u : v))
    }

    public func local(_ plot: Plot) -> (u: Int, v: Int) {
        let x = plot.x - origin.x, y = plot.y - origin.y
        return alongY ? (y, x) : (x, y)
    }

    public var terminal: Plot { plot(Self.entranceColumn, 0) }
    public var entrance: Plot { plot(Self.entranceColumn, -1) }
    package static let entranceCenter = (Double(entranceColumn) + 0.5) / scale - 0.5

    public var tower: Plot { designPlot(Self.towerCenter.x, Self.towerCenter.y) }
    public var hangars: [Plot] { Self.hangarCenters.map { designPlot($0.x, $0.y) } }

    package func anchor(for surface: Surface) -> Plot {
        designPlot((surface.u.lowerBound + surface.u.upperBound) / 2,
                   (surface.v.lowerBound + surface.v.upperBound) / 2)
    }

    private func designPlot(_ u: Double, _ v: Double) -> Plot {
        let point = position(u, v)
        return Plot(Int(point.x.rounded()), Int(point.y.rounded()))
    }

    public func contains(_ point: Plot) -> Bool {
        let p = local(point)
        return (0..<Self.length).contains(p.u) && (0..<Self.width).contains(p.v)
    }

    public func isApproach(_ point: Plot) -> Bool {
        let p = local(point)
        let u = (Double(p.u) + 0.5) / Self.scale - 0.5
        let runway = (Self.runwayCenter + 0.5) * Self.scale - 0.5
        return abs(Double(p.v) - runway) <= 1 && ((u >= -12 && u < 0) || (u >= 14 && u <= 26))
    }

    var plots: [Plot] {
        (0..<Self.length).flatMap { u in (0..<Self.width).map { plot(u, $0) } }
    }

    var isValid: Bool {
        (1..<CityMap.side - Self.length).contains(alongY ? origin.y : origin.x) &&
        (1..<CityMap.side - Self.width).contains(alongY ? origin.x : origin.y)
    }
}

extension CityMap {
    /// Reserve land before buildings are populated. Prefer sites that can reuse a street
    /// at the forecourt and keep the rest of the city connected through existing streets.
    mutating func planAirport(random: inout CityRandom, optional: Bool) {
        if optional && random.pick(4) != 0 { return }
        var best: (airport: Airport, newRoads: [Plot], score: Int)?
        for alongY in [false, true] {
            for y in 5...43 {
                for x in 5...43 {
                    let candidate = Airport(origin: Plot(x, y), alongY: alongY)
                    guard candidate.isValid else { continue }
                    let middle = candidate.plot(Airport.length / 2, Airport.width / 2)
                    guard middle.distance(to: downtown) >= 20 else { continue }
                    guard let newRoads = airportAccessRoad(for: candidate) else { continue }
                    let footprint = candidate.plots
                    guard footprint.allSatisfy({ point in
                        let lot = self[point]
                        return [.grass, .road].contains(lot.ground) && lot.building == nil &&
                            landscape(at: point).ground == .grass && point.distance(to: downtown) >= 11
                    }) else { continue }
                    let displaced = footprint.filter(isRoad)
                    // Prefer the outskirts within the wallpaper crop, without sacrificing riverbanks or parks.
                    let visible = footprint.filter {
                        let x = 320 + ($0.x - $0.y - Self.center.x + Self.center.y) * 16
                        let y = 210 + ($0.x + $0.y - Self.center.x - Self.center.y) * 8
                        return (16..<624).contains(x) && (16..<344).contains(y)
                    }.count
                    let score = -visible * 4 + abs(middle.distance(to: downtown) - 24) +
                        displaced.count * 5 + newRoads.count * 16 + random.pick(12)
                    guard best == nil || score < best!.score,
                          keepsRoadsConnected(around: candidate, removing: displaced) else { continue }
                    best = (candidate, newRoads, score)
                }
            }
        }
        guard let best else { return }
        let selected = best.airport
        airport = selected
        for point in best.newRoads {
            var lot = self[point]
            lot.ground = .road
            self[point] = lot
        }
        for point in selected.plots {
            var lot = self[point]
            lot.ground = .airport
            lot.zone = .civic
            self[point] = lot
        }
        var terminal = self[selected.terminal]
        terminal.ground = .grass
        terminal.building = Building(level: 1, style: Airport.terminalStyle)
        self[selected.terminal] = terminal
    }

    /// At most two new lots in a straight spur. An existing street at the entrance
    /// is already a connection. Adjacent streets along a new spur would form extra
    /// junctions or a parallel strip of pavement, so leave those sites to the city.
    func airportAccessRoad(for airport: Airport) -> [Plot]? {
        let column = airport.local(airport.entrance).u
        var newRoads: [Plot] = []
        for v in [-1, -2, -3] {
            let point = airport.plot(column, v)
            guard contains(point), landscape(at: point).ground == .grass else { return nil }
            if self[point].ground == .road { return newRoads }
            guard v != -3, self[point].ground == .grass, self[point].building == nil,
                  !isRoad(airport.plot(column - 1, v)), !isRoad(airport.plot(column + 1, v)) else { return nil }
            newRoads.append(point)
        }
        return nil
    }

    private func keepsRoadsConnected(around airport: Airport, removing roads: [Plot]) -> Bool {
        // Every component split by the removal must touch a displaced street.
        // Check the surviving neighbours without using the footprint or the new spur.
        var remaining = Set(roads.flatMap(\.neighbors).filter { !airport.contains($0) && isRoad($0) })
        guard let start = remaining.popFirst() else { return true }
        var visited: Set<Plot> = [start]
        var queue = [start]
        var cursor = 0
        while !remaining.isEmpty && cursor < queue.count {
            let point = queue[cursor]
            cursor += 1
            for next in point.neighbors where !airport.contains(next) && isRoad(next) && visited.insert(next).inserted {
                remaining.remove(next)
                queue.append(next)
            }
        }
        return remaining.isEmpty
    }
}
