import CityEngine
import Foundation

private func airportDot(_ origin: Dot, _ airport: Airport, _ u: Double, _ v: Double, _ z: Double = 0) -> Dot {
    let position = airport.position(u, v)
    let x = (position.x - Double(airport.origin.x)) * 16
    let y = (position.y - Double(airport.origin.y)) * 16
    return origin.offset(Int((x - y).rounded()), Int(((x + y) * 0.5 - z * Airport.scale).rounded()))
}

extension Pixels {
    mutating func airportSurfaces(at p: Dot, airport: Airport, palette c: Palette) {
        func dot(_ u: Double, _ v: Double, _ z: Double = 0) -> Dot {
            airportDot(p, airport, u, v, z)
        }
        func surface(_ area: Airport.Surface, _ ink: Ink, inset: Double = 0) {
            let u = area.u.lowerBound + inset, endU = area.u.upperBound - inset
            let v = area.v.lowerBound + inset, endV = area.v.upperBound - inset
            polygon([dot(u, v), dot(endU, v), dot(endU, endV), dot(u, endV)], ink)
        }
        for area in Airport.hangarPavement { surface(area, c.sidewalk.mix(c.asphalt, 0.5)) }
        for gate in Airport.gates { surface(gate.stand, c.asphalt.mix(c.sidewalk, 0.26)) }
        for link in Airport.runwayLinks { surface(link, c.asphalt) }
        surface(Airport.taxiway, c.asphalt)
        surface(Airport.runway, c.curb)
        surface(Airport.runway, c.roadEdge, inset: 0.075)
        surface(Airport.forecourt, c.sidewalk)
        let entry = Airport.entranceCenter
        polygon([dot(entry - 0.365, -0.5), dot(entry + 0.365, -0.5),
                 dot(entry + 0.66, -0.27), dot(entry - 0.66, -0.27)], c.asphalt)
        line(dot(entry - 0.76, -0.17), dot(entry + 0.76, -0.17), c.curb)
        for u in [entry - 1.16, entry + 1.16] {
            let bed = dot(u, -0.29)
            tile(bed, -4, -2, 8, 4, c.paths)
            line(bed.iso(-3, 0, 1), bed.iso(3, 0, 1), c.foliage)
            span(bed.x - 1, bed.x + 1, bed.y - 1, c.gold.mix(c.foliage, 0.6))
        }

        // Low fencing on the runway side and beside the service yards.
        for (start, end, v) in [(0.2, 13.3, 6.38), (0.2, 3.4, -0.34), (9.7, 13.3, -0.34)] {
            let wire = c.foliage.mix(c.curb, 0.38)
            line(dot(start, v, 1.5), dot(end, v, 1.5), wire)
            for u in stride(from: start, through: end, by: 1.1) {
                line(dot(u, v), dot(u, v, 2.5), wire)
            }
        }
        if c.night > 0.3 {
            for u in stride(from: 0.65, through: 13.1, by: 1.45) {
                for v in [Airport.runway.v.lowerBound, Airport.runway.v.upperBound] {
                    let light = dot(u, v)
                    span(light.x, light.x, light.y, c.color(0xD5C395, 0xF2D7A1))
                }
                for v in [Airport.taxiway.v.lowerBound, Airport.taxiway.v.upperBound] {
                    let light = dot(u, v)
                    span(light.x, light.x, light.y, c.color(0x7E95AA, 0x7AA0C4))
                }
            }
        }
    }

