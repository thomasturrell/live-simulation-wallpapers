import CityEngine

extension Pixels {
    mutating func aircraft(at p: Dot, pose: Aircraft.Pose, livery: Int, blink: Bool, palette c: Palette) {
        let dx = pose.dx, dy = pose.dy
        let scale = 6.0 / 7.0
        func dot(_ along: Double, _ across: Double, _ z: Double = 0) -> Dot {
            let u = (dx * along - dy * across) * scale
            let v = (dy * along + dx * across) * scale
            let height = (z + across * pose.bank) * scale
            return p.projectedOffset(u - v, (u + v) * 0.5 - height)
        }
        let white = c.color(0xE0DDC9, 0x9DA8B3)
        let shade = c.color(0x9DAEAC, 0x596C7E)
        // Lift the livery tones away from the river colours, especially the teal tail.
        let accent = c.color([0x477C83, 0xAD6253, 0xB49755, 0x677A9A][livery]).mix(white, 0.34)
        let engine = c.color(0x72858B, 0x5B6D7E)
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
