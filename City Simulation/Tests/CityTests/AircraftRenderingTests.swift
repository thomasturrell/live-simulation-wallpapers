@testable import CityArt
@testable import CityEngine
import Foundation
import Testing

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
        let pose = Aircraft.Pose(x: 0, y: 0, dx: cos(angle), dy: sin(angle), altitude: 0, bank: bank)
        var day = base, dark = base, flashing = base
        day.aircraft(at: center, pose: pose, livery: 0, blink: false, palette: Palette(night: 0))
        dark.aircraft(at: center, pose: pose, livery: 0, blink: false, palette: night)
        flashing.aircraft(at: center, pose: pose, livery: 0, blink: true, palette: night)

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
        }
    }
}

@Test(arguments: [false, true], [0.0, 1.0])
func aircraftLiveriesColorTheFinAndFuselage(alongY: Bool, night: Double) {
    let palette = Palette(night: night)
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
        let flight = Aircraft(id: 0, livery: livery, lane: 0, reverse: false, alongY: alongY)
        let pose = flight.pose()
        var sprite = Pixels(width: 48, height: 40, background: Ink(0x82975D))
        sprite.aircraft(at: center, pose: pose, livery: livery, blink: false, palette: palette)
        let facing = pose.dx > pose.dy ? 1 : -1
        let accents = sprite.storage.indices.filter { sprite.storage[$0] == accent.pixel }
        let along = accents.map { ($0 % sprite.width - center.x) * facing }
        #expect(along.contains { $0 <= -6 }, "Livery \(livery) is missing from the tail")
        #expect(along.contains { (-5...1).contains($0) }, "Livery \(livery) is missing from the fuselage")
    }
}

@Test(arguments: [false, true], [0.0, 1.0])
func overflightRendersTheEntireAircraftOverOpenWater(alongY: Bool, night: Double) throws {
    // These two crossings put the entire sprite over open water at wallpaper scale.
    var city = City(seed: alongY ? 23 : 171)
    var plane = Aircraft(id: 0, livery: 0, lane: 0, reverse: alongY, alongY: alongY)
    plane.elapsed = alongY ? 1133 : 905
    let pose = plane.pose()
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
    sprite.aircraft(at: center, pose: pose, livery: plane.livery, blink: true, palette: palette)
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

@Test(arguments: [false, true], [false, true])
func overflightsCrossTheVisibleCity(alongY: Bool, reverse: Bool) {
    let sizes = [(1280, 720), (1080, 1920), (3440, 1440)]
    for lane in [-8, 0, 8] {
        var flight = Aircraft(id: 0, livery: 0, lane: lane, reverse: reverse, alongY: alongY)
        for (width, height) in sizes {
            let viewport = CityViewport(pixelWidth: width, pixelHeight: height)
            var centralSamples = 0
            for elapsed in stride(from: 0, to: flight.duration, by: 15) {
                flight.elapsed = elapsed
                let pose = flight.pose()
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
