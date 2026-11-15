import Testing
import LifeEngine

@Test(arguments: [false, true], Array(0...8))
func appliesEveryNeighbourCount(live: Bool, neighbours: Int) {
    var world = LifeWorld(width: 9, height: 9)
    let ring = [(3, 3), (3, 4), (3, 5), (4, 3), (4, 5), (5, 3), (5, 4), (5, 5)]
    world.setAlive(live, x: 4, y: 4)
    for (x, y) in ring.prefix(neighbours) { world.setAlive(x: x, y: y) }
    world.step()
    #expect(world.isAlive(x: 4, y: 4) == (neighbours == 3 || (live && neighbours == 2)))
    #expect(world.wasAlive(x: 4, y: 4) == live)
    #expect(world.generation == 1)
}

@Test func blockAndBeehiveAreStable() {
    var world = LifeWorld(width: 20, height: 16)
    world.insert(.block, x: 19, y: 15)
    world.insert(.beehive, x: 6, y: 7)
    let initial = liveIndices(world)
    #expect(initial.count == 10)
    for _ in 0..<12 { world.step() }
    #expect(liveIndices(world) == initial)
}

@Test func blinkerOscillatesAcrossWrap() {
    var world = LifeWorld(width: 9, height: 9)
    world.insert(.blinker, x: 8, y: 4)
    let initial = liveIndices(world)
    world.step()
    #expect(liveIndices(world) == [27, 36, 45])
    world.step()
    #expect(liveIndices(world) == initial)
}

@Test func gliderPropagatesDiagonally() {
    var world = LifeWorld(width: 16, height: 16)
    world.insert(.glider, x: 14, y: 14)
    for _ in 0..<4 { world.step() }
    var expected = LifeWorld(width: 16, height: 16)
    expected.insert(.glider, x: 15, y: 15)
    #expect(liveIndices(world) == liveIndices(expected))
}

@Test func matchesReferenceEvolution() {
    var world = LifeWorld(width: 17, height: 13)
    for y in 0..<world.height {
        for x in 0..<world.width where (x * x * 17 + y * 31 + x * y * 19) % 31 < 10 {
            world.setAlive(x: x, y: y)
        }
    }
    for _ in 0..<24 {
        let live = Set(liveIndices(world))
        let expected = (0..<(world.width * world.height)).filter { i in
            let x = i % world.width
            let y = i / world.width
            var neighbours = 0
            for dy in -1...1 {
                for dx in -1...1 where dx != 0 || dy != 0 {
                    let column = (x + dx + world.width) % world.width
                    let row = (y + dy + world.height) % world.height
                    if live.contains(row * world.width + column) { neighbours += 1 }
                }
            }
            return neighbours == 3 || (neighbours == 2 && live.contains(i))
        }
        world.step()
        #expect(liveIndices(world) == expected)
    }
}

private func liveIndices(_ world: LifeWorld) -> [Int] {
    (0..<(world.width * world.height)).filter {
        world.isAlive(x: $0 % world.width, y: $0 / world.width)
    }
}
