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

    public func position(_ u: Double, _ v: Double) -> SIMD2<Double> {
        let x = (u + 0.5) * Self.scale - 0.5
        let y = (v + 0.5) * Self.scale - 0.5
        return SIMD2(Double(origin.x) + (alongY ? y : x), Double(origin.y) + (alongY ? x : y))
    }

    public func designPlot(_ u: Int, _ v: Int) -> Plot {
        let point = position(Double(u), Double(v))
        return Plot(Int(point.x.rounded()), Int(point.y.rounded()))
    }

    public func plot(_ u: Int, _ v: Int) -> Plot {
        Plot(origin.x + (alongY ? v : u), origin.y + (alongY ? u : v))
    }

    public func local(_ plot: Plot) -> (u: Int, v: Int) {
        let x = plot.x - origin.x, y = plot.y - origin.y
        return alongY ? (y, x) : (x, y)
    }

    public var terminal: Plot { plot(6, 0) }
    public var tower: Plot { plot(9, 0) }
    public var hangars: [Plot] { [plot(2, 0), plot(11, 0)] }

    public func contains(_ point: Plot) -> Bool {
        let p = local(point)
        return (0..<Self.length).contains(p.u) && (0..<Self.width).contains(p.v)
    }

    public func isApproach(_ point: Plot) -> Bool {
        let p = local(point)
        let u = (Double(p.u) + 0.5) / Self.scale - 0.5
        let runway = 5.5 * Self.scale - 0.5
        return abs(Double(p.v) - runway) <= 1 && ((u >= -12 && u < 0) || (u >= 14 && u <= 26))
    }

    var plots: [Plot] {
        (0..<Self.length).flatMap { u in (0..<Self.width).map { plot(u, $0) } }
    }

    var perimeter: [Plot] {
        (-1...Self.length).flatMap { u in
            (-1...Self.width).compactMap { v in
                u == -1 || u == Self.length || v == -1 || v == Self.width ? plot(u, v) : nil
            }
        }
    }

    var isValid: Bool {
        (1..<CityMap.side - Self.length).contains(alongY ? origin.y : origin.x) &&
        (1..<CityMap.side - Self.width).contains(alongY ? origin.x : origin.y)
    }
}

extension CityMap {
    /// Reserve land before buildings are populated. A perimeter road reconnects every street
    /// reaching the site, rather than leaving severed roads or cars crossing the runway.
    mutating func planAirport(random: inout CityRandom, optional: Bool) {
        if optional && random.pick(4) != 0 { return }
        var best: (airport: Airport, score: Int)?
        for alongY in [false, true] {
            for y in stride(from: 5, through: 43, by: 2) {
                for x in stride(from: 5, through: 43, by: 2) {
                    let candidate = Airport(origin: Plot(x, y), alongY: alongY)
                    guard candidate.isValid else { continue }
                    let middle = candidate.plot(Airport.length / 2, Airport.width / 2)
                    guard middle.distance(to: downtown) >= 20 else { continue }
                    let footprint = candidate.plots + candidate.perimeter
                    guard footprint.allSatisfy({
                        contains($0) && [.grass, .road].contains(self[$0].ground) &&
                        $0.distance(to: downtown) >= 11
                    }), candidate.perimeter.contains(where: isRoad) else { continue }
                    // Prefer the outskirts within the wallpaper crop, without sacrificing riverbanks or parks.
                    let visible = candidate.plots.filter {
                        let x = 320 + ($0.x - $0.y - Self.center.x + Self.center.y) * 16
                        let y = 210 + ($0.x + $0.y - Self.center.x - Self.center.y) * 8
                        return (16..<624).contains(x) && (16..<344).contains(y)
                    }.count
                    let score = -visible * 4 + abs(middle.distance(to: downtown) - 24) + random.pick(12)
                    if best == nil || score < best!.score { best = (candidate, score) }
                }
            }
        }
        guard let selected = best?.airport else { return }
        airport = selected
        for point in selected.perimeter {
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

}
