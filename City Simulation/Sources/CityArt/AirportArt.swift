import CityEngine
import Foundation

private func airportDot(_ p: Dot, _ plot: Plot, _ airport: Airport, _ u: Double, _ v: Double, _ z: Double = 0) -> Dot {
    let position = airport.position(u, v)
    let x = (position.x - Double(plot.x)) * 16
    let y = (position.y - Double(plot.y)) * 16
    return p.offset(Int((x - y).rounded()), Int(((x + y) * 0.5 - z * Airport.scale).rounded()))
}

extension Pixels {
    mutating func airportGround(at p: Dot, plot: Plot, airport: Airport, palette c: Palette) {
        let local = airport.local(plot)
        let leftEdge = Double(local.u) / Airport.scale - 0.5
        let rightEdge = Double(local.u + 1) / Airport.scale - 0.5
        let topEdge = Double(local.v) / Airport.scale - 0.5
        let bottomEdge = Double(local.v + 1) / Airport.scale - 0.5
        tile(p, -8, -8, 16, 16, c.grass((local.u + local.v) % 6))
        func point(_ a: Double, _ b: Double) -> Dot {
            airportDot(p, plot, airport, a, b)
        }
        // Clip long paved surfaces to each lot, preserving the renderer's terrain cache.
        func rectangle(_ a: Double, _ b: Double, _ endU: Double, _ endV: Double, _ ink: Ink) {
            let left = max(a, leftEdge), right = min(endU, rightEdge)
            let top = max(b, topEdge), bottom = min(endV, bottomEdge)
            guard left < right, top < bottom else { return }
            polygon([point(left, top), point(right, top), point(right, bottom), point(left, bottom)], ink)
        }
        rectangle(0.1, 4.15, 13.4, 5.85, c.curb)
        rectangle(0.1, 4.35, 13.4, 5.65, c.roadEdge)
        rectangle(0.9, 2.6, 12.8, 3.4, c.asphalt)
        rectangle(0.8, 3, 1.6, 5, c.asphalt)
        rectangle(11.3, 3, 12.8, 5, c.asphalt)
        rectangle(3.7, 0.5, 8.3, 3.1, c.sidewalk)
        rectangle(0.8, 0.5, 3.3, 3.1, c.sidewalk)
        rectangle(10, 0.5, 12.3, 3.1, c.sidewalk)
        // Low perimeter posts, interrupted at the passenger entrance.
        if local.v == 0 && !(5...7).contains(where: { airport.designPlot($0, 0) == plot }) {
            let a = point(leftEdge, -0.4), b = point(rightEdge, -0.4)
            line(a.offset(0, -1), b.offset(0, -1), c.curb)
            line(a, a.offset(0, -3), c.outline)
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

        // A single ground pass keeps each guide line continuous across lot boundaries.
        stroke(11, 40, 166, 40, c.paint)
        stroke(15, 40, 15, 58, c.paint)
        stroke(158, 40, 158, 58, c.paint)
        stroke(81, 15, 81, 40, c.paint)
        stroke(77, 21, 85, 21, c.paint)
        for v in [53, 56] { stroke(11, v, 19, v, c.paint) }

        let white = c.color(0xD8D4BD, 0x92939A)
        stroke(8, 59, 177, 59, white)
        stroke(8, 75, 177, 75, white)
        for u in [52, 78, 104, 130] { stroke(u - 4, 67, u + 4, 67, white) }
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
        let local = airport.local(plot)
        func dot(_ u: Int, _ v: Int, _ z: Int = 0) -> Dot {
            airportDot(p, plot, airport, Double(local.u) + Double(u) / 16,
                       Double(local.v) + Double(v) / 16, Double(z))
        }
        func prism(_ u: Int, _ v: Int, _ w: Int, _ d: Int, _ base: Int, _ top: Int, _ roof: Ink) {
            let a = dot(u, v, top), b = dot(u + w, v, top)
            let e = dot(u + w, v + d, top), f = dot(u, v + d, top)
            polygon([f, e, dot(u + w, v + d, base), dot(u, v + d, base)], c.color(0xC0B8A1))
            polygon([b, e, dot(u + w, v + d, base), dot(u + w, v, base)], c.color(0x878C86))
            polygon([a, b, e, f], roof.mix(c.snow, c.weather.snowCover * 0.85))
            line(f, e, c.curb)
            line(b, e, c.outline)
        }
        let glass = c.color(0x527F85, 0x637D87)
        // Draw lights after every terrain tile, so both edges survive the ground pass.
        if c.night > 0.3 {
            for u in stride(from: 0, through: 12, by: 2) {
                for v in [3, 5] where plot == airport.designPlot(u, v) {
                    let margin = v == 5 ? 0.75 : 0.375
                    let ink = v == 5 ? c.color(0xD5C395, 0xF2D7A1) : c.color(0x7E95AA, 0x7AA0C4)
                    for edge in [-margin, margin] {
                        let light = airportDot(p, plot, airport, Double(u), Double(v) + edge)
                        span(light.x, light.x, light.y, ink)
                    }
                }
            }
        }
        if plot == airport.terminal {
            prism(-22, -6, 44, 13, 0, 9, c.color(0x79918C))
            // A continuous glazed concourse, roof plant and a short boarding pier.
            polygon([dot(-20, 7, 7), dot(20, 7, 7), dot(20, 7, 3), dot(-20, 7, 3)], glass)
            for u in stride(from: -19, through: 20, by: 4) { line(dot(u, 7, 7), dot(u, 7, 3), c.curb) }
            if c.night > 0.4 {
                for u in [-17, -5, 7, 19] { line(dot(u, 7, 5), dot(u + 1, 7, 5), c.gold) }
            }
            prism(-4, 7, 8, 10, 2, 5, c.color(0xA6ABA0))
            prism(-14, -3, 8, 5, 9, 11, c.color(0x8C9991))
            line(dot(-21, -6, 10), dot(21, -6, 10), c.shore)
            for u in [-12, 0, 12] {
                line(dot(u - 2, -7, 4), dot(u + 2, -7, 4), c.night > 0.4 ? c.gold : glass)
            }
        } else if plot == airport.tower {
            prism(-3, -3, 6, 6, 0, 19, c.curb)
            prism(-6, -6, 12, 12, 19, 25, c.color(0x73918D))
            polygon([dot(-5, 6, 24), dot(5, 6, 24), dot(5, 6, 21), dot(-5, 6, 21)], glass)
            polygon([dot(6, -5, 24), dot(6, 5, 24), dot(6, 5, 21), dot(6, -5, 21)], glass)
            line(dot(0, 0, 25), dot(0, 0, 32), c.outline)
            line(dot(-4, 0, 30), dot(4, 0, 30), c.curb)
        } else if airport.hangars.contains(plot) {
            prism(-11, -6, 22, 14, 0, 9, c.color(0x9B9E91))
            let ridgeA = dot(-11, 1, 13), ridgeB = dot(11, 1, 13)
            polygon([dot(-11, -6, 9), dot(11, -6, 9), ridgeB, ridgeA], c.color(0x8A9791))
            polygon([ridgeA, ridgeB, dot(11, 8, 9), dot(-11, 8, 9)], c.color(0xADB0A0))
            line(ridgeA, ridgeB, c.shore)
            polygon([dot(-8, 8, 7), dot(8, 8, 7), dot(8, 8), dot(-8, 8)], c.roadEdge)
            for u in [-7, -3, 1, 5] { line(dot(u, 8, 6), dot(u, 8, 1), c.sidewalk) }
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
