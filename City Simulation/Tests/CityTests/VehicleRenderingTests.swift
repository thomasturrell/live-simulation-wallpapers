@testable import CityArt
@testable import CityEngine
import Foundation
import Testing

private let asphalt = Ink(0x485464)
private let center = Dot(12, 10)

private func sprite(at angle: Double, long: Bool, visibility: Double = 1, night: Double = 0) -> Pixels {
    var pixels = Pixels(width: 24, height: 20, background: asphalt, rasterScale: 4)
    pixels.overlay = true
    pixels.opacity = visibility
    let pose = Vehicle.Pose(x: 0, y: 0, dx: cos(angle) * 0.08, dy: sin(angle) * 0.08, visibility: visibility)
    pixels.car(at: center, pose: pose, color: 0, long: long, palette: Palette(night: night, skin: .contemporary))
    return pixels
}

@Test(arguments: [false, true], [0.4, 1.0])
func contemporaryVehicleSilhouettesStayConnectedThroughTurns(long: Bool, visibility: Double) throws {
    for degrees in stride(from: 0, to: 360, by: 15) {
        let pixels = sprite(at: Double(degrees) * .pi / 180, long: long, visibility: visibility)
        var painted = Set(pixels.storage.indices.filter { pixels.storage[$0] != asphalt.pixel })
        let first = painted.popFirst()
        var pending = [try #require(first)]
        while let index = pending.popLast() {
            for y in -1...1 {
                for x in -1...1 {
                    if let next = painted.remove(index + y * pixels.rasterWidth + x) { pending.append(next) }
                }
            }
        }
        #expect(painted.isEmpty, "Detached vehicle pixels at \(degrees)°")
    }
    func width(_ angle: Double) throws -> Int {
        let pixels = sprite(at: angle, long: long, visibility: visibility)
        let columns = pixels.storage.indices.filter { pixels.storage[$0] != asphalt.pixel }.map { $0 % pixels.rasterWidth }
        return try #require(columns.max()) - #require(columns.min()) + 1
    }
    let headOn = try width(.pi / 4), sideOn = try width(3 * .pi / 4)
    #expect(sideOn > headOn)
}

@Test(arguments: [false, true])
func contemporaryVehicleLightsFollowTheDirectionOfTravel(long: Bool) throws {
    let palette = Palette(night: 1, skin: .contemporary)
    for angle in [0.0, .pi / 2, .pi, 3 * .pi / 2] {
        let pixels = sprite(at: angle, long: long, night: 1)
        let direction = cos(angle) - sin(angle)
        for (light, facing) in [(palette.gold, 1.0), (palette.color(0xA54F46, 0xE95D47), -1.0)] {
            let samples = pixels.storage.indices.filter { pixels.storage[$0] == light.pixel }
            try #require(!samples.isEmpty)
            #expect(samples.allSatisfy { index in
                let offset = Double(index % pixels.rasterWidth) + 0.5 - Double(center.x * pixels.rasterScale)
                return offset * direction * facing > 0
            }, "Lamp is on the wrong end at heading \(angle)")
        }
    }
}
