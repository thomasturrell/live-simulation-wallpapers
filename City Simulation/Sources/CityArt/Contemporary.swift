import CityEngine

public enum CitySkin: String, CaseIterable, Sendable {
    case original, contemporary

    public var title: String { rawValue.capitalized }
}

extension Pixels {
    mutating func contemporaryBuilding(_ building: Building, zone: Zone, at p: Dot, palette c: Palette) {
        let style = building.style
        switch zone {
        case .homes:
            contemporaryHomes(p, level: building.level, style: style, c: c)
        case .commerce:
            contemporaryOffice(p, level: building.level, style: style, c: c)
        case .industry:
            distributionShed(p, style: style, c: c)
        case .civic:
            riversideHall(p, style: style, c: c)
        }
    }

    private func brick(_ style: Int, _ c: Palette) -> Masonry {
        switch style % 3 {
        case 0: return Masonry(c, 0xB9C4C3, 0x737C81, 0xF1DFC0, 0xB2A693, 0xF6EBCE)
        case 1: return Masonry(c, 0xAAB7BB, 0x735953, 0xDE916B, 0xAC6353, 0xF0C29C)
        default: return Masonry(c, 0x9BAAB3, 0x705953, 0xCF7855, 0x9B5448, 0xE8A77D)
        }
    }

    private mutating func solarArray(_ p: Dot, u: Int, v: Int, z: Int, c: Palette) {
        let roof = p.offset(0, -z)
        tile(roof, u, v, 8, 5, c.roof(0x294964))
        line(roof.iso(u, v), roof.iso(u + 8, v), c.roof(0x7DADC4))
        line(roof.iso(u + 4, v), roof.iso(u + 4, v + 4), c.roof(0x638BA5))
    }

    private mutating func contemporaryHomes(_ p: Dot, level: Int, style: Int, c: Palette) {
        let m = brick(style, c)
        let f = Footprint(u: level == 1 ? -5 : -7, v: -5, w: level == 1 ? 11 : 14, d: 11)
        let h = [0, 7, 12, 21][level] + style % 3
        prism(p, f, top: h, m)
        windows(p, f, floors: Array(stride(from: 5, through: h - 1, by: 6)),
                pitch: 5, pane: 3, height: 4, style: style, c: c, trim: m.light, glass: 0x496F82)
        for u in level == 2 ? [-5, 2] : [f.u + 2] {
            let door = p.iso(u, f.farV, 4)
            box(door, 2, 4, c.color(0x394F59))
            line(door.offset(-1, -1), door.offset(3, 1), m.trim)
        }

        if level < 3 && (style / 3).isMultiple(of: 2) {
            let slate = Masonry(c, 0x596B77, 0x394D5E, 0xCF916E, 0xAD816C, 0x8B9BA4)
            gable(p, f, at: h, rise: 4, alongX: true, slate)
            let flue = p.iso(-3, -2, h + 4)
            box(flue.offset(0, -2), 2, 3, m.shade)
        } else {
            // A recessed roof behind a light parapet leaves a readable rim at 1×.
            tile(p.offset(0, -h), f.u + 1, f.v + 1, f.w - 2, f.d - 2, c.roof(0x83929B))
            if style.isMultiple(of: 4) {
                solarArray(p, u: f.u + 2, v: -3, z: h + 1, c: c)
            } else if level == 3 {
                prism(p, Footprint(u: -5, v: -4, w: 7, d: 6), base: h, top: h + 3, m)
            }
        }

        if level == 3 {
            let recess = c.color(0x344952, 0x242F42)
            for z in stride(from: 8, through: h - 2, by: 6) {
                let a = p.iso(f.u + 1, f.farV, z)
                let b = p.iso(f.u + 7, f.farV, z)
                aperture(a, b, 4, m.shade, recess)
                let pane = windowLight(c.color(0x648492), index: (style + z) % 11, palette: c)
                line(a.offset(2, 2), b.offset(-1, 1), pane)
                line(a.offset(0, 4), b.offset(0, 4), m.trim)
                line(a.offset(0, 3), a.offset(0, 1), m.trim)
            }
        }
    }

