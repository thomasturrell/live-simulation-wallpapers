@testable import CityArt
@testable import CityEngine
import Testing

private let markingOrigin = Dot(240, 30)

private func runwayFrame(alongY: Bool, night: Double) -> (Pixels, Airport, Palette) {
    let airport = Airport(origin: Plot(10, 10), alongY: alongY)
    let palette = Palette(night: night)
    var pixels = Pixels(width: 480, height: 220, background: palette.roadEdge)
    pixels.airportMarkings(at: markingOrigin, airport: airport, palette: palette)
    return (pixels, airport, palette)
}

private func runwayPoint(_ u: Int, _ v: Int, alongY: Bool) -> Dot {
    alongY ? markingOrigin.iso(v, u) : markingOrigin.iso(u, v)
}

@Test(arguments: [false, true], [0.0, 1.0])
func runwayStripesKeepTheirShapeAndGuidesStayClear(alongY: Bool, night: Double) {
    let (pixels, _, palette) = runwayFrame(alongY: alongY, night: night)
    let white = palette.color(0xD8D4BD, 0x92939A).pixel
    func local(_ x: Int, _ y: Int) -> (u: Double, v: Double) {
        let dx = Double(x - markingOrigin.x), dy = Double(y - markingOrigin.y)
        let u = dy + dx / 2, v = dy - dx / 2
        return alongY ? (v, u) : (u, v)
    }
    func stripe(_ u: Int, _ v: Int) -> Set<Plot> {
        let origin = runwayPoint(u, v, alongY: alongY)
        var shape: Set<Plot> = []
        for y in 0..<pixels.height {
            for x in 0..<pixels.width where pixels.storage[y * pixels.width + x] == white {
                let p = local(x, y)
                if (Double(u) - 0.75...Double(u) + 8.75).contains(p.u) && abs(p.v - Double(v)) <= 0.75 {
                    shape.insert(Plot(x - origin.x, y - origin.y))
                }
            }
        }
        return shape
    }
    let reference = stripe(12, 61)
    #expect(reference.count == 9)
    for end in [12, 163] {
        for across in [61, 65, 69, 73] { #expect(stripe(end, across) == reference) }
    }
    for centre in [52, 78, 104, 130] { #expect(stripe(centre - 4, 67) == reference) }
    let intrudingGuides = pixels.storage.indices.filter {
        pixels.storage[$0] == palette.paint.pixel && local($0 % pixels.width, $0 / pixels.width).v > 58.5
    }
    #expect(intrudingGuides.isEmpty)
}

@Test(arguments: [false, true], [0.0, 1.0])
func runwayNumbersRetainTheirOpenSpaces(alongY: Bool, night: Double) {
    let (pixels, _, palette) = runwayFrame(alongY: alongY, night: night)
    let white = palette.color(0xD8D4BD, 0x92939A).pixel
    func painted(_ u: Int, _ v: Int) -> Bool {
        let p = runwayPoint(u, v, alongY: alongY)
        return pixels.storage[p.y * pixels.width + p.x] == white
    }
    // The zero stays hollow, and the nine has an open upper counter and a distinct crossbar.
    #expect(!painted(26, 64))
    for (u, v) in [(30, 62), (30, 66), (22, 62), (22, 66)] { #expect(painted(u, v)) }
    #expect(!painted(28, 70))
    #expect(painted(26, 70))
    #expect(!painted(26, 67))
    // The reciprocal two opens towards its lower right, rather than collapsing into a blob.
    #expect(!painted(159, 68))
    #expect(painted(159, 72))
}
