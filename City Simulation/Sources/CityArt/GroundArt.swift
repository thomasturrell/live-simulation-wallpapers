import CityEngine

func parkWalks(at plot: Plot) -> (across: Bool, down: Bool) {
    (plot.y % 4 == 1, plot.x % 4 == 2)
}

extension Pixels {
    mutating func ground(_ lot: Lot, at p: Dot, plot: Plot, map: CityMap, palette c: Palette) {
        let n = lot.detail
        if lot.ground == .water {
            tile(p, -8, -8, 16, 16, c.water)
            let west = map[Plot(plot.x - 1, plot.y)].ground == .promenade
            let east = map[Plot(plot.x + 1, plot.y)].ground == .promenade
            if west { tile(p, -8, -8, 3, 16, c.waterDark) }
            if east { tile(p, 5, -8, 3, 16, c.waterDark) }
            if n.isMultiple(of: 4) {
                span(p.x - 7, p.x - 2 + n % 4, p.y + n % 5 - 2, c.waterLight)
            }
        } else if lot.ground.carriesTraffic {
            road(at: p, plot: plot, map: map, palette: c, bridge: lot.ground == .bridge)
        } else if lot.ground == .promenade {
            tile(p, -8, -8, 16, 16, c.grass(n))
            let eastBank = map.landscape(at: Plot(plot.x - 1, plot.y)).ground == .water
            let edge = eastBank ? -8 : 7
            line(p.iso(edge, -8, -2), p.iso(edge, 8, -2), c.waterDark)
            line(p.iso(edge, -8), p.iso(edge, 8), c.shore)
            tile(p, eastBank ? -7 : 3, -8, 4, 16, c.paths)
            if n.isMultiple(of: 3) { line(p.iso(edge, 2), p.iso(edge, 6), c.curb) }
        } else {
            tile(p, -8, -8, 16, 16, c.grass(n))
            span(p.x - 6 + n % 5, p.x - 5 + n % 5, p.y + n % 5 - 2, c.grass(n + 2))
            if lot.ground == .park {
                let path = parkWalks(at: plot)
                if path.across { tile(p, -8, -2, 16, 4, c.paths) }
                if path.down { tile(p, -2, -8, 4, 16, c.paths) }
                if path.across && path.down {
                    tile(p, -7, -7, 14, 14, c.paths)
                    tile(p, -5, -5, 10, 10, c.curb)
                    tile(p, -4, -4, 8, 8, c.water)
                    span(p.x - 3, p.x + 2, p.y + 1, c.waterLight)
                    line(p.offset(0, -3), p.offset(0, 0), c.shore)
                } else if path.across && n % 2 == 0 {
                    line(p.iso(-3, -4, 1), p.iso(3, -4, 1), c.clay)
                    line(p.iso(-2, -4), p.iso(2, -4), c.outline)
                }
            } else if let road = map.roadAccess(at: plot), lot.building != nil {
                if lot.zone != .homes {
                    tile(p, -7, -7, 14, 14, c.sidewalk)
                    if lot.zone == .civic { tile(p, -8, -8, 16, 16, c.curb) }
                } else if n.isMultiple(of: 3) {
                    line(p.iso(-7, 7, 1), p.iso(7, 7, 1), c.foliage)
                    line(p.iso(-7, 7), p.iso(7, 7), c.shadow)
                }
                let dx = road.x - plot.x, dy = road.y - plot.y
                if dx != 0 { tile(p, dx > 0 ? 2 : -8, -1, 6, 3, c.paths) }
                if dy != 0 { tile(p, -1, dy > 0 ? 2 : -8, 3, 6, c.paths) }
            }
        }
    }

    private mutating func road(at p: Dot, plot: Plot, map: CityMap, palette c: Palette, bridge: Bool) {
        let east = map.isRoad(Plot(plot.x + 1, plot.y))
        let west = map.isRoad(Plot(plot.x - 1, plot.y))
        let south = map.isRoad(Plot(plot.x, plot.y + 1))
        let north = map.isRoad(Plot(plot.x, plot.y - 1))
        if bridge {
            tile(p, -8, -8, 16, 16, c.water)
            tile(p.offset(0, 3), -8, -6, 16, 13, c.waterDark)
            tile(p.offset(0, 2), -8, -6, 16, 13, c.outline)
            tile(p, -8, -6, 16, 13, c.sidewalk)
        } else {
            tile(p, -8, -8, 16, 16, c.sidewalk)
            line(p.iso(-8, -8), p.iso(-8, 8), c.curb)
            line(p.iso(-8, -8), p.iso(8, -8), c.curb)
        }
        let left = west ? -8 : -5
        let top = north ? -8 : -5
        let right = east ? 8 : 5
        let bottom = south ? 8 : 5
        tile(p, left, -6, right - left, 12, c.roadEdge)
        tile(p, -6, top, 12, bottom - top, c.roadEdge)
        tile(p, left, -5, right - left, 10, c.asphalt)
        tile(p, -5, top, 10, bottom - top, c.asphalt)
        if east { line(p.iso(6, 0), p.iso(7, 0), c.paint) }
        if west { line(p.iso(-8, 0), p.iso(-7, 0), c.paint) }
        if south { line(p.iso(0, 6), p.iso(0, 7), c.paint) }
        if north { line(p.iso(0, -8), p.iso(0, -7), c.paint) }
        let junction = [east, west, south, north].filter { $0 }.count > 2
        if junction {
            for mark in [-4, -2, 2, 4] {
                if east { line(p.iso(5, mark), p.iso(6, mark), c.curb) }
                if south { line(p.iso(mark, 5), p.iso(mark, 6), c.curb) }
            }
        }
        if bridge {
            line(p.iso(-8, -6, 2), p.iso(8, -6, 2), c.curb)
            line(p.iso(-8, 6, 2), p.iso(8, 6, 2), c.curb)
            for u in [-8, 0, 7] {
                line(p.iso(u, 6), p.iso(u, 6, 4), c.outline)
                line(p.iso(u, -6), p.iso(u, -6, 4), c.curb)
            }
        }
    }

    mutating func tree(at p: Dot, style: Int, palette c: Palette) {
        let h = 6 + style % 5
        let green = c.color([0x76934E, 0x668951, 0x93A354, 0xA29952, 0x63906C, 0x8A9B5C][style % 6])
        let tip = p.offset(style % 3 - 1, -h)
        box(p.offset(0, -4), 1, 5, c.color(0x755B48, 0x322D3C))
        polygon([tip, tip.offset(4, 3), tip.offset(5, 6), tip.offset(1, 9),
                 tip.offset(-4, 7), tip.offset(-5, 4), tip.offset(-2, 1)], c.leafShade)
        polygon([tip.offset(-1, 0), tip.offset(3, 2), tip.offset(3, 5),
                 tip.offset(-1, 7), tip.offset(-5, 5), tip.offset(-4, 2)], c.foliage)
        polygon([tip.offset(-1, 0), tip.offset(2, 2), tip.offset(1, 3), tip.offset(-2, 5),
                 tip.offset(-4, 4), tip.offset(-3, 2)], green)
        span(tip.x - 2, tip.x, tip.y + 2, green.mix(c.shore, 0.17))
    }

    mutating func lamp(at p: Dot, palette c: Palette) {
        line(p, p.offset(0, -8), c.outline)
        span(p.x - 2, p.x + 1, p.y - 8, c.outline)
        span(p.x - 2, p.x - 1, p.y - 7, c.night > 0.25 ? c.gold : c.curb)
        if c.night > 0.5 { span(p.x - 3, p.x, p.y, c.color(0xA29A76, 0x706047)) }
    }
}