    private mutating func contemporaryOffice(_ p: Dot, level: Int, style: Int, c: Palette) {
        let m = brick(style, c)
        let podium = Footprint(u: -7, v: -7, w: 15, d: 14)
        let base = level < 3 ? 7 : 9
        prism(p, podium, top: base, m)
        windows(p, podium, floors: [base - 2], pitch: 6, pane: 4, height: 5,
                style: style, c: c, trim: m.trim, glass: 0x35576A)
        let glass = Masonry(c, 0xB8CAD3, 0x475B71, style.isMultiple(of: 3) ? 0x7196AC : 0x6792A2,
                            0x40627C, 0xC8D9DA)
        let f = Footprint(u: -6, v: -6, w: 12 + style % 2, d: 11 + style % 3)
        let h = [0, 9, 15, 23, 33, 43][level] + style % 5
        // Some blocks retain a brick street frontage and a projecting glazed bay.
        let brickFront = style % 5 == 2 || style == Building.riversideTowerStyle
        if brickFront {
            prism(p, f, base: base, top: h, m)
            windows(p, f, floors: Array(stride(from: base + 5, through: h - 1, by: 6)),
                    pitch: 5, pane: 3, height: 4, style: style, c: c, trim: m.light, glass: 0x486F83)
            let bay = Footprint(u: f.u + 4, v: f.v, w: f.w - 4, d: f.d + 1)
            glassStoreys(p, bay, base: base, top: h - 1, style: style, m: glass, c: c)
        } else {
            glassStoreys(p, f, base: base, top: h, style: style, m: glass, c: c)
        }
        if level >= 3 {
            let upper = Footprint(u: -5, v: -5, w: f.w - 3, d: f.d - 3)
            let crown = h + 5 + style % 4
            glassStoreys(p, upper, base: h, top: crown, style: style + 1, m: glass, c: c)
            if level == 5 || style.isMultiple(of: 3) {
                let plant = Footprint(u: -4, v: -4, w: 5, d: 6)
                let cap = crown + (style == Building.riversideTowerStyle ? 9 : 3)
                prism(p, plant, base: crown, top: cap, glass)
                line(p.iso(-3, -3, cap), p.iso(-3, 0, cap), c.roof(0x70879B))
            } else {
                tile(p.offset(0, -crown), -4, -4, 4, 3, c.roof(0x93A9B6))
            }
        } else if style.isMultiple(of: 4) {
            solarArray(p, u: -4, v: -4, z: h + 1, c: c)
        }
    }

    private mutating func glassStoreys(_ p: Dot, _ f: Footprint, base: Int, top: Int,
                                       style: Int, m: Masonry, c: Palette) {
        prism(p, f, base: base, top: top, m)
        // Broad reflected strips run behind continuous floor bands on both faces.
        let reflection = c.color(0x98BDCC, 0x415972)
        let u = f.u + 2 + style % 3
        polygon([p.iso(u, f.farV, top - 1), p.iso(u + 3, f.farV, top - 1),
                 p.iso(u + 3, f.farV, base + 1), p.iso(u, f.farV, base + 1)], reflection)
        for z in stride(from: base + 4, through: top - 2, by: 6) {
            let a = p.iso(f.u, f.farV, z), b = p.iso(f.farU, f.farV, z), d = p.iso(f.farU, f.v, z)
            line(a.offset(0, 1), b.offset(0, 1), m.edge)
            line(a, b, m.trim)
            line(b, d, c.color(0x89A4B4))
            let sidePane = p.iso(f.farU, f.v + 3, z + 2)
            let sideGlass = windowLight(c.color(0x7593A8, 0x38485E), index: (z + style) % 11, palette: c)
            line(sidePane, sidePane.offset(-3, 1), sideGlass)
            let frontPane = p.iso(f.u + 2, f.farV, z - 2)
            let frontGlass = windowLight(reflection, index: (z / 3 + style) % 9, palette: c)
            line(frontPane, frontPane.offset(3, 1), frontGlass)
            line(frontPane.offset(0, 1), frontPane.offset(3, 2), frontGlass)
        }
    }

    private mutating func distributionShed(_ p: Dot, style: Int, c: Palette) {
        let metal = Masonry(c, 0xB7C7CC, 0x516473, 0x97ABAD, 0x657D89, 0xCFD9D4)
        let f = Footprint(u: -7, v: -6, w: 15, d: 13)
        let h = 8 + style % 3
        prism(p, f, top: h, metal)
        for u in stride(from: -5, through: 5, by: 4) {
            line(p.iso(u, -5, h), p.iso(u, 5, h), c.roof(0x92A9B3))
        }
        for u in [-5, 2] {
            let left = p.iso(u, 7, 5), right = p.iso(u + 4, 7, 5)
            aperture(left, right, 5, metal.edge, metal.shade)
            line(left.offset(0, 2), right.offset(0, 2), metal.light)
            line(left.offset(0, -1), right.offset(0, -1), c.color(0xDBA85F))
        }
        if style.isMultiple(of: 4) {
            prism(p, Footprint(u: 4, v: -5, w: 3, d: 3), base: h, top: 22, metal)
        } else if style.isMultiple(of: 3) {
            solarArray(p, u: -5, v: -3, z: h + 1, c: c)
        } else {
            tile(p.offset(0, -h), -4, -4, 3, 8, c.roof(0x7299A6))
        }
    }

    private mutating func riversideHall(_ p: Dot, style: Int, c: Palette) {
        let m = Masonry(c, 0x97A6A3, 0x667977, 0xE1CDA8, 0xA99E8B, 0xF0DFC2)
        let f = Footprint(u: -7, v: -6, w: 15, d: 13)
        prism(p, f, top: 12, m)
        windows(p, f, floors: [9], pitch: 4, pane: 3, height: 7, style: style, c: c, trim: m.light)
        let hall = Footprint(u: -6, v: -5, w: style == 39 ? 12 : 7, d: 8)
        prism(p, hall, base: 12, top: 19, m)
        gable(p, hall, at: 19, rise: 3, alongX: false, m)
    }
}
