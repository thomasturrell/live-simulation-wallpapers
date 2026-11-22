@testable import CityArt
@testable import CityEngine
import Testing

private let center = Plot(27, 26)
private let origin = Dot(80, 60)
private let directions = [SIMD2(1, 0), SIMD2(0, 1), SIMD2(-1, 0), SIMD2(0, -1)]

private func roadFrame(_ roads: [SIMD2<Int>], bridges: Set<Plot> = [],
                       convention: TrafficConvention, palette: Palette) -> Pixels {
    var map = City().map
    for x in -4...4 {
        for y in -4...4 { map[Plot(center.x + x, center.y + y)] = Lot() }
    }
    for road in roads {
        map[Plot(center.x + road.x, center.y + road.y)] = Lot(ground: bridges.contains(Plot(road.x, road.y)) ? .bridge : .road)
    }
    var pixels = Pixels(width: 160, height: 120, background: palette.grass(0))
    for road in roads.sorted(by: { ($0.x + $0.y, $0.x) < ($1.x + $1.y, $1.x) }) {
        let plot = Plot(center.x + road.x, center.y + road.y)
        pixels.ground(map[plot], at: origin.iso(road.x * 16, road.y * 16),
                      plot: plot, map: map, convention: convention, palette: palette)
    }
    return pixels
}

private func sample(_ frame: Pixels, _ offset: SIMD2<Int>) -> UInt32 {
    let dot = origin.iso(offset.x, offset.y)
    return frame.storage[dot.y * frame.width + dot.x]
}

@Test(arguments: TrafficConvention.allCases, [0.0, 1.0])
func straightAndBridgeDashesKeepAnEvenPhaseAcrossTiles(convention: TrafficConvention, night: Double) {
    let palette = Palette(night: night)
    let ink = convention == .uk ? palette.whiteRoadPaint : palette.yellowRoadPaint
    for alongX in [true, false] {
        let roads = (-3...3).map { alongX ? SIMD2($0, 0) : SIMD2(0, $0) }
        let frame = roadFrame(roads, bridges: alongX ? [Plot(0, 0)] : [], convention: convention, palette: palette)
        for x in (origin.x - 55)...(origin.x + 55) {
            let litPixels = (0..<frame.height).filter { frame.storage[$0 * frame.width + x] == ink.pixel }
            let phase = (x - origin.x + 64) % 16
            let dash = (phase <= 4 || phase >= 12) && abs(x - origin.x) <= 36
            #expect(litPixels.count == (dash ? 1 : 0))
            if dash, let y = litPixels.first {
                let projected = origin.y + ((alongX ? x - origin.x : origin.x - x) >> 1)
                #expect(abs(y - projected) <= 1)
            }
        }
        if convention == .uk { #expect(!frame.storage.contains(palette.yellowRoadPaint.pixel)) }
    }
}

@Test(arguments: TrafficConvention.allCases, [-1, 0, 1, 2, 3])
func stopLinesMarkOnlyTheIncomingLaneAtCrossroadsAndTJunctions(convention: TrafficConvention, missing: Int) {
    let connections = directions.enumerated().filter { $0.offset != missing }.map(\.element)
    for night in [0.0, 1.0] {
        let palette = Palette(night: night)
        let paint = palette.whiteRoadPaint.pixel
        let frame = roadFrame([.zero] + connections, convention: convention, palette: palette)
        #expect(frame.storage.filter { $0 == paint }.count == connections.count * 4)
        #expect(sample(frame, .zero) == palette.asphalt.pixel)
        for outward in connections {
            let incoming = convention == .uk ? SIMD2(-outward.y, outward.x) : SIMD2(outward.y, -outward.x)
            let stop = outward &* 10
            for lateral in [1, 4] { #expect(sample(frame, stop &+ incoming &* lateral) == paint) }
            for lateral in [0, -1, -2, -3, -4] { #expect(sample(frame, stop &+ incoming &* lateral) != paint) }
        }
        let longerApproaches = [SIMD2<Int>.zero] + connections + connections.map { $0 &* 2 }
        let extended = roadFrame(longerApproaches, convention: convention, palette: palette)
        let dash = convention == .uk ? paint : palette.yellowRoadPaint.pixel
        for outward in connections {
            #expect(sample(extended, outward &* 14) == dash)
            #expect(sample(extended, outward &* 12) == palette.asphalt.pixel)
        }
    }
}

@Test(arguments: TrafficConvention.allCases)
func bendsCarryTheCentreMarkAndDeadEndsHaveNoStopLine(convention: TrafficConvention) {
    let palette = Palette(night: 0)
    let ink = convention == .uk ? palette.whiteRoadPaint : palette.yellowRoadPaint
    let bend = roadFrame([.zero, SIMD2(-1, 0), SIMD2(0, 1)], convention: convention, palette: palette)
    #expect(sample(bend, SIMD2(-5, 0)) == ink.pixel)
    #expect(sample(bend, SIMD2(0, 5)) == ink.pixel)
    #expect(!bend.storage.contains(palette.whiteRoadPaint.pixel) || convention == .uk)
    #expect(bend.storage.filter { $0 == ink.pixel }.count == 9)
    let deadEnd = roadFrame([.zero, SIMD2(-1, 0)], convention: convention, palette: palette)
    #expect(!deadEnd.storage.contains(ink.pixel))
    #expect(!deadEnd.storage.contains(palette.whiteRoadPaint.pixel))
}

@Test func changingConventionInvalidatesTheRendererCacheAtTheSameTick() {
    let uk = City(trafficConvention: .uk)
    let right = City(trafficConvention: .rightHand)
    let viewport = CityViewport(pixelWidth: 640, pixelHeight: 360)
    let renderer = CityRenderer()
    let leftImage = renderer.image(for: uk, viewport: viewport)
    let rightImage = renderer.image(for: right, viewport: viewport)
    #expect(leftImage !== rightImage)
    #expect(rightImage === renderer.image(for: right, viewport: viewport))
}
