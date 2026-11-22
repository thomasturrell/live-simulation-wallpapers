@testable import CityArt
@testable import CityEngine
import CoreGraphics
import Foundation
import Testing

@Test func seedProducesTheSameEstablishedCityAndTraffic() {
    let city = City(seed: 42)
    #expect(city == City(seed: 42))
    #expect(city != City(seed: 43))
    #expect(city.vehicles.count > 20)
    for zone in [Zone.homes, .commerce, .industry, .civic] {
        #expect(CityMap.plots.contains { city.map[$0].building != nil && city.map[$0].zone == zone })
    }
    #expect(CityMap.plots.contains { city.map[$0].ground == .park })
}

@Test func everyRoadIsConnectedAndEveryOccupiedLotHasFrontage() throws {
    let map = City().map
    let start = try #require(CityMap.plots.first(where: map.isRoad))
    var seen: Set<Plot> = [start]
    var queue = [start]
    while let point = queue.popLast() {
        for next in point.neighbors where map.isRoad(next) && seen.insert(next).inserted { queue.append(next) }
    }
    #expect(seen == Set(CityMap.plots.filter(map.isRoad)))
    let route = try #require(map.route(from: Plot(24, 19), to: Plot(38, 19)))
    #expect(route.contains { map[$0].ground == .bridge })
    #expect(map.route(from: start, to: Plot(-1, -1)) == nil)
    for point in CityMap.plots {
        guard let building = map[point].building else { continue }
        #expect(map[point].ground == .grass)
        #expect(map.roadAccess(at: point) != nil)
        #expect((1...map.capacity(at: point)).contains(building.level))
    }
}

@Test func journeysUseValidRoadsAndTurnContinuously() throws {
    var city = City()
    let initial = Dictionary(uniqueKeysWithValues: city.vehicles.map { ($0.id, $0.progress) })
    for _ in 0..<900 { city.step() }
    #expect(city.vehicles.contains { initial[$0.id] == nil })
    #expect(Set(initial.keys).subtracting(city.vehicles.map(\.id)).count > 15)
    for car in city.vehicles {
        #expect(car.route.allSatisfy(city.map.isRoad))
        #expect(car.origin.distance(to: car.route[0]) == 1)
        #expect(car.destination.distance(to: car.route.last!) == 1)
        #expect(zip(car.route, car.route.dropFirst()).allSatisfy { $0.distance(to: $1) == 1 })
        #expect(city.map[car.origin].building != nil)
        #expect(city.map[car.destination].building != nil)
    }

    var car = Vehicle(id: 0, route: [Plot(6, 7), Plot(7, 7), Plot(7, 8), Plot(7, 9)],
                      color: 0, pace: 24, long: false, origin: Plot(6, 6), destination: Plot(8, 9), progress: 0)
    var previous = car.pose(in: city.trafficConvention)
    #expect(previous.visibility == 0)
    for progress in 1...72 {
        car.progress = progress
        let next = car.pose(in: city.trafficConvention)
        #expect(hypot(next.x - previous.x, next.y - previous.y) < 0.18)
        previous = next
    }
    #expect(previous.visibility == 0)
}

@Test func developmentUsesZonedFrontageAndKeepsParksAndRoads() throws {
    var city = City()
    let original = city.map
    for _ in 0..<City.ticksPerSecond * 12 { city.step() }
    let project = try #require(city.construction)
    let replacement = try #require(project.replacement)
    let plot = project.plot
    #expect(city.map[plot] == original[plot])
    #expect(city.map.roadAccess(at: plot) != nil)
    #expect(replacement.level == (original[plot].building?.level ?? 0) + 1)
    #expect(replacement.level <= city.map.capacity(at: plot))

    for _ in city.tick..<project.finish { city.step() }
    #expect(city.map[plot].building == replacement)
    #expect(city.revision == 1)
    var roadProject: Plot?
    while city.tick < City.ticksPerSecond * 240 && roadProject == nil {
        city.step()
        if let job = city.construction, job.replacement == nil {
            #expect(city.map.roadAccess(at: job.plot) != nil)
            #expect(city.map[job.plot].building == nil)
            for _ in city.tick..<job.finish { city.step() }
            roadProject = job.plot
        }
    }
    let newRoad = try #require(roadProject)
    #expect(city.map.isRoad(newRoad))
    #expect(city.map.route(from: newRoad, to: Plot(24, 25)) != nil)
    for point in CityMap.plots where [.park, .water, .road, .bridge].contains(original[point].ground) {
        #expect(city.map[point] == original[point])
    }
}

