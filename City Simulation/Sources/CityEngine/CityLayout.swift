struct CityRiver: Codable, Equatable {
    let banks: [Int]
    let width: Int

    static let defaultRiver = CityRiver(banks: (0..<CityMap.side).map {
        31 + ($0 >= 35 ? 1 : 0) - ($0 < 13 ? 1 : 0)
    }, width: 5)

    init(banks: [Int], width: Int) {
        self.banks = banks
        self.width = width
    }

    init(random: inout CityRandom, districtGrids: Bool) {
        let center = [16, 25, 34][random.pick(3)] + random.pick(3) - 1
        let direction = random.pick(2) == 0 ? -1 : 1
        let bend = direction * (districtGrids ? 4 + random.pick(5) : 2 + random.pick(4))
        let anchors = [center + bend, center + bend / 2, center, center - bend / 2,
                       center + (random.pick(2) == 0 ? bend : -bend)].map { min(37, max(12, $0)) }
        // Interpolate between bends at tile resolution so the channel stays continuous.
        banks = (0..<CityMap.side).map { y in
            let section = y / 14
            let offset = y % 14
            return anchors[section] + (anchors[section + 1] - anchors[section]) * offset / 14
        }
        width = 4 + random.pick(4)
    }

    var isValid: Bool {
        (4...7).contains(width) && banks.count == CityMap.side && banks.allSatisfy { (12...37).contains($0) }
    }

    func bank(at y: Int) -> Int { banks[min(CityMap.side - 1, max(0, y))] }

    func ground(at point: Plot) -> Ground {
        let west = bank(at: point.y)
        let east = west + width
        if (west..<east).contains(point.x) { return .water }
        if point.x == west - 1 || point.x == east { return .promenade }
        return .grass
    }
}

struct CityLayout {
    let river: CityRiver
    let downtown: Plot
    private let industry: Plot
    private let parkCenters: [Plot]
    private var roads: Set<Plot> = []

    init(random: inout CityRandom) {
        let districtGrids = random.pick(2) == 0
        let river = CityRiver(random: &random, districtGrids: districtGrids)
        self.river = river

        let rows = 7...49
        let banks = rows.map(river.bank(at:))
        // Each bank has a collector beyond all the bends. Every grid and bridge joins a collector.
        let west = banks.min()! - 3
        let east = banks.max()! + river.width + 2
        let gridRows = Array(stride(from: 7 + random.pick(3), through: 49, by: 5 + random.pick(2)))
        let crossings = districtGrids
            ? [15 + random.pick(7), 27 + random.pick(8), 39 + random.pick(7)]
            : [gridRows[2], gridRows[4], gridRows[6]]
        let centerOnWest = abs(west - CityMap.center.x) <= abs(east - CityMap.center.x)
        downtown = Plot(centerOnWest ? west - 2 : east + 2, crossings[1] - 3)
        industry = Plot(centerOnWest ? east + 2 : west - 2, crossings[2] - 2)
        parkCenters = [Plot(downtown.x, downtown.y - 7), Plot(industry.x, industry.y - 8)]

        for y in rows {
            roads.insert(Plot(west, y))
            roads.insert(Plot(east, y))
        }
        for y in crossings {
            for x in west...east { roads.insert(Plot(x, y)) }
        }
        let spacing = 4 + random.pick(3)
        for (spine, direction) in [(west, -1), (east, 1)] {
            let edge = direction < 0 ? 6 : 50
            if districtGrids {
                let mid = (direction < 0 ? 19 : 25) + random.pick(5)
                for district in [(8 + random.pick(4))...mid, (mid + 7)...(46 + random.pick(4))] {
                    let outer = edge - direction * min(random.pick(5), abs(edge - spine) - 3)
                    let streets = Array(stride(from: district.lowerBound, through: district.upperBound,
                                              by: 4 + random.pick(3)))
                    addGrid(from: spine, to: outer, rows: streets, spacing: 4 + random.pick(3))
                }
            } else {
                addGrid(from: spine, to: edge, rows: gridRows, spacing: spacing)
            }
        }
    }

    private mutating func addGrid(from spine: Int, to edge: Int, rows: [Int], spacing: Int) {
        let direction = edge < spine ? -1 : 1
        let avenues = stride(from: spine, to: edge, by: spacing * direction).filter { abs($0 - edge) >= 3 } + [edge]
        for x in avenues {
            for y in rows.first!...rows.last! { roads.insert(Plot(x, y)) }
        }
        for y in rows {
            let bank = river.bank(at: y)
            let waterfront = direction < 0 ? bank - 2 : bank + river.width + 1
            for x in min(edge, waterfront)...max(edge, waterfront) { roads.insert(Plot(x, y)) }
        }
    }

    func lot(at point: Plot) -> Lot {
        let ground = river.ground(at: point)
        if roads.contains(point) { return Lot(ground: ground == .water ? .bridge : .road) }
        guard ground == .grass else { return Lot(ground: ground) }
        if parkCenters.contains(where: { abs(point.x - $0.x) < 2 && abs(point.y - $0.y) < 3 }) {
            return Lot(ground: .park)
        }
        if point.distance(to: downtown) < 10 { return Lot(zone: .commerce) }
        if point.distance(to: industry) < 9 { return Lot(zone: .industry) }
        return Lot()
    }
}
