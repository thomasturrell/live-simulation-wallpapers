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

        let grassStrip = airport.stage == .airfield
        let gravel = c.paths.mix(c.grass(2), 0.40)
        let taxi = grassStrip ? c.grass(4).mix(gravel, 0.35) : c.asphalt
        let concrete = c.sidewalk.mix(c.asphalt, 0.36)
        let forecourt = grassStrip ? gravel : c.sidewalk.mix(c.paths, 0.35)
        for link in Airport.runwayLinks { surface(link, taxi) }
        surface(Airport.taxiway, taxi)
        if grassStrip {
            let track = Airport.Surface(Airport.taxiway.u, 2.78...3.22)
            surface(track, gravel.mix(taxi, 0.39))
            for u in [1.13, 11.69] {
                surface(Airport.Surface((u - 0.24)...(u + 0.24), 3.0...4.25), gravel.mix(taxi, 0.39))
            }
        }
        surface(Airport.hangarRamp, grassStrip ? gravel : concrete)
        surface(Airport.firstApron, grassStrip ? gravel : concrete)
        if !grassStrip {
            surface(Airport.Surface(4.03...4.86, 1.51...2.12), forecourt)
        }
        if airport.stage == .regional {
            surface(Airport.regionalApron, concrete)
            surface(Airport.serviceYard, c.asphalt.mix(c.sidewalk, 0.40))
            line(dot(11.10, 2.04), dot(12.70, 2.04), c.taxiwayPaint)
        }

        if grassStrip {
            surface(Airport.runway, c.grass(3).mix(c.foliage, 0.28))
            for v in [4.30, 4.82, 5.34] {
                surface(Airport.Surface(Airport.runway.u, v...(v + 0.32)), c.grass(1).mix(c.foliage, 0.17))
            }
        } else {
            surface(Airport.runway, c.asphalt.mix(c.grass(2), 0.17))
            surface(Airport.runway, c.asphalt.mix(c.roadEdge, 0.72), inset: 0.075)
        }

        surface(Airport.forecourt, forecourt)
        surface(Airport.parking, grassStrip ? gravel : c.asphalt.mix(c.sidewalk, 0.28))
        let entry = Airport.entranceCenter
        surface(Airport.Surface((entry - 0.37)...(entry + 0.37), -0.5 ... -0.07), c.asphalt)
        for u in [entry - 0.32, entry - 0.16, entry, entry + 0.16, entry + 0.32] {
            line(dot(u, -0.25), dot(u, -0.09), c.curb)
        }
        let parking = Airport.parking
        for u in [3.10, 3.55, 4.00, 4.45, 4.90] {
            line(dot(u, 0.68), dot(u, 1.26), c.curb)
        }
        line(dot(3.1, 1.28), dot(4.9, 1.28), c.curb)
        line(dot(parking.u.lowerBound, 1.37), dot(parking.u.upperBound, 1.37), c.foliage)
        for (u, v) in [(2.93, 0.38), (5.18, -0.31), (8.18, -0.24), (12.74, 0.34)] {
            let bed = dot(u, v)
            tile(bed, -4, -2, 8, 4, c.paths)
            line(bed.iso(-3, 0, 1), bed.iso(3, 0, 1), c.foliage)
            span(bed.x - 1, bed.x + 1, bed.y - 1, c.gold.mix(c.foliage, 0.62))
        }

        // Break the perimeter into an airfield boundary and short service fences.
        let wire = c.foliage.mix(c.curb, 0.35)
        for (start, end, v) in [(0.25, 13.1, 6.34), (0.23, 2.58, -0.35), (9.74, 13.14, -0.34)] {
            line(dot(start, v, 1.4), dot(end, v, 1.4), wire)
            for u in stride(from: start, through: end, by: 1.1) {
                line(dot(u, v), dot(u, v, 2.7), wire)
            }
        }

        if c.night > 0.26 {
            if !grassStrip {
                for u in stride(from: 0.62, through: 13.1, by: 1.20) {
                    for v in [Airport.runway.v.lowerBound + 0.03, Airport.runway.v.upperBound - 0.03] {
                        let light = dot(u, v)
                        span(light.x, light.x, light.y, c.color(0xD0C8A4, 0xBFC6BE))
                    }
                }
                for u in stride(from: 1.7, through: 12.9, by: 1.08) {
                    for v in [2.25, 3.77] {
                        let light = dot(u, v)
                        span(light.x, light.x, light.y, c.color(0x7799A5, 0x679FC0))
                    }
                }
            }
            for (u, ink) in [(0.58, c.color(0xA3C3A2, 0x97D2AD)), (12.98, c.color(0xBB7966, 0xD08A7B))] {
                for v in [4.30, 4.72, 5.28, 5.70] {
                    let light = dot(u, v)
                    span(light.x, light.x, light.y, ink)
                }
            }

            let amber = c.color(0xCDB183, 0xE4B984)
            let pools = [(entry, -0.23), (1.77, 1.37)] +
                (grassStrip ? [] : [(5.83, 1.14), (8.27, 0.99)]) +
                (airport.stage == .regional ? [(11.42, 1.35)] : [])
            for (u, v) in pools {
                for inset in [0.0, 0.10, 0.20] {
                    let glow = (grassStrip ? gravel : concrete).mix(amber, (0.12 + inset * 1.45) * c.night)
                    let w = 0.44 - inset, d = 0.26 - inset
                    polygon([dot(u - w, v), dot(u, v - d), dot(u + w, v), dot(u, v + d)], glow)
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
        if airport.stage == .airfield {
            let ink = c.color(0xCDC9A3, 0x72918B)
            for u in [14, 168] {
                for v in [58, 74] { stroke(u - 4, v, u + 4, v, ink) }
            }
            for u in [38, 67, 96, 125, 153] { stroke(u - 2, 67, u + 2, 67, ink) }
            return
        }
        let taxi = pixel(Airport.taxiwayCenter)
        stroke(pixel(Airport.taxiway.u.lowerBound) + 7, taxi, pixel(Airport.taxiway.u.upperBound) - 7, taxi, c.taxiwayPaint)
        let hold = pixel(Airport.holdShort.x)
        let runway = pixel(Airport.runwayCenter)
        let holdingLine = pixel(Airport.runway.v.lowerBound) - 1
        stroke(hold, taxi, hold, holdingLine, c.taxiwayPaint)
        let exit = pixel(Airport.runwayExit)
        stroke(exit, taxi, exit, runway - 9, c.taxiwayPaint)
        for v in [holdingLine, holdingLine + 2] { stroke(hold - 4, v, hold + 4, v, c.taxiwayPaint) }
        for gate in airport.openGates {
            let u = pixel(gate.stop.x), v = pixel(gate.stop.y)
            stroke(u, v - 4, u, taxi, c.taxiwayPaint)
            stroke(u - 4, v, u + 4, v, c.taxiwayPaint)
            for side in [gate.stand.u.lowerBound + 0.19, gate.stand.u.upperBound - 0.19] {
                let edge = pixel(side)
                stroke(edge, v + 4, edge, v + 8, c.curb)
            }
        }

        let white = c.color(0xD8D4BD, 0x92939A)
        let edge = c.color(0xADB4AA, 0x69798D)
        stroke(8, runway - 8, 177, runway - 8, edge)
        stroke(8, runway + 8, 177, runway + 8, edge)
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
        func prism(_ area: Airport.Surface, base: Double = 0, top: Double, roof: Ink,
                   walls: (Ink, Ink)? = nil) {
            let u = area.u.lowerBound, endU = area.u.upperBound
            let v = area.v.lowerBound, endV = area.v.upperBound
            let a = dot(u, v, top), b = dot(endU, v, top), e = dot(endU, endV, top), f = dot(u, endV, top)
            polygon([f, e, dot(endU, endV, base), dot(u, endV, base)], walls?.0 ?? c.color(0xD5C6A7))
            polygon([b, e, dot(endU, endV, base), dot(endU, v, base)], walls?.1 ?? c.color(0x9A9E8D))
            polygon([a, b, e, f], roof.mix(c.snow, c.weather.snowCover * 0.85))
            line(f, e, c.curb)
            line(b, e, c.outline)
        }
        let glass = c.color(0x527F85, 0x667F8F)
        let illuminated = c.color(0x7B9694, 0xDCB477)
        func windows(_ area: Airport.Surface, bottom: Double, top: Double, spacing: Double = 0.27) {
            let u = area.u.lowerBound + 0.08, endU = area.u.upperBound - 0.08
            let v = area.v.upperBound, back = area.v.lowerBound + 0.08
            let wall = area.u.upperBound
            polygon([dot(wall, back, top), dot(wall, v, top), dot(wall, v, bottom), dot(wall, back, bottom)], glass)
            polygon([dot(u, v, top), dot(endU, v, top), dot(endU, v, bottom), dot(u, v, bottom)], glass)
            for (index, start) in stride(from: u, to: endU, by: spacing).enumerated() {
                let end = min(endU, start + spacing - 0.06)
                if index % 3 != 1 {
                    polygon([dot(start + 0.03, v, top - 0.25), dot(end, v, top - 0.25),
                             dot(end, v, bottom + 0.28), dot(start + 0.03, v, bottom + 0.28)], illuminated)
                }
                line(dot(start, v, top), dot(start, v, bottom), c.curb)
            }
        }
        func roofStrip(_ u: ClosedRange<Double>, _ v: ClosedRange<Double>, _ highU: Double,
                       eave: Double, ridge: Double, light: Ink, shade: Ink) {
            let a = u.lowerBound, b = u.upperBound, back = v.lowerBound, front = v.upperBound
            polygon([dot(a, front, eave), dot(highU, front, ridge), dot(b, front, eave)],
                    c.color(0x668A8C, 0x485D73))
            polygon([dot(a, back, eave), dot(highU, back, ridge),
                     dot(highU, front, ridge), dot(a, front, eave)], light)
            polygon([dot(highU, back, ridge), dot(b, back, eave),
                     dot(b, front, eave), dot(highU, front, ridge)], shade)
            line(dot(highU, back, ridge), dot(highU, front, ridge), c.shore)
            line(dot(a, front, eave), dot(highU, front, ridge), light)
        }

        if plot == airport.hangarPlot {
            let hangar = Airport.hangar
            let u = hangar.u, v = hangar.v
            let mid = (u.lowerBound + u.upperBound) / 2
            let metal = c.roof(0xB9B9A8)
            prism(hangar, top: 10, roof: metal, walls: (c.color(0x9B9C90), c.color(0x788781)))
            roofStrip(u, v, mid, eave: 10, ridge: 15, light: metal, shade: c.roof(0x919F9B))
            let a = u.lowerBound + 0.15, b = u.upperBound - 0.15, front = v.upperBound
            polygon([dot(a, front, 7.6), dot(b, front, 7.6), dot(b, front), dot(a, front)], c.color(0x3E5157, 0x252D3D))
            line(dot(a, front, 8), dot(b, front, 8), c.color(0xDBD1AF, 0xB59C76))
            for post in [a, b] { line(dot(post, front), dot(post, front, 7.5), c.curb) }
            line(dot(a + 0.16, front, 1), dot(b - 0.16, front, 1), c.asphalt)
            for u in [mid - 0.48, mid + 0.48] {
                let lamp = dot(u, front, 7)
                span(lamp.x, lamp.x, lamp.y, c.night > 0.35 ? c.gold : c.shore)
            }
        }

        if plot == airport.terminal {
            if airport.stage == .airfield {
                let clubhouse = Airport.clubhouse
                prism(clubhouse, top: 6, roof: c.roof(0xA46D53),
                      walls: (c.color(0xCEB18B), c.color(0x9D896C)))
                roofStrip(clubhouse.u, clubhouse.v, 7.24, eave: 6, ridge: 10,
                          light: c.roof(0xB9835B), shade: c.roof(0x936853))
                windows(clubhouse, bottom: 1.8, top: 4.5, spacing: 0.40)
            } else {
                let canopy = Airport.canopy
                prism(canopy, base: 4.5, top: 6.5, roof: c.roof(0xC88D63),
                      walls: (c.color(0xD5AC78), c.color(0xB68060)))
                for u in [6.56, 7.69] {
                    line(dot(u, -0.37), dot(u, -0.37, 4.8), c.curb)
                }
                line(dot(6.51, -0.40, 6.5), dot(7.76, -0.40, 6.5), c.color(0xECD3A1, 0xAE8F61))

                let hall = Airport.headhouse
                prism(hall, top: 11, roof: c.roof(0xA7B8AB))
                windows(hall, bottom: 2, top: 8.2, spacing: 0.32)
                line(dot(hall.u.lowerBound, hall.v.upperBound, 9.0),
                     dot(hall.u.upperBound, hall.v.upperBound, 9.0), c.color(0xE2DCC1, 0x93958D))
                let roof = c.roof(0xAEC9B9)
                let roofShade = c.roof(0x739B96)
                if airport.stage == .regional {
                    let bays: [(ClosedRange<Double>, Double, Double)] = [
                        (5.46...6.58, 6.17, 15), (6.58...7.83, 7.40, 18), (7.83...8.93, 8.53, 15)
                    ]
                    for (u, crest, z) in bays {
                        roofStrip(u, 0.02...0.96, crest, eave: 11, ridge: z, light: roof, shade: roofShade)
                    }
                } else {
                    roofStrip(5.46...8.93, 0.02...0.96, 7.66, eave: 11, ridge: 15, light: roof, shade: roofShade)
                }
            }
        }
        if airport.stage != .airfield, plot == airport.anchor(for: Airport.lounge) {
            let lounge = Airport.lounge
            prism(lounge, top: 7.5, roof: c.roof(0xAAC0AB))
            windows(lounge, bottom: 2, top: 5.5)
        }
        if airport.stage == .regional, plot == airport.anchor(for: Airport.concourse) {
            let concourse = Airport.concourse
            prism(concourse, top: 8, roof: c.roof(0x829D94))
            windows(concourse, bottom: 2, top: 5.8)
            for u in [9.25, 9.62] {
                line(dot(u, 0.36, 8.5), dot(u, 0.83, 8.5), c.color(0xB8C8B8))
            }
        }
        if airport.stage != .airfield {
            for gate in airport.openGates where plot == airport.anchor(for: gate.pier) {
                prism(gate.pier, base: 1.6, top: 4.9, roof: c.roof(0xB7BDAA))
                let u = gate.pier.u, v = gate.pier.v.upperBound
                line(dot(u.lowerBound, v, 3), dot(u.upperBound, v, 3), c.night > 0.4 ? c.gold : glass)
                line(dot(u.upperBound, v, 2), dot(u.upperBound, v), c.outline)
            }
        }
        if airport.stage != .airfield, plot == airport.tower {
            let u = Airport.towerCenter.x, v = Airport.towerCenter.y
            let cab = Airport.towerCab
            prism(Airport.towerBase, top: 17, roof: c.curb, walls: (c.color(0xB58E72), c.color(0x947366)))
            line(dot(u + 0.26, v + 0.26, 4), dot(u + 0.26, v + 0.26, 14), c.color(0xCEBA95))
            prism(cab, base: 17, top: 24, roof: c.roof(0x648B89),
                  walls: (c.color(0x909F96), c.color(0x627D7C)))
            windows(cab, bottom: 18.7, top: 22.8, spacing: 0.20)
            line(dot(cab.u.lowerBound, cab.v.upperBound, 24), dot(cab.u.upperBound, cab.v.upperBound, 24), c.shore)
            line(dot(u, v, 24), dot(u, v, 31), c.outline)
            line(dot(u - 0.28, v, 28), dot(u + 0.25, v, 28), c.curb)
        }
        if airport.stage == .regional, plot == airport.servicePlot {
            let shop = Airport.workshop
            prism(shop, top: 7, roof: c.roof(0xA67358), walls: (c.color(0xAE8C6E), c.color(0x876F5A)))
            let front = shop.v.upperBound
            polygon([dot(11.46, front, 5.6), dot(12.05, front, 5.6), dot(12.05, front), dot(11.46, front)],
                    c.roadEdge)
            line(dot(11.44, front, 6), dot(12.08, front, 6), c.night > 0.35 ? c.gold : c.shore)
            line(dot(12.35, 0.26, 8), dot(12.35, 0.82, 8), c.color(0xCAB294))
            prism(Airport.Surface(12.48...12.82, 1.12...1.37), top: 3.8, roof: c.roof(0xD4C4A3),
                  walls: (c.color(0xB9AD93), c.color(0x918D80)))
        }

        if plot == airport.anchor(for: Airport.parking) {
            let cars: [(Double, UInt32)] = [(3.33, 0xBD7253), (4.24, 0x82A3A4), (4.69, 0xDBC593)]
            for (u, color) in cars.prefix(airport.stage == .airfield ? 1 : 3) {
                airportParkedCar(at: dot(u, 0.96), alongX: airport.alongY, color: c.color(color), palette: c)
            }
            let hedge = c.foliage
            line(dot(3.14, 1.46, 1.5), dot(4.76, 1.46, 1.5), hedge)
            parkLantern(at: dot(4.92, 0.42), palette: c)
        }
        for (u, v, style) in [(2.93, 0.10, 15), (8.65, -0.30, 31), (12.97, 0.65, 43)] {
            if plot == airport.designPlot(u, v) {
                lowPlanting(at: dot(u, v), style: style, palette: c)
            }
        }
        if plot == airport.parkedPropPlot {
            let point = Airport.parkedProp
            aircraft(at: dot(point.x, point.y), pose: airport.parkedPropPose, livery: 1, kind: .lightProp,
                     shadow: false, blink: false, palette: c)
        }
        let sock = Airport.windsock
        if plot == airport.designPlot(sock.x, sock.y) {
            line(dot(sock.x, sock.y), dot(sock.x, sock.y, 10.3), c.outline)
            let a = dot(sock.x, sock.y, 9.8), b = dot(sock.x + 0.47, sock.y, 6.6)
            polygon([a.offset(0, -1), a.offset(0, 2), b.offset(0, 1), b], c.color(0xBD674E, 0x9A6256))
            line(a.offset(1, 0), a.offset(1, 1), c.curb)
        }
    }

    mutating func airportWorksite(at p: Dot, airport: Airport, upgrade: Airport.Stage, progress: Int, palette c: Palette) {
        let area = Airport.worksite(for: upgrade)
        let a = airportDot(p, airport, area.u.lowerBound, area.v.upperBound)
        let b = airportDot(p, airport, area.u.upperBound, area.v.upperBound)
        line(a.offset(0, -2), b.offset(0, -2), c.clay)
        for stake in [a, b] { line(stake, stake.offset(0, -4), c.curb) }
        let stack = airportDot(p, airport, (area.u.lowerBound + area.u.upperBound) / 2, area.v.lowerBound + 0.17)
        for layer in 0...progress {
            line(stack.offset(-3, -layer - 1), stack.offset(3, 1 - layer), c.curb)
        }
    }

    mutating func airportParkedCar(at p: Dot, alongX: Bool, color: Ink, palette c: Palette) {
        let slope = alongX ? 1 : -1
        let a = p.offset(-3, -slope), b = p.offset(3, slope)
        line(a, b, c.roadEdge)
        line(a.offset(0, -1), b.offset(0, -1), color)
        line(p.offset(-1, -2), p.offset(2, slope - 2), color.mix(c.shore, 0.32))
        span(p.x - 1, p.x, p.y - 2, c.color(0x435F6B))
    }

    mutating func airportServiceCart(at p: Dot, alongX: Bool, palette c: Palette) {
        let slope = alongX ? 1 : -1
        line(p.offset(-3, -slope), p.offset(3, slope), c.roadEdge)
        line(p.offset(-3, -slope - 1), p.offset(3, slope - 1), c.color(0xD4BB82, 0xA68C65))
        span(p.x + 1, p.x + 2, p.y + slope - 2, c.curb)
        span(p.x - 2, p.x - 1, p.y - slope - 2, c.gold)
    }

    private mutating func parkLantern(at p: Dot, palette c: Palette) {
        line(p, p.offset(0, -7), c.outline)
        span(p.x, p.x + 1, p.y - 7, c.night > 0.3 ? c.gold : c.curb)
    }

    private mutating func lowPlanting(at p: Dot, style: Int, palette c: Palette) {
        let leaf = c.color(c.season.leafColor).mix(c.foliage, 0.35).mix(c.snow, c.weather.snowCover * 0.5)
        span(p.x - 4, p.x + 4, p.y, c.shadow)
        for (x, y) in [(-3, 0), (0, -2), (3, -1)] {
            span(p.x + x - 1, p.x + x + 1, p.y + y - 1, leaf)
            span(p.x + x - 1, p.x + x + 1, p.y + y, c.foliage)
            if c.season.flowers > 0.4, (style + x).isMultiple(of: 2) {
                span(p.x + x, p.x + x, p.y + y - 2, c.gold)
            }
        }
    }
}