@Test(arguments: TrafficConvention.allCases)
func checkpointRestoresConstructionTrafficAndRandomSequence(convention: TrafficConvention) throws {
    var city = City(seed: 99, trafficConvention: convention)
    for _ in 0..<City.ticksPerSecond * 13 { city.step() }
    #expect(city.construction != nil)
    let data = try city.checkpoint()
    var restored = try #require(City(checkpoint: data))
    #expect(restored == city)
    #expect(City(checkpoint: Data(data.prefix(20))) == nil)
    let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    var previousVersion = try #require(plist as? [String: Any])
    previousVersion["version"] = 1
    let obsolete = try PropertyListSerialization.data(fromPropertyList: previousVersion, format: .binary, options: 0)
    #expect(City(checkpoint: obsolete) == nil)
    for _ in 0..<920 {
        city.step()
        restored.step()
    }
    #expect(city == restored)
}

@Test func versionFiveCheckpointsKeepTheirRightHandJourneys() throws {
    #expect(City().trafficConvention == .uk)
    var city = City(seed: 42, trafficConvention: .rightHand)
    for _ in 0..<180 { city.step() }
    #expect(!city.vehicles.isEmpty)
    let data = try city.checkpoint()
    var plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    var fields = try #require(plist["city"] as? [String: Any])
    fields.removeValue(forKey: "savedTrafficConvention")
    plist["city"] = fields
    let incomplete = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    #expect(City(checkpoint: incomplete) == nil)
    plist["version"] = 5
    let legacy = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    var restored = try #require(City(checkpoint: legacy))
    #expect(city == restored)
    #expect(try City(checkpoint: restored.checkpoint()) == restored)
    for _ in 0..<300 {
        city.step()
        restored.step()
    }
    #expect(city == restored)
}

@Test func fixedTimePlaybackIsIndependentOfDrawCadence() {
    var slow = Playback(city: City())
    var fast = slow
    slow.present(visible: true, animated: true)
    fast.present(visible: true, animated: true)
    let renderer = CityRenderer()
    let viewport = CityViewport(pixelWidth: 168, pixelHeight: 94)
    for index in 0..<600 {
        fast.advance(elapsed: 1 / 60.0)
        if index.isMultiple(of: 19) { _ = renderer.image(for: fast.city, viewport: viewport) }
    }
    for _ in 0..<83 { slow.advance(elapsed: 0.12) }
    slow.advance(elapsed: 0.04)
    #expect(fast.city.tick == 300)
    #expect(fast.city == slow.city)
}

@Test func playbackSettlesStopsSuspendsAndResumesInPlace() {
    var playback = Playback(city: City())
    #expect(!playback.needsTimer)
    playback.present(visible: true, animated: false)
    #expect(playback.mode == .still)
    playback.present(visible: true, animated: true)
    for _ in 0..<7 { playback.advance(elapsed: 0.125) }
    let moving = playback.city.tick
    #expect(moving == 26)
    playback.present(visible: true, animated: false)
    #expect(playback.mode == .settling)
    playback.advance(elapsed: 0.25)
    let early = playback.city.tick - moving
    for _ in 0..<14 { playback.advance(elapsed: 0.25) }
    #expect(playback.needsTimer && playback.mode == .settling)
    playback.advance(elapsed: 0.25)
    #expect(playback.city.tick - moving == 40)
    #expect(early > 4)
    #expect(!playback.needsTimer && playback.mode == .still)
    let parked = playback.city
    playback.advance(elapsed: 10)
    #expect(playback.city == parked)
    playback.present(visible: true, animated: true)
    playback.advance(elapsed: 0.2)
    #expect(playback.city.tick == parked.tick + 6)
    playback.present(visible: false, animated: true)
    let suspended = playback.city
    #expect(!playback.needsTimer && playback.mode == .suspended)
    playback.advance(elapsed: 100)
    #expect(playback.city == suspended)
    playback.present(visible: true, animated: true)
    playback.advance(elapsed: 0.1)
    #expect(playback.city.tick == suspended.tick + 3)
}

@Test(arguments: [CGSize(width: 5120, height: 2880), CGSize(width: 3024, height: 1964),
                  CGSize(width: 3441, height: 1441), CGSize(width: 1080, height: 1920),
                  CGSize(width: 1280, height: 800), CGSize(width: 47, height: 19)])
