import CityEngine

private struct Footprint {
    let u: Int, v: Int, w: Int, d: Int
    var farU: Int { u + w }
    var farV: Int { v + d }

    func points(_ p: Dot, _ z: Int) -> [Dot] {
        [p.iso(u, v, z), p.iso(farU, v, z), p.iso(farU, farV, z), p.iso(u, farV, z)]
    }
}

private struct Masonry {
    let roof: Ink, edge: Ink, light: Ink, shade: Ink, trim: Ink
    init(_ c: Palette, _ roof: UInt32, _ edge: UInt32, _ light: UInt32, _ shade: UInt32, _ trim: UInt32) {
        self.roof = c.color(roof)
        self.edge = c.color(edge)
        self.light = c.color(light)
        self.shade = c.color(shade)
        self.trim = c.color(trim)
    }
}

extension Pixels {
    mutating func building(_ b: Building, zone: Zone, at p: Dot, palette c: Palette) {
        switch zone {
        case .homes:
            if b.level == 1 { house(at: p, style: b.style, palette: c) }
            else if b.level == 2 { terrace(at: p, style: b.style, palette: c) }
            else { apartments(at: p, style: b.style, palette: c) }
        case .commerce: commercial(at: p, level: b.level, style: b.style, palette: c)
        case .industry: industry(at: p, style: b.style, palette: c)
        case .civic: civic(at: p, style: b.style, palette: c)
        }
    }

    private mutating func prism(_ p: Dot, _ footprint: Footprint, base: Int = 0, top: Int, _ colors: Masonry) {
        let bottom = footprint.points(p, base)
        let high = footprint.points(p, top)
        polygon([high[3], high[2], bottom[2], bottom[3]], colors.light)
        polygon([high[2], high[1], bottom[1], bottom[2]], colors.shade)
        polygon(high, colors.roof)
        line(high[3], high[2], colors.trim)
        line(high[2], high[1], colors.edge)
        line(bottom[3], bottom[2], colors.edge)
        line(bottom[2], bottom[1], colors.edge)
    }

    private mutating func gable(_ p: Dot, _ f: Footprint, at z: Int, rise: Int, alongX: Bool, _ m: Masonry) {
        let base = f.points(p, z)
        if alongX {
            let left = p.iso(f.u, (f.v + f.farV) / 2, z + rise)
            let right = p.iso(f.farU, (f.v + f.farV) / 2, z + rise)
            polygon([base[1], right, base[2]], m.shade)
            polygon([base[0], base[1], right, left], m.edge)
            polygon([left, right, base[2], base[3]], m.roof)
            line(left, right, m.trim)
            line(base[3], base[2], m.edge)
            line(right, base[2], m.edge)
        } else {
            let back = p.iso((f.u + f.farU) / 2, f.v, z + rise)
            let front = p.iso((f.u + f.farU) / 2, f.farV, z + rise)
            polygon([base[3], front, base[2]], m.light)
            polygon([base[0], back, front, base[3]], m.roof)
            polygon([back, base[1], base[2], front], m.edge)
            line(back, front, m.trim)
            line(front, base[2], m.edge)
        }
    }

    private mutating func windows(_ p: Dot, _ f: Footprint, floors: [Int], pitch: Int, pane: Int, height: Int,
                                  style: Int, c: Palette, trim: Ink, glass: UInt32 = 0x588086) {
        for z in floors {
            for offset in stride(from: 1, through: f.w - pane - 1, by: pitch) {
                let a = p.iso(f.u + offset, f.farV, z)
                let b = p.iso(f.u + offset + pane, f.farV, z)
                let lit = (offset * 41 + z * 13 + style) % 17
                let pane = windowLight(c.color(glass, 0x2C4055), index: lit, palette: c)
                aperture(a, b, height, trim, pane)
            }
            for offset in stride(from: 1, through: f.d - pane - 1, by: pitch) {
                let a = p.iso(f.farU, f.v + offset, z)
                let b = p.iso(f.farU, f.v + offset + pane, z)
                let lit = (offset * 19 + z * 23 + style * 3) % 19
                let pane = windowLight(c.color(0x47636F, 0x242E45), index: lit, palette: c)
                aperture(a, b, height, trim.mix(c.outline, 0.38), pane)
            }
        }
    }

    private func windowLight(_ glass: Ink, index: Int, palette: Palette) -> Ink {
        guard index < 6 else { return glass }
        let strength = min(1, max(0, (palette.night - 0.29 - Double(index) * 0.055) * 4))
        return glass.mix(palette.gold, strength * (index.isMultiple(of: 2) ? 0.89 : 0.61))
    }

