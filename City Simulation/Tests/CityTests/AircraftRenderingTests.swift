@testable import CityArt
@testable import CityEngine
import Foundation
import Testing

@Test(arguments: [false, true], [false, true])
func aircraftKeepAStableSilhouetteOnStraightGroundSegments(alongY: Bool, shadow: Bool) {
    let airport = Airport(origin: Plot(10, 10), alongY: alongY)
    let segments: [(Aircraft.Phase, Range<Int>)] = [
        (.landing, 0..<13 * City.ticksPerSecond),
        (.takeoff, 0..<12 * City.ticksPerSecond),
        (.taxiIn, 7 * City.ticksPerSecond..<19 * City.ticksPerSecond),
        (.taxiOut, 0..<13 * City.ticksPerSecond)
    ]
    for (phase, ticks) in segments {
        if shadow && phase == .takeoff { continue } // A rising aircraft's shadow intentionally fades.
        var flight = Aircraft(id: 0, livery: 0, phase: phase, standTime: 1800,
                              lane: 0, reverse: false, alongY: alongY)
        var reference: [UInt32]?
        var changedFrames = 0
        for tick in ticks {
            flight.elapsed = tick
            var sprite = Pixels(width: 48, height: 40, background: Ink(0x82975D))
            sprite.aircraft(at: Dot(24, 20), pose: flight.pose(at: airport), livery: 0,
                            shadow: shadow, blink: false, palette: Palette(night: 0))
            if let reference, sprite.storage != reference { changedFrames += 1 }
            else if reference == nil { reference = sprite.storage }
        }
        #expect(changedFrames == 0, "Straight \(phase) changed the aircraft silhouette in \(changedFrames) frames")
    }
}

@Test func approachingAircraftShadowDoesNotJitterBackwards() {
    let airport = Airport(origin: Plot(10, 10), alongY: false)
    let viewport = CityViewport(pixelWidth: 1280, pixelHeight: 720)
    var flight = Aircraft(id: 0, livery: 0, phase: .approach, standTime: 1800,
                          lane: 0, reverse: false, alongY: false)
    var previous: Dot?
    var backwardsSteps = 0
    for tick in 0..<flight.duration {
        flight.elapsed = tick
        let pose = flight.pose(at: airport)
        guard pose.altitude < 60 else { continue }
        let screen = viewport.project(pose.x, pose.y, offset: SIMD2(4 + pose.altitude * 0.25, 2))
        if let previous, screen.x < previous.x || screen.y < previous.y { backwardsSteps += 1 }
        previous = screen
    }
    #expect(backwardsSteps == 0)
}

@Test(arguments: [Aircraft.Phase.takeoff, .climb])
func ascendingAircraftDoNotJitterBackwardsOnScreen(phase: Aircraft.Phase) {
    let airport = Airport(origin: Plot(10, 10), alongY: false)
    let viewport = CityViewport(pixelWidth: 1280, pixelHeight: 720)
    var flight = Aircraft(id: 0, livery: 0, phase: phase, standTime: 1800,
                          lane: 0, reverse: false, alongY: false)
    var previous: Dot?
    var backwardsSteps = 0
    for tick in 0..<flight.duration {
        flight.elapsed = tick
        let pose = flight.pose(at: airport)
        let screen = viewport.project(pose.x, pose.y, altitude: pose.altitude)
        // These paths move right and down in this projection, including during the climb.
        if let previous, screen.x < previous.x || screen.y < previous.y { backwardsSteps += 1 }
        previous = screen
    }
    #expect(backwardsSteps == 0, "\(phase) stepped backwards in \(backwardsSteps) frames")
}