func integerPixelsCoverTheDisplay(size: CGSize) throws {
    let width = Int(size.width), height = Int(size.height)
    let viewport = CityViewport(pixelWidth: width, pixelHeight: height)
    #expect(viewport.imageRect.contains(CGRect(origin: .zero, size: size)))
    let image = CityRenderer().image(for: City(), viewport: viewport)
    #expect(image.width == viewport.width && image.height == viewport.height)
    #expect(!image.shouldInterpolate)
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                         bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    viewport.draw(image, in: context)
    let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
    for (x, y) in [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)] {
        #expect(bytes[y * context.bytesPerRow + x * 4 + 3] == 255)
    }
    if viewport.zoom > 1 {
        let start = Int(viewport.imageRect.minX) + (viewport.width / 2) * viewport.zoom
        let sample = height / 2 * context.bytesPerRow + start * 4
        for offset in 1..<viewport.zoom {
            for channel in 0..<4 { #expect(bytes[sample + channel] == bytes[sample + offset * 4 + channel]) }
        }
    }
}

@Test func framesChangeWithTrafficAndLighting() throws {
    var city = City()
    let viewport = CityViewport(pixelWidth: 640, pixelHeight: 360)
    let renderer = CityRenderer()
    let first = renderer.image(for: city, viewport: viewport)
    #expect(renderer.image(for: city, viewport: viewport) === first)
    for _ in 0..<30 { city.step() }
    let later = renderer.image(for: city, viewport: viewport)
    #expect(first.dataProvider?.data != later.dataProvider?.data)
    while city.darkness < 0.99 { city.step() }
    let night = renderer.image(for: city, viewport: viewport)
    let dayPixels = try #require(first.dataProvider?.data) as Data
    let nightPixels = try #require(night.dataProvider?.data) as Data
    let sample = 4 * (viewport.width * 302 + 12)
    let sum: (Data) -> Int = { $0[sample..<(sample + 3)].reduce(0) { $0 + Int($1) } }
    #expect(sum(nightPixels) < sum(dayPixels))
}

@Test func switchingSkinsRebuildsArtworkAtTheSavedTick() throws {
    var city = City()
    for _ in 0..<300 { city.step() }
    let checkpoint = try city.checkpoint()
    let saved = try #require(City(checkpoint: checkpoint))
    let renderer = CityRenderer()
    let viewport = CityViewport(pixelWidth: 640, pixelHeight: 360)
    let original = renderer.image(for: saved, viewport: viewport)
    #expect(renderer.image(for: saved, viewport: viewport, skin: .original) === original)

    let contemporary = renderer.image(for: saved, viewport: viewport, skin: .contemporary)
    #expect(renderer.image(for: saved, viewport: viewport, skin: .contemporary) === contemporary)
    let originalBytes = try #require(original.dataProvider?.data) as Data
    let contemporaryBytes = try #require(contemporary.dataProvider?.data) as Data
    #expect(contemporaryBytes != originalBytes)

    let fresh = CityRenderer().image(for: saved, viewport: viewport, skin: .contemporary)
    #expect(try #require(fresh.dataProvider?.data) as Data == contemporaryBytes)
    let switchedBack = renderer.image(for: saved, viewport: viewport, skin: .original)
    #expect(try #require(switchedBack.dataProvider?.data) as Data == originalBytes)
    #expect(try saved.checkpoint() == checkpoint)
}

@Test func contemporaryRasterResolvesEdgesAndOcclusionWithinALogicalPixel() {
    let background = Ink(0x112233), roof = Ink(0x556677), car = Ink(0xAABBCC)
    var pixels = Pixels(width: 4, height: 4, background: background, rasterScale: 4)
    pixels.depth = 8
    pixels.polygon([Dot(0, 0), Dot(4, 0), Dot(0, 4)], roof)
    pixels.overlay = true
    pixels.depth = 7
    pixels.box(Dot(0, 0), 4, 4, car)

    // The diagonal splits the logical pixel at (1, 2). Only the exposed
    // samples should show a car passing behind the roof.
    let start = 8 * pixels.rasterWidth + 4
    #expect(pixels.storage[start] == roof.pixel)
    #expect(pixels.storage[start + 3 * pixels.rasterWidth + 3] == car.pixel)
    #expect(pixels.image().shouldInterpolate)
}

@Test func contemporaryUsesAFinerRasterWithTheOriginalCameraFraming() {
    let city = City(), renderer = CityRenderer()
    let view = CityViewport(pixelWidth: 1280, pixelHeight: 720)
    let original = renderer.image(for: city, viewport: view)
    let fine = renderer.image(for: city, viewport: view, skin: .contemporary)
    #expect(original.width == 640 && original.height == 360)
    #expect(fine.width >= view.pixelWidth && fine.height >= view.pixelHeight)
    #expect(fine.width * original.height == fine.height * original.width)
    #expect(fine.shouldInterpolate && !original.shouldInterpolate)
}