    private mutating func aperture(_ a: Dot, _ b: Dot, _ height: Int, _ trim: Ink, _ glass: Ink) {
        polygon([a, b, b.offset(0, height), a.offset(0, height)], glass)
        line(a, b, trim)
        line(a.offset(0, height), b.offset(0, height), trim)
    }

    private mutating func house(at p: Dot, style: Int, palette c: Palette) {
        let choices = [
            Masonry(c, 0xB46952, 0x784D48, 0xE3C5A2, 0xAC8C78, 0xDA956D),
            Masonry(c, 0x638084, 0x425962, 0xE1D1AE, 0xB29E86, 0x91A7A0),
            Masonry(c, 0x916C56, 0x5B5253, 0xBD8770, 0x926758, 0xBA9970),
            Masonry(c, 0x6C756F, 0x475B5D, 0xD2BF96, 0xA6A07D, 0x959983),
            Masonry(c, 0x994D42, 0x693F43, 0xE0CAA1, 0xAC8C77, 0xBE755B)
        ]
        let m = choices[style % choices.count]
        let f = Footprint(u: -5, v: -5, w: 10 + style % 3, d: 10)
        if style % 3 == 0 {
            prism(p, Footprint(u: -7, v: -6, w: 5, d: 8), top: 5, m)
        }
        prism(p, f, top: 7, m)
        let roof = Footprint(u: f.u - 1, v: f.v - 1, w: f.w + 2, d: f.d + 2)
        gable(p, roof, at: 7, rise: 4 + style % 3, alongX: style % 2 == 0, m)
        windows(p, f, floors: [5], pitch: 4, pane: 3, height: 3, style: style, c: c, trim: m.light)
        let door = p.iso(f.u + 4, f.farV, 0)
        box(door.offset(0, -4), 2, 4, c.outline)
        span(door.x - 1, door.x + 1, door.y, c.paths)
        if style.isMultiple(of: 3) {
            let chimney = p.iso(f.farU - 3, f.v + 4, 10)
            box(chimney.offset(0, -5), 3, 6, c.clay)
            span(chimney.x - 1, chimney.x + 3, chimney.y - 5, m.shade)
        }
    }

    private mutating func terrace(at p: Dot, style: Int, palette c: Palette) {
        let m = style.isMultiple(of: 2)
            ? Masonry(c, 0x887579, 0x585965, 0xB9856F, 0x966B62, 0xD1AE8F)
            : Masonry(c, 0xA06753, 0x624D4C, 0xD6B289, 0xA78B70, 0xE3CC9E)
        let f = Footprint(u: -7, v: -5, w: 14, d: 10)
        prism(p, f, top: 13, m)
        gable(p, Footprint(u: -8, v: -6, w: 16, d: 12), at: 13, rise: 5, alongX: true, m)
        windows(p, f, floors: [5, 10], pitch: 4, pane: 2, height: 3, style: style, c: c, trim: m.trim)
        for u in [-3, 2] {
            line(p.iso(u, 5, 1), p.iso(u, 5, 12), m.shade)
            let entry = p.iso(u - 2, 5)
            box(entry.offset(0, -4), 2, 4, c.outline)
            span(entry.x - 1, entry.x + 1, entry.y, c.curb)
            let stack = p.iso(u, -1, 17)
            box(stack.offset(0, -3), 2, 4, m.edge)
            span(stack.x - 1, stack.x + 2, stack.y - 3, m.trim)
        }
    }

    private mutating func apartments(at p: Dot, style: Int, palette c: Palette) {
        let m = style % 2 == 0
            ? Masonry(c, 0xAD9D84, 0x7A736E, 0xCB8D72, 0x9A7067, 0xE1BB92)
            : Masonry(c, 0x989887, 0x666E6C, 0xD6C5A3, 0xA2A092, 0xE6D6B6)
        let f = Footprint(u: -6, v: -6, w: 12, d: 12)
        let h = 20 + style % 7
        prism(p, Footprint(u: -7, v: -7, w: 15, d: 15), top: 2, m)
        prism(p, f, top: h, m)
        let floors = Array(stride(from: 7, through: h - 3, by: 5))
        windows(p, f, floors: floors, pitch: 4, pane: 3, height: 3, style: style, c: c, trim: m.trim)
        for z in floors {
            let balcony = p.iso(-6, 7, z - 3)
            line(balcony, balcony.offset(7, 3), m.trim)
            line(balcony.offset(0, 1), balcony.offset(7, 4), m.edge)
        }
        prism(p, Footprint(u: -3, v: -3, w: 4, d: 5), base: h, top: h + 4, m)
        let antenna = p.iso(3, 0, h)
        line(antenna, antenna.offset(0, -5), c.outline)
        span(antenna.x - 2, antenna.x + 2, antenna.y - 4, c.outline)
        box(p.iso(0, 7, 5), 3, 5, m.edge)
    }