    /// Markings use whole world pixels on the compact runway, rather than shrinking
    /// font pixels or clipping subpixel strokes independently to each terrain tile.
    mutating func airportMarkings(at p: Dot, airport: Airport, palette c: Palette) {
        func dot(_ u: Int, _ v: Int) -> Dot {
            airport.alongY ? p.iso(v, u) : p.iso(u, v)
        }
        func stroke(_ u: Int, _ v: Int, _ endU: Int, _ endV: Int, _ ink: Ink) {
            line(dot(u, v), dot(endU, endV), ink)
        }
        func rectangle(_ u: Int, _ v: Int, _ w: Int, _ d: Int, _ ink: Ink) {
            polygon([dot(u, v), dot(u + w, v), dot(u + w, v + d), dot(u, v + d)], ink)
        }

        func pixel(_ coordinate: Double) -> Int {
            Int((((coordinate + 0.5) * Airport.scale - 0.5) * 16).rounded())
        }
        let taxi = pixel(Airport.taxiwayCenter)
        stroke(pixel(Airport.taxiway.u.lowerBound) + 7, taxi, pixel(Airport.taxiway.u.upperBound) - 7, taxi, c.paint)
        let hold = pixel(Airport.holdShort.x)
        let runway = pixel(Airport.runwayCenter)
        stroke(hold, taxi, hold, runway - 9, c.paint)
        let exit = pixel(Airport.runwayExit)
        stroke(exit, taxi, exit, runway - 9, c.paint)
        for v in [53, 56] { stroke(hold - 4, v, hold + 4, v, c.paint) }
        for gate in Airport.gates {
            let u = pixel(gate.stop.x), v = pixel(gate.stop.y)
            stroke(u, v - 4, u, taxi, c.paint)
            stroke(u - 4, v, u + 4, v, c.paint)
            for side in [gate.stand.u.lowerBound + 0.19, gate.stand.u.upperBound - 0.19] {
                let edge = pixel(side)
                stroke(edge, v + 4, edge, v + 8, c.curb)
            }
        }

        let white = c.color(0xD8D4BD, 0x92939A)
        stroke(8, runway - 8, 177, runway - 8, white)
        stroke(8, runway + 8, 177, runway + 8, white)
        for u in [52, 78, 104, 130] { stroke(u - 4, runway, u + 4, runway, white) }
        for u in [12, 163] {
            for v in [61, 65, 69, 73] { stroke(u, v, u + 8, v, white) }
        }
        for u in [40, 137] {
            rectangle(u, 61, 6, 2, white)
            rectangle(u, 71, 6, 2, white)
        }

        // Outline numerals retain open counters at this scale. The opposite threshold
        // is rotated 180 degrees so each designation faces its approaching aircraft.
        let glyphs = [0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F]
        let segments = [(0, 0, 0, 4), (0, 4, 4, 4), (4, 4, 8, 4), (8, 4, 8, 0),
                        (8, 0, 4, 0), (4, 0, 0, 0), (4, 0, 4, 4)]
        for farEnd in [false, true] {
            let digits = farEnd ? [2, 7] : [0, 9]
            let top = farEnd ? 153 : 30
            let left = farEnd ? 72 : 62
            let along = farEnd ? 1 : -1
            let across = -along
            for (index, digit) in digits.enumerated() {
                for (bit, segment) in segments.enumerated() where glyphs[digit] & (1 << bit) != 0 {
                    let (row, column, endRow, endColumn) = segment
                    stroke(top + row * along, left + (index * 6 + column) * across,
                           top + endRow * along, left + (index * 6 + endColumn) * across, white)
                }
            }
        }
    }

