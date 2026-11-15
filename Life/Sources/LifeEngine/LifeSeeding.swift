import Foundation

public struct LifeSeeding {
    package private(set) var seed: UInt64

    public init(seed: UInt64) {
        self.seed = seed
    }

    private mutating func next() -> UInt64 {
        // SplitMix64 keeps a composition reproducible across processes.
        seed &+= 0x9e3779b97f4a7c15
        var bits = seed
        bits = (bits ^ (bits >> 30)) &* 0xbf58476d1ce4e5b9
        bits = (bits ^ (bits >> 27)) &* 0x94d049bb133111eb
        return bits ^ (bits >> 31)
    }

    private mutating func integer(_ limit: Int) -> Int {
        Int(next() % UInt64(limit))
    }

    public mutating func populate(_ world: inout LifeWorld) {
        let motifs: [LifePattern] = [.block, .beehive, .blinker, .toad, .beacon, .glider,
                                     .lightweightSpaceship, .rPentomino, .diehard, .acorn]
        for row in stride(from: 0, to: world.height, by: 11) {
            for column in stride(from: 0, to: world.width, by: 13) {
                let x = column + integer(min(13, world.width - column))
                let y = row + integer(min(11, world.height - row))
                let band = sin(Double(x) * 0.062 + Double(y) * 0.08)
                let pockets = cos(Double(x) * 0.087 - Double(y) * 0.052)
                let density = 0.64 + 0.20 * band + 0.13 * pockets
                guard integer(100) < Int(density * 100) else { continue }
                let pattern = motifs[integer(motifs.count)].oriented(integer(8))
                world.insert(pattern, x: x, y: y)

                // Small irregular colonies mingle with the named structures.
                guard integer(100) < Int(density * 57) else { continue }
                let radius = 3 + integer(4)
                for dy in -radius...radius {
                    for dx in -radius...radius where dx * dx + dy * dy <= radius * radius {
                        if integer(100) < 32 {
                            let targetX = x + dx + 4
                            let targetY = y + dy - 3
                            if (0..<world.width).contains(targetX), (0..<world.height).contains(targetY) {
                                world.setAlive(x: targetX, y: targetY)
                            }
                        }
                    }
                }
            }
        }
        for _ in 0..<12 { world.step() }
    }

    /// Tries to place one small pattern in a quiet part of the visible world.
    public mutating func introduce(into world: inout LifeWorld, x: Range<Int>, y: Range<Int>) {
        let motifs: [LifePattern] = [.glider, .glider, .lightweightSpaceship, .rPentomino,
                                     .diehard, .acorn, .toad]
        guard !x.isEmpty, !y.isEmpty else { return }
        let pattern = motifs[integer(motifs.count)].oriented(integer(8))
        for _ in 0..<18 {
            let column = x.lowerBound + integer(x.count)
            let row = y.lowerBound + integer(y.count)
            let clear = (max(0, row - 2)..<min(world.height, row + 10)).allSatisfy { cy in
                (max(0, column - 2)..<min(world.width, column + 10)).allSatisfy { cx in
                    !world.isAlive(x: cx, y: cy)
                }
            }
            if clear {
                world.insert(pattern, x: column, y: row)
                return
            }
        }
    }
}