    private mutating func commercial(at p: Dot, level: Int, style: Int, palette c: Palette) {
        if level == 5 && style == Building.riversideTowerStyle {
            riversideTower(at: p, palette: c)
            return
        }
        let choices = [
            Masonry(c, 0xA7ADA4, 0x667D7A, 0x83A29C, 0x5C787B, 0xC3C2A8),
            Masonry(c, 0xB7A592, 0x79756F, 0xCDBBA7, 0x9B9289, 0xE6D2AE),
            Masonry(c, 0x888D91, 0x56646F, 0x8D9FAB, 0x627788, 0xB6C3C0),
            Masonry(c, 0xAD8D77, 0x805E5A, 0xB98573, 0x936768, 0xDAB199)
        ]
        let m = choices[style % 4]
        let podium = Footprint(u: -8, v: -7, w: 15, d: 14)
        let f = Footprint(u: -6 + style % 2, v: -6, w: 12, d: 11 + style % 3)
        let h = [0, 9, 17, 26, 39, 50][level] + style % (level + 4)
        prism(p, podium, top: 6, m)
        prism(p, f, base: 6, top: h, m)
        if level >= 4 {
            let crown = Footprint(u: f.u + 1, v: f.v + 1, w: f.w - 2, d: f.d - 2)
            prism(p, crown, base: h, top: h + (style % 3 == 0 ? 6 : 2), m)
            if style % 3 == 0 {
                let mast = p.iso(0, 0, h + 6)
                line(mast, mast.offset(0, -8), m.edge)
                span(mast.x, mast.x, mast.y - 8, c.color(0xCF826B, 0xD07B61))
            }
        }
        if style % 3 != 0 && level < 4 {
            prism(p, Footprint(u: -2, v: -3, w: 4, d: 5), base: h, top: h + 2, m)
            line(p.iso(-2, -3, h + 2), p.iso(2, -3, h + 2), m.edge)
        }
        windows(p, f, floors: Array(stride(from: 10, through: max(10, h - 3), by: 4)).filter { $0 < h },
                pitch: level >= 3 ? 3 : 4, pane: 2, height: 2, style: style, c: c, trim: m.trim, glass: 0x496E7D)
        if level < 3 {
            let awnings: [UInt32] = [0x9D5C53, 0x64847C, 0xB98C55, 0x6C748D]
            for u in -6...5 {
                let top = p.iso(u, 7, 6)
                line(top, p.iso(u, 9, 4), c.color(u.isMultiple(of: 3) ? 0xE1C49E : awnings[style % 4]))
            }
        } else {
            line(p.iso(-8, 7, 5), p.iso(7, 7, 5), m.trim)
        }
        windows(p, podium, floors: [4], pitch: 5, pane: 4, height: 3, style: style, c: c, trim: m.shade)
    }

    private mutating func riversideTower(at p: Dot, palette c: Palette) {
        let stone = Masonry(c, 0xB2A792, 0x827D77, 0xD9C7AA, 0xAA9B8D, 0xE8D8AD)
        let copper = Masonry(c, 0x748E81, 0x455D61, 0x9FB0A0, 0x6B7E78, 0xADC0AA)
        let lobby = Footprint(u: -8, v: -7, w: 16, d: 14)
        let wings = Footprint(u: -8, v: -6, w: 16, d: 12)
        let f = Footprint(u: -6, v: -5, w: 12, d: 11)
        prism(p, lobby, top: 8, stone)
        prism(p, wings, base: 8, top: 24, stone)
        windows(p, wings, floors: [12, 17, 22], pitch: 4, pane: 2, height: 3, style: 119, c: c, trim: stone.light)
        prism(p, f, base: 8, top: 46, stone)
        windows(p, f, floors: [13, 19, 25, 31, 37, 43], pitch: 4, pane: 2,
                height: 4, style: 119, c: c, trim: stone.trim)
        for u in [-5, -1, 3] { line(p.iso(u, 6, 24), p.iso(u, 6, 46), stone.trim) }
        prism(p, Footprint(u: -4, v: -4, w: 8, d: 8), base: 46, top: 53, stone)
        prism(p, Footprint(u: -3, v: -3, w: 6, d: 6), base: 53, top: 58, copper)
        prism(p, Footprint(u: -2, v: -2, w: 4, d: 4), base: 58, top: 62, copper)
        let finial = p.iso(0, 0, 62)
        line(finial, finial.offset(0, -5), stone.trim)
        let entrance = p.iso(-2, 7)
        aperture(entrance.offset(0, -6), p.iso(3, 7, 6), 6, stone.edge, c.color(0x607D82, 0x635E59))
    }

