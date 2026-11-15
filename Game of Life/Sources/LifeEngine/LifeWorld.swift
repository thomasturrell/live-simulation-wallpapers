import Foundation

/// A finite B3/S23 world with wraparound on both axes.
public struct LifeWorld {
    public let width: Int
    public let height: Int
    private let stride: Int
    private var cells: [UInt8]
    private var previous: [UInt8]
    public private(set) var generation = 0

    public init(width: Int, height: Int) {
        precondition(width >= 3 && height >= 3)
        self.width = width
        self.height = height
        stride = width + 2
        cells = Array(repeating: 0, count: (width + 2) * (height + 2))
        previous = cells
    }

    package struct Checkpoint: Codable {
        package let width: Int
        package let height: Int
        let generation: Int
        let bits: Data
    }

    package var checkpoint: Checkpoint {
        var bits = Data(repeating: 0, count: (width * height + 7) / 8)
        for y in 0..<height {
            for x in 0..<width where isAlive(x: x, y: y) {
                let i = y * width + x
                bits[i / 8] |= 1 << (i % 8)
            }
        }
        return Checkpoint(width: width, height: height, generation: generation, bits: bits)
    }

    package init?(checkpoint: Checkpoint) {
        let w = checkpoint.width
        let h = checkpoint.height
        guard (3...4096).contains(w), (3...4096).contains(h),
              (0..<Int.max).contains(checkpoint.generation),
              checkpoint.bits.count == (w * h + 7) / 8 else { return nil }
        self.init(width: w, height: h)
        generation = checkpoint.generation
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                if checkpoint.bits[i / 8] & (1 << (i % 8)) != 0 { setAlive(x: x, y: y) }
            }
        }
    }

    public func isAlive(x: Int, y: Int) -> Bool {
        cells[(y + 1) * stride + x + 1] != 0
    }

    public func wasAlive(x: Int, y: Int) -> Bool {
        previous[(y + 1) * stride + x + 1] != 0
    }

    public mutating func setAlive(_ alive: Bool = true, x: Int, y: Int) {
        precondition((0..<width).contains(x) && (0..<height).contains(y))
        cells[(y + 1) * stride + x + 1] = alive ? 1 : 0
    }

    public mutating func step() {
        // Copy the wrapped edges into a one-cell border so the inner loop
        // needs neither coordinate wrapping nor edge branches.
        let lastRow = height * stride
        let bottom = lastRow + stride
        for x in 1...width {
            cells[x] = cells[lastRow + x]
            cells[bottom + x] = cells[stride + x]
        }
        for y in 0...(height + 1) {
            let row = y * stride
            cells[row] = cells[row + width]
            cells[row + width + 1] = cells[row + 1]
        }

        cells.withUnsafeBufferPointer { current in
            previous.withUnsafeMutableBufferPointer { next in
                for y in 1...height {
                    let row = y * stride
                    for i in (row + 1)...(row + width) {
                        let above = i - stride
                        let below = i + stride
                        let top = current[above - 1] + current[above] + current[above + 1]
                        let middle = current[i - 1] + current[i + 1]
                        let bottom = current[below - 1] + current[below] + current[below + 1]
                        let count = top + middle + bottom
                        next[i] = (count == 3 || (count == 2 && current[i] == 1)) ? 1 : 0
                    }
                }
            }
        }
        swap(&cells, &previous)
        generation += 1
    }

    public mutating func insert(_ pattern: LifePattern, x: Int, y: Int) {
        for cell in pattern.cells {
            let column = ((x + cell.x) % width + width) % width
            let row = ((y + cell.y) % height + height) % height
            setAlive(x: column, y: row)
        }
    }
}