    mutating func airportBuilding(at p: Dot, plot: Plot, airport: Airport, palette c: Palette) {
        func dot(_ u: Double, _ v: Double, _ z: Double = 0) -> Dot {
            airportDot(p, airport, u, v, z)
        }
        func prism(_ area: Airport.Surface, base: Double = 0, top: Double, roof: Ink) {
            let u = area.u.lowerBound, endU = area.u.upperBound
            let v = area.v.lowerBound, endV = area.v.upperBound
            let a = dot(u, v, top), b = dot(endU, v, top), e = dot(endU, endV, top), f = dot(u, endV, top)
            polygon([f, e, dot(endU, endV, base), dot(u, endV, base)], c.color(0xC0B8A1))
            polygon([b, e, dot(endU, endV, base), dot(endU, v, base)], c.color(0x878C86))
            polygon([a, b, e, f], roof.mix(c.snow, c.weather.snowCover * 0.85))
            line(f, e, c.curb)
            line(b, e, c.outline)
        }
        let glass = c.color(0x527F85, 0x677F8B)
        func windows(_ area: Airport.Surface, bottom: Double, top: Double) {
            let u = area.u.lowerBound + 0.09, endU = area.u.upperBound - 0.09
            let v = area.v.upperBound, endV = area.v.lowerBound + 0.08
            let wall = area.u.upperBound
            polygon([dot(u, v, top), dot(endU, v, top), dot(endU, v, bottom), dot(u, v, bottom)], glass)
            polygon([dot(wall, endV, top), dot(wall, v, top), dot(wall, v, bottom), dot(wall, endV, bottom)], glass)
            for (index, pane) in stride(from: u + 0.18, to: endU, by: 0.24).enumerated() {
                line(dot(pane, v, top), dot(pane, v, bottom), c.curb)
                if c.night > 0.4, index % 3 != 1 {
                    line(dot(pane + 0.06, v, bottom + 1), dot(min(endU, pane + 0.14), v, bottom + 1), c.gold)
                }
            }
        }
        for wing in Airport.concourses where plot == airport.anchor(for: wing) {
            prism(wing, top: 8, roof: c.color(0x829E9C))
            windows(wing, bottom: 2, top: 6)
        }
        for end in Airport.concourseEnds where plot == airport.anchor(for: end) {
            prism(end, top: 9, roof: c.color(0x9CADA2))
            windows(end, bottom: 2, top: 6)
        }
        if plot == airport.terminal {
            prism(Airport.headhouse, top: 12, roof: c.color(0x9EB5B0))
            windows(Airport.headhouse, bottom: 3, top: 8)
            let entry = Airport.entranceCenter
            prism(Airport.canopy, base: 5, top: 7, roof: c.color(0xBAC8BC))
            for u in [entry - 0.55, entry + 0.55] {
                line(dot(u, -0.26), dot(u, -0.26, 5), c.curb)
            }
            line(dot(entry - 0.41, 0.09, 13), dot(entry + 0.42, 0.09, 13), c.shore)
            prism(Airport.Surface(7.63...8.28, 0.32...0.58), base: 12, top: 14, roof: c.color(0x889C97))
        }
        for gate in Airport.gates where plot == airport.anchor(for: gate.pier) {
            prism(gate.pier, base: 2, top: 5, roof: c.color(0xBCC2AA))
            let u = gate.pier.u, v = gate.pier.v.upperBound
            line(dot(u.lowerBound, v, 3), dot(u.upperBound, v, 3), c.night > 0.4 ? c.gold : glass)
        }
        if plot == airport.tower {
            let u = Airport.towerCenter.x, v = Airport.towerCenter.y
            let cab = Airport.Surface((u - 0.35)...(u + 0.35), (v - 0.35)...(v + 0.35))
            prism(Airport.towerBase, top: 19, roof: c.curb)
            prism(cab, base: 19, top: 25, roof: c.color(0x73918D))
            windows(cab, bottom: 21, top: 24)
            line(dot(u, v, 25), dot(u, v, 32), c.outline)
            line(dot(u - 0.25, v, 30), dot(u + 0.25, v, 30), c.curb)
        }
        for hangar in Airport.hangarFootprints where plot == airport.anchor(for: hangar) {
            let u = hangar.u, v = hangar.v
            let middle = (v.lowerBound + v.upperBound) / 2
            prism(hangar, top: 9, roof: c.color(0x9B9E91))
            let ridgeA = dot(u.lowerBound, middle, 13), ridgeB = dot(u.upperBound, middle, 13)
            polygon([dot(u.lowerBound, v.lowerBound, 9), dot(u.upperBound, v.lowerBound, 9), ridgeB, ridgeA], c.color(0x8A9791))
            polygon([ridgeA, ridgeB, dot(u.upperBound, v.upperBound, 9), dot(u.lowerBound, v.upperBound, 9)], c.color(0xADB0A0))
            line(ridgeA, ridgeB, c.shore)
            let a = u.lowerBound + 0.17, b = u.upperBound - 0.17, front = v.upperBound
            polygon([dot(a, front, 7), dot(b, front, 7), dot(b, front), dot(a, front)], c.roadEdge)
            for panel in stride(from: a + 0.07, to: b, by: 0.25) {
                line(dot(panel, front, 6), dot(panel, front, 1), c.sidewalk)
            }
        }
    }

    mutating func aircraft(at p: Dot, pose: Aircraft.Pose, livery: Int, shadow: Bool, blink: Bool, palette c: Palette) {
        guard shadow else {
            aircraftShape(at: p, pose: pose, livery: livery, shadow: false, blink: blink, palette: c)
            return
        }
        let opacity = 0.3 * max(0, 1 - pose.altitude / 60)
        guard opacity > 0, p.x + 20 >= 0, p.x - 20 < width, p.y + 12 >= 0, p.y - 12 < height else { return }
        // Rasterise a single silhouette, then shade each covered ground pixel once.
        // Sampling one ground colour made the entire shadow flash over runway markings;
        // blending individual overlapping wings and fuselage would darken their overlaps twice.
        var mask = Pixels(width: 41, height: 25, background: Ink(0))
        mask.aircraftShape(at: Dot(20, 12), pose: pose, livery: livery, shadow: true, blink: false, palette: c)
        for y in 0..<mask.height {
            let targetY = p.y + y - 12
            guard (0..<height).contains(targetY) else { continue }
            for x in 0..<mask.width where mask.storage[y * mask.width + x] != Ink(0).pixel {
                let targetX = p.x + x - 20
                guard (0..<width).contains(targetX) else { continue }
                let index = targetY * width + targetX
                guard !overlay || depth >= depths[index] else { continue }
                let pixel = storage[index]
                var shaded = pixel & 0xFF00_0000
                for shift in [0, 8, 16] {
                    shaded |= UInt32(Double((pixel >> shift) & 255) * (1 - opacity)) << shift
                }
                storage[index] = shaded
            }
        }
    }

