public struct LifePattern {
    public let cells: [(x: Int, y: Int)]

    public init(_ rows: [String]) {
        cells = rows.enumerated().flatMap { y, row in
            row.enumerated().compactMap { x, marker in
                marker == "o" ? (x, y) : nil
            }
        }
    }

    private init(cells: [(x: Int, y: Int)]) {
        self.cells = cells
    }

    public func oriented(_ orientation: Int) -> LifePattern {
        let transformed = cells.map { x, y -> (x: Int, y: Int) in
            let column = orientation & 1 == 0 ? x : -x
            let row = orientation & 2 == 0 ? y : -y
            return orientation & 4 == 0 ? (column, row) : (row, column)
        }
        let minX = transformed.map(\.x).min() ?? 0
        let minY = transformed.map(\.y).min() ?? 0
        return LifePattern(cells: transformed.map { ($0.x - minX, $0.y - minY) })
    }

    public static let block = LifePattern(["oo", "oo"])
    public static let beehive = LifePattern([".oo.", "o..o", ".oo."])
    public static let blinker = LifePattern(["ooo"])
    public static let toad = LifePattern([".ooo", "ooo."])
    public static let beacon = LifePattern(["oo..", "oo..", "..oo", "..oo"])
    public static let glider = LifePattern([".o.", "..o", "ooo"])
    public static let lightweightSpaceship = LifePattern([".o..o", "o....", "o...o", "oooo."])
    public static let rPentomino = LifePattern([".oo", "oo.", ".o."])
    public static let diehard = LifePattern(["......o.", "oo......", ".o...ooo"])
    public static let acorn = LifePattern([".o.....", "...o...", "oo..ooo"])
}