@Test func aircraftShadowsOnlyDarkenTheSurfaceUnderEachPixel() {
    let palette = Palette(night: 0)
    var runway = Pixels(width: 96, height: 64, background: palette.roadEdge)
    for x in stride(from: 0, to: 96, by: 12) {
        runway.box(Dot(x, 0), 4, 64, palette.shore)
    }
    let pose = Aircraft.Pose(x: 0, y: 0, dx: 1, dy: 0, altitude: 0, bank: 0, gear: true)
    for x in stride(from: 20, through: 76, by: 4) {
        var frame = runway
        frame.overlay = true
        frame.depth = 1
        frame.aircraft(at: Dot(x, 32), pose: pose, livery: 0, shadow: true, blink: false, palette: palette)
        let changed = runway.storage.indices.filter { runway.storage[$0] != frame.storage[$0] }
        #expect(changed.count > 40)
        let brightened = changed.first { index in
            [0, 8, 16].contains { shift in
                (frame.storage[index] >> shift) & 255 > (runway.storage[index] >> shift) & 255
            }
        }
        #expect(brightened == nil, "Shadow crossing a runway marking at x=\(x)")
        // Markings remain lighter than asphalt inside the same shadow.
        let shadedAsphalt = changed.filter { runway.storage[$0] == palette.roadEdge.pixel }.map { frame.storage[$0] & 255 }
        let shadedPaint = changed.filter { runway.storage[$0] == palette.shore.pixel }.map { frame.storage[$0] & 255 }
        if let paint = shadedPaint.min(), let asphalt = shadedAsphalt.max() { #expect(paint > asphalt) }
    }
}

@Test func aircraftShadowsRespectBuildingsAndFadeWithHeight() {
    let palette = Palette(night: 0)
    var ground = Pixels(width: 80, height: 60, background: palette.sidewalk)
    ground.depth = 100
    ground.box(Dot(40, 0), 40, 60, palette.shore)
    var changedCounts: [Int] = []
    for altitude in [0.0, 30.0, 60.0] {
        var frame = ground
        frame.overlay = true
        frame.depth = 1
        let pose = Aircraft.Pose(x: 0, y: 0, dx: 1, dy: 0, altitude: altitude, bank: 0, gear: true)
        frame.aircraft(at: Dot(40, 30), pose: pose, livery: 0, shadow: true, blink: false, palette: palette)
        for y in 0..<60 { #expect(Array(frame.storage[y * 80 + 40..<y * 80 + 80]) == Array(ground.storage[y * 80 + 40..<y * 80 + 80])) }
        changedCounts.append(ground.storage.indices.filter { ground.storage[$0] != frame.storage[$0] }.count)
        if altitude < 60 {
            let shaded = frame.storage.enumerated().filter { $0.element != ground.storage[$0.offset] }.map { $0.element & 255 }
            #expect(!shaded.isEmpty)
        }
    }
    #expect(changedCounts[0] > 0 && changedCounts[1] > 0 && changedCounts[2] == 0)
}

@Test(arguments: [false, true], [false, true])
func overflightsCrossTheVisibleCity(alongY: Bool, reverse: Bool) {
    let sizes = [(1280, 720), (1080, 1920), (3440, 1440)]
    for lane in [-8, 0, 8] {
        var flight = Aircraft(id: 0, livery: 0, phase: .overflight, standTime: 1800,
                              lane: lane, reverse: reverse, alongY: alongY)
        for (width, height) in sizes {
            let viewport = CityViewport(pixelWidth: width, pixelHeight: height)
            var centralSamples = 0
            for elapsed in stride(from: 0, to: flight.duration, by: 15) {
                flight.elapsed = elapsed
                let pose = flight.pose(at: nil)
                let screen = viewport.project(pose.x, pose.y, altitude: pose.altitude)
                if (viewport.width * 3 / 10...viewport.width * 7 / 10).contains(screen.x) &&
                    (viewport.height * 3 / 10...viewport.height * 7 / 10).contains(screen.y) {
                    centralSamples += 1
                }
            }
            #expect(centralSamples >= 4, "Overflight must cross the city centre at \(width)×\(height), lane \(lane)")
        }
    }
}