    private mutating func industry(at p: Dot, style: Int, palette c: Palette) {
        let m = Masonry(c, style % 2 == 0 ? 0x908B81 : 0xA29580, 0x676A6A, 0xB58B76, 0x896F67, 0xC7AE8E)
        let f = Footprint(u: -7, v: -6, w: 14, d: 13)
        prism(p, f, top: 8, m)
        for u in [-7, 0] {
            gable(p, Footprint(u: u, v: -7, w: 7, d: 15), at: 8, rise: 4, alongX: false, m)
            let skylight = p.iso(u + 4, -3, 11)
            line(skylight, skylight.offset(-4, 2), c.color(0x526F79))
            line(skylight.offset(1, 1), skylight.offset(-3, 3), c.color(0x6D8891))
        }
        for u in [-5, 2] {
            let door = p.iso(u, 7, 5)
            aperture(door, p.iso(u + 4, 7, 5), 5, m.edge, c.color(0x77736E))
            line(door.offset(0, 2), p.iso(u + 4, 7, 3), m.shade)
        }
        if style.isMultiple(of: 4) {
            prism(p, Footprint(u: 4, v: -5, w: 3, d: 3), base: 9, top: 22, m)
            let stack = p.iso(4, -2, 20)
            line(stack, stack.offset(3, 1), c.clay)
            line(stack.offset(0, 1), stack.offset(3, 2), m.trim)
        } else {
            let crate = Footprint(u: -7, v: 8, w: 3, d: 2)
            prism(p, crate, top: 2, m)
        }
    }

    private mutating func civic(at p: Dot, style: Int, palette c: Palette) {
        let m = Masonry(c, 0x73897E, 0x465F63, 0xDCC8AC, 0xAA9B90, 0xEEE0BA)
        let f = Footprint(u: -7, v: -6, w: 14, d: 13)
        prism(p, Footprint(u: -9, v: -8, w: 18, d: 17), top: 2, m)
        prism(p, f, base: 2, top: 13, m)
        gable(p, f, at: 13, rise: 6, alongX: style != 23, m)
        windows(p, f, floors: [9], pitch: 4, pane: 3, height: 5, style: style, c: c, trim: m.trim)
        if style == 39 {
            for offset in [1, 5, 9] {
                let column = p.iso(f.u + offset, f.farV + 1, 0)
                line(column, column.offset(0, -8), m.trim)
            }
        } else {
            let tower = Footprint(u: -3, v: 0, w: 6, d: 6)
            prism(p, tower, base: 12, top: style == 23 ? 26 : 24, m)
            let z = style == 23 ? 26 : 24
            let top = p.iso(0, 3, z + (style == 23 ? 7 : 12))
            let corners = tower.points(p, z)
            polygon([corners[3], top, corners[2]], m.roof)
            polygon([corners[2], top, corners[1]], m.edge)
            let clock = p.iso(0, 6, z - 3)
            span(clock.x - 1, clock.x + 1, clock.y, m.trim)
            span(clock.x, clock.x, clock.y - 1, m.trim)
            span(clock.x, clock.x, clock.y + 1, m.edge)
        }
    }

    mutating func site(at p: Dot, stage: Int, road: Bool, palette c: Palette) {
        tile(p, -7, -7, 14, 14, c.color(0xB49A70, 0x584D51))
        tile(p, -5, -5, 10, 10, c.color(0x9E8165, 0x493F49))
        for u in stride(from: -7, through: 7, by: 3) {
            let peg = p.iso(u, 7)
            line(peg, peg.offset(0, -3), c.outline)
            span(peg.x, peg.x + 1, peg.y - 2, c.gold)
        }
        if road {
            if stage > 0 { tile(p, -6, -2, 12, 5, c.asphalt) }
            return
        }
        let m = Masonry(c, 0xACA18A, 0x696D6C, 0xB9AC92, 0x878477, 0xD4C6A8)
        prism(p, Footprint(u: -5, v: -5, w: 10, d: 10), top: [1, 4, 8][stage], m)
        let base = p.iso(5, -4)
        let joint = base.offset(0, -16)
        line(base, joint, c.outline)
        line(base.offset(-1, -2), joint.offset(-1, 0), c.color(0xC89A52))
        line(joint.offset(-8, 1), joint.offset(4, -2), c.gold)
        line(joint.offset(-7, 1), joint.offset(-7, 5 + stage), c.outline)
    }
}