    private mutating func aircraftShape(at p: Dot, pose: Aircraft.Pose, livery: Int, shadow: Bool, blink: Bool, palette c: Palette) {
        let dx = pose.dx, dy = pose.dy
        func dot(_ along: Double, _ across: Double, _ z: Double = 0) -> Dot {
            let u = (dx * along - dy * across) * Airport.scale
            let v = (dy * along + dx * across) * Airport.scale
            let height = shadow ? 0 : (z + across * pose.bank) * Airport.scale
            return p.offset(Int((u - v).rounded()), Int(((u + v) * 0.5 - height).rounded()))
        }
        let shadowInk = Ink(0xFFFFFF)
        let white = shadow ? shadowInk : c.color(0xE0DDC9, 0x9DA8B3)
        let shade = shadow ? shadowInk : c.color(0x9DAEAC, 0x596C7E)
        // Lift the livery tones away from the river colours, especially the teal tail.
        let accent = shadow ? shadowInk : c.color([0x477C83, 0xAD6253, 0xB49755, 0x677A9A][livery]).mix(white, 0.34)
        let outline = shadow ? shadowInk : c.outline
        let engine = shadow ? shadowInk : c.color(0x72858B, 0x5B6D7E)
        let near = dx >= dy ? 1.0 : -1.0
        func wingtip(_ side: Double) -> Dot { dot(-5, side * 10.65) }

        // Swept wings and tailplanes, with underwing engine nacelles.
        for side in [-1.0, 1.0] {
            let wing = side > 0 ? shade : white
            polygon([dot(2, side), dot(-4, side * 10.65), dot(-6, side * 10.65), dot(-3, side)], wing)
            line(dot(-4.1, side * 8.5), wingtip(side), wing)
            line(dot(-1, side * 5, -1), dot(-4, side * 5, -1), engine)
            line(dot(-1, side * 5), dot(-4, side * 5), shade)
            polygon([dot(-6, 0), dot(-9, side * 5), dot(-11, side * 5), dot(-9, 0)], accent)
            line(dot(-8.3, 0), dot(-9.7, side * 4.3), accent)
        }
        if !shadow && pose.gear {
            for side in [-1.8, 1.8] { line(dot(-3, side, -1), dot(-2, side, -1), outline) }
            line(dot(7, 0, -1), dot(8, 0, -1), outline)
        }
        // Join the roof and the shaded side along the same rim so the fuselage reads as one solid body.
        let profile: [(along: Double, halfWidth: Double)] = [
            (-10.8, 0), (-8, 1.15), (7, 1.5), (9.5, 1.05), (10.8, 0)
        ]
        let rim = profile.map { dot($0.along, near * $0.halfWidth, 2) }
        let farRim = profile.reversed().map { dot($0.along, -near * $0.halfWidth, 2) }
        let belly = profile.reversed().map { dot($0.along * 0.95, near * $0.halfWidth * 0.85, 0.25) }
        polygon(rim + belly, shade)
        polygon(rim + farRim, white)
        polygon([dot(-9, 0, 2), dot(-10, 0, 7), dot(-7, 0, 7), dot(-5, 0, 2)], accent)
        line(dot(-8.5, 0, 6.6), dot(-7.3, 0, 2), accent)
        if shadow { return }
        line(dot(-4.6, near * 1.1, 0.55), dot(0, near * 1.2, 0.55), accent)
        let cockpit = c.color(0x354953, 0x253448)
        line(dot(7.2, -near, 2), dot(8, near, 1.75), cockpit)
        let cabin = c.color(0x52636B, 0x405269)
        for u in [-3.6, 0, 3.6] {
            let window = dot(u, near * 1.25, 1.25)
            span(window.x, window.x, window.y, cabin)
        }
        if c.night > 0.35 {
            let red = wingtip(-1), green = wingtip(1)
            span(red.x, red.x, red.y, c.color(0xB15E4E, 0xE18069))
            span(green.x, green.x, green.y, c.color(0x71A286, 0x9DD3AB))
            if blink {
                let beacon = dot(0, 0, 2)
                span(beacon.x, beacon.x, beacon.y, c.gold)
            }
        }
    }
}
