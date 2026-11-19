@testable import CityArt
@testable import CityEngine
import Foundation
import Testing

@Test(arguments: [false, true], [0.0, 1.0])
func aircraftKeepAStableSilhouetteOnStraightGroundSegments(alongY: Bool, night: Double) {
    let airport = Airport(origin: Plot(10, 10), alongY: alongY)
    let segments: [(Aircraft.Phase, Range<Int>)] = [
        (.landing, 0..<13 * City.ticksPerSecond),
        (.takeoff, 0..<12 * City.ticksPerSecond),
        (.taxiIn, 7 * City.ticksPerSecond..<19 * City.ticksPerSecond),
        (.taxiOut, 0..<13 * City.ticksPerSecond)
    ]
    for shadow in night == 0 ? [false, true] : [false] {
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
                                shadow: shadow, blink: false, palette: Palette(night: night))
                if let reference, sprite.storage != reference { changedFrames += 1 }
                else if reference == nil { reference = sprite.storage }
            }
            #expect(changedFrames == 0, "Straight \(phase) changed the aircraft silhouette in \(changedFrames) frames")
        }
    }
}

@Test(arguments: [-0.22, 0, 0.22])
func aircraftSilhouetteStaysConnectedWhileTurningAndBanking(bank: Double) throws {
    let background = Ink(0x82975D)
    let base = Pixels(width: 48, height: 40, background: background)
    let center = Dot(24, 20)
    let night = Palette(night: 1)
    let lights = [night.color(0xB15E4E, 0xE18069), night.color(0x71A286, 0x9DD3AB)]
    // Diagonal neighbors count as connected in the isometric sprite.
    let neighbors = [-1, 0, 1].flatMap { row in [-1, 0, 1].map { row * base.width + $0 } }
    for degrees in stride(from: 0, to: 360, by: 5) {
        let angle = Double(degrees) * .pi / 180
        let pose = Aircraft.Pose(x: 0, y: 0, dx: cos(angle), dy: sin(angle), altitude: 0, bank: bank, gear: false)
        var day = base, dark = base, flashing = base, groundShadow = base
        day.aircraft(at: center, pose: pose, livery: 0, shadow: false, blink: false, palette: Palette(night: 0))
        dark.aircraft(at: center, pose: pose, livery: 0, shadow: false, blink: false, palette: night)
        flashing.aircraft(at: center, pose: pose, livery: 0, shadow: false, blink: true, palette: night)
        if bank == 0 {
            groundShadow.aircraft(at: center, pose: pose, livery: 0, shadow: true, blink: false, palette: night)
        }

        let painted = day.storage.indices.filter { day.storage[$0] != background.pixel }
        #expect(dark.storage.indices.filter { dark.storage[$0] != background.pixel } == painted)
        #expect(flashing.storage.indices.filter { flashing.storage[$0] != background.pixel } == painted)
        let beacon = dark.storage.indices.filter { dark.storage[$0] != flashing.storage[$0] }
        #expect(beacon.count == 1)
        #expect(beacon.first.map { flashing.storage[$0] } == night.gold.pixel)

        let columns = painted.map { $0 % base.width }
        let rows = painted.map { $0 / base.width }
        let width = try #require(columns.max()) - #require(columns.min()) + 1
        let height = try #require(rows.max()) - #require(rows.min()) + 1
        #expect(width <= 27)
        #expect(height <= 18)

        var remaining = Set(painted.dropFirst())
        var pending = [try #require(painted.first)]
        while let pixel = pending.popLast() {
            for offset in neighbors {
                if let next = remaining.remove(pixel + offset) { pending.append(next) }
            }
        }
        #expect(remaining.isEmpty, "Detached aircraft pixels at \(degrees)° with bank \(bank)")

        for light in lights {
            let pixels = dark.storage.indices.filter { dark.storage[$0] == light.pixel }
            #expect(pixels.count == 1)
            let tip = try #require(pixels.first)
            if bank == 0 {
                // Flattening the level wing moves its tip down by at most one pixel.
                #expect([tip, tip + base.width].contains { groundShadow.storage[$0] != background.pixel })
            }
        }
    }
}

@Test(arguments: [false, true], [0.0, 1.0])
func aircraftLiveriesColorTheFinAndFuselage(alongY: Bool, night: Double) {
    let palette = Palette(night: night)
    let airport = Airport(origin: Plot(10, 10), alongY: alongY)
    let center = Dot(24, 20)
    let waterColors = [palette.water, palette.waterDark, palette.waterLight]
    let colors: [UInt32] = [0x477C83, 0xAD6253, 0xB49755, 0x677A9A]
    for (livery, color) in colors.enumerated() {
        let accent = palette.color(color).mix(palette.color(0xE0DDC9, 0x9DA8B3), 0.34)
        for water in waterColors {
            let channelDifferences = [0, 8, 16].map { shift in
                abs(Int((accent.rgb >> shift) & 255) - Int((water.rgb >> shift) & 255))
            }
            #expect(channelDifferences.contains { $0 >= 25 }, "Livery \(livery) blends into the river")
        }
        for phase in [Aircraft.Phase.parked, .landing] {
            let flight = Aircraft(id: 0, livery: livery, phase: phase, standTime: 1800,
                                  lane: 0, reverse: false, alongY: alongY)
            let pose = flight.pose(at: airport)
            var sprite = Pixels(width: 48, height: 40, background: Ink(0x82975D))
            sprite.aircraft(at: center, pose: pose, livery: livery, shadow: false, blink: false, palette: palette)
            let facing = pose.dx > pose.dy ? 1 : -1
            let accents = sprite.storage.indices.filter { sprite.storage[$0] == accent.pixel }
            let along = accents.map { ($0 % sprite.width - center.x) * facing }
            #expect(along.contains { $0 <= -6 }, "Livery \(livery) is missing from the tail")
            #expect(along.contains { (-5...1).contains($0) }, "Livery \(livery) is missing from the fuselage")
        }
    }
}

@Test(arguments: [false, true], [0.0, 1.0])
func overflightRendersTheEntireAircraftOverOpenWater(alongY: Bool, night: Double) throws {
    // These two crossings put the entire sprite over open water at wallpaper scale.
    var city = City(seed: alongY ? 23 : 171)
    var plane = Aircraft(id: 0, livery: 0, phase: .overflight, standTime: 1800,
                         lane: 0, reverse: alongY, alongY: alongY)
    plane.elapsed = alongY ? 1133 : 905
    let pose = plane.pose(at: city.map.airport)
    let viewport = CityViewport(pixelWidth: 1280, pixelHeight: 720)
    let position = viewport.project(pose.x, pose.y, altitude: pose.altitude)
    var preview = EnvironmentPreview()
    preview.darkness = night
    preview.month = 2
    preview.weather = .clear
    let environment = Environment.frame(city: city, preview: preview).quantized
    let palette = Palette(night: night, environment: environment)
    let water = [palette.water, palette.waterDark, palette.waterLight].map(\.pixel)
    let background = CityRenderer().image(for: city, viewport: viewport, environment: environment)
    city.aviation.aircraft = [plane]
    let image = CityRenderer().image(for: city, viewport: viewport, environment: environment)
    let backgroundData = try #require(background.dataProvider?.data) as Data
    let imageData = try #require(image.dataProvider?.data) as Data

    var sprite = Pixels(width: 36, height: 26, background: Ink(0))
    let center = Dot(18, 13)
    sprite.aircraft(at: center, pose: pose, livery: plane.livery, shadow: false, blink: true, palette: palette)
    let painted = sprite.storage.indices.filter { sprite.storage[$0] != Ink(0).pixel }
    #expect(painted.count > 60)
    backgroundData.withUnsafeBytes { backdrop in
        imageData.withUnsafeBytes { frame in
            let ground = backdrop.bindMemory(to: UInt32.self)
            let pixels = frame.bindMemory(to: UInt32.self)
            for index in painted {
                let x = position.x + index % sprite.width - center.x
                let y = position.y + index / sprite.width - center.y
                let destination = y * viewport.width + x
                #expect(water.contains(ground[destination]))
                #expect(pixels[destination] == sprite.storage[index])
            }
        }
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
