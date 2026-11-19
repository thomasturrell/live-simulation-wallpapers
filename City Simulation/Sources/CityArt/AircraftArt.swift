import CityEngine
import Foundation

extension Pixels {
    mutating func aircraft(at p: Dot, pose: Aircraft.Pose, livery: Int, kind: Aircraft.Kind = .jet,
                           shadow: Bool, blink: Bool, palette c: Palette) {
        guard shadow else {
            aircraftShape(at: p, pose: pose, livery: livery, kind: kind, shadow: false, blink: blink, palette: c)
            return
        }
        let opacity = 0.3 * max(0, 1 - pose.altitude / 60)
        guard opacity > 0, p.x + 20 >= 0, p.x - 20 < width, p.y + 12 >= 0, p.y - 12 < height else { return }
        // Rasterise a single silhouette, then shade each covered ground pixel once.
        // Sampling one ground colour made the entire shadow flash over runway markings;
        // blending individual overlapping wings and fuselage would darken their overlaps twice.
        var mask = Pixels(width: 41, height: 25, background: Ink(0))
        mask.aircraftShape(at: Dot(20, 12), pose: pose, livery: livery, kind: kind, shadow: true, blink: false, palette: c)
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

    private mutating func aircraftShape(at p: Dot, pose: Aircraft.Pose, livery: Int, kind: Aircraft.Kind,
                                        shadow: Bool, blink: Bool, palette c: Palette) {
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
        if kind != .jet {
            let commuter = kind == .turboprop
            let nose = commuter ? 8.8 : 6.2
            let wing = commuter ? 9.5 : 6.6
            let wingZ = commuter ? 2.9 : 2.5
            let cabin = c.color(0x425D68, 0x4C667C)
            polygon([dot(nose, 0, 1), dot(nose - 2, -1.3, 1), dot(-nose + 1.5, -1.1, 1),
                     dot(-nose, 0, 1), dot(-nose + 1.5, 1.1, 1), dot(nose - 2, 1.3, 1)], shade)
            line(dot(-nose + 1, 0, 2), dot(nose - 1, 0, 2), white)
            polygon([dot(-nose + 4, 0, 2), dot(-nose + 1, 0, commuter ? 5.7 : 4.5),
                     dot(-nose, 0, commuter ? 5.4 : 4.2), dot(-nose + 0.5, 0, 2)], accent)
            for side in [-1.0, 1.0] {
                polygon([dot(1.6, 0, wingZ), dot(0.4, side * wing, wingZ),
                         dot(-1.8, side * wing, wingZ), dot(-2.8, 0, wingZ)], side == near ? white : shade)
                line(dot(-nose + 2, 0, 2), dot(-nose + 0.7, side * 3.1, 2), accent)
                if commuter {
                    line(dot(-3, side * 3.9, 2), dot(2.8, side * 3.9, 2), engine)
                    line(dot(2.9, side * 3.9, 0.8), dot(2.9, side * 3.9, 4.1), shadow ? shadowInk : shade)
                }
                if pose.gear && !shadow {
                    line(dot(-0.9, side * 1.6, -0.4), dot(-0.3, side * 1.6, -0.4), outline)
                }
                if c.night > 0.35 && !shadow {
                    let tip = dot(-0.4, side * wing, wingZ)
                    span(tip.x, tip.x, tip.y, side < 0 ? c.color(0xB15E4E, 0xCB7863) : c.color(0x71A286, 0x90B69E))
                }
            }
            if !commuter {
                line(dot(nose, 0, 0.2), dot(nose, 0, 2.9), shadow ? shadowInk : shade)
            }
            if !shadow {
                line(dot(3.2, -near * 0.8, 2.1), dot(4.0, near * 0.8, 2.1), cabin)
                line(dot(-3.7, near, 1), dot(-2.6, near, 1), accent)
            }
            return
        }
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
