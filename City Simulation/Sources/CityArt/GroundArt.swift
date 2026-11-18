import CityEngine

func parkWalks(at plot: Plot) -> (across: Bool, down: Bool) {
    (plot.y % 4 == 1, plot.x % 4 == 2)
}

extension Pixels {
    mutating func ground(_ lot: Lot, at p: Dot, plot: Plot, map: CityMap, palette c: Palette) {
        if let airport = map.airport, airport.contains(plot) {
            airportGround(at: p, plot: plot, airport: airport, palette: c)
            return
        }
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
        // Flower beds, scattered meadow flowers and fallen leaves share the
        // seasonal artwork in both calendars. Paths and buildings stay intact.
        if [.grass, .park, .promenade].contains(lot.ground), lot.building == nil {
            let density = c.season.flowers * (lot.ground == .park ? 1 : 0.55)
            for i in 0..<4 where Double((n * 13 + i * 29) % 100) / 100 < density {
                let dot = p.iso((n + i * 7) % 13 - 6, (n * 3 + i * 5) % 13 - 6)
                let flower = c.color([0xE7BD83, 0xD7C8B6, 0xC78689][i % 3])
                span(dot.x, dot.x, dot.y - 1, flower.mix(c.snow, c.weather.snowCover))
                span(dot.x, dot.x, dot.y, c.foliage)
            }
            if c.season.foliage < 0.7 && c.season.warmth > 0.15 && c.season.blossom < 0.1 {
                for i in 0..<3 {
                    let dot = p.iso((n + i * 5) % 13 - 6, (n * 7 + i * 3) % 13 - 6)
                    span(dot.x, dot.x + 1, dot.y, c.color(0xAB7A47).mix(c.snow, c.weather.snowCover))
                }
            }
        }
        if lot.ground.carriesTraffic || lot.ground == .water {
            if c.weather.rain > 0.2 && n % 4 == 0 {
                let wet = p.iso(-4, 3)
                span(wet.x - 2, wet.x + 2, wet.y, c.waterLight.mix(c.asphalt, 0.45))
            }
            if lot.ground.carriesTraffic && c.weather.snowCover > 0.15 {
                line(p.iso(-7, -6), p.iso(-7, 6), c.curb.mix(c.snow, c.weather.snowCover))
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
        let h = 10 + style % 5
        let tip = p.offset(style % 3 - 1, -h)
        let bark = c.color(0x755B48, 0x322D3C)
        line(p, tip.offset(0, 2), bark)
        if style.isMultiple(of: 5) {
            // Evergreen spruces retain distinct tiered needles all year.
            for tier in 0..<3 {
                let top = tip.offset(0, tier * 3)
                let half = 2 + tier
                polygon([top, top.offset(half, 5), top.offset(-half, 5)], c.color(0x365E50, 0x233B42))
                polygon([top, top.offset(0, 5), top.offset(-half, 5)], c.color(0x628168, 0x344B4F))
                if c.weather.snowCover > Double(tier + 1) / 5 {
                    line(top, top.offset(-half + 1, 3), c.snow)
                }
            }
            return
        }
        // Branches remain visible as foliage withdraws. Stable per-tree phase
        // and cluster thresholds prevent the whole city changing in lockstep.
        let season = SeasonAppearance.at(month: (c.environment?.month ?? 5) + Double(style % 9 - 4) * 0.065)
        let clusters = [(-3, 3), (3, 4), (0, 0), (-4, 6), (2, 7), (0, 4), (-2, 1), (4, 6)]
        let green = c.color(season.leafColor).mix(c.color(0xB4AC64), Double(style % 6) * 0.025)
        for (i, offset) in clusters.enumerated() {
            let centre = tip.offset(offset.0, offset.1)
            line(p.offset(0, -3), centre, bark)
            line(centre, centre.offset(i % 2 == 0 ? -1 : 1, -2), bark)
            let threshold = Double((i * 3 + style) % 8) / 8 + 0.045
            let growth = max(0, min(1, (season.foliage - threshold) * 7))
            let radius = Int((growth * 3).rounded())
            if radius > 0 {
                let r = radius
                polygon([centre.offset(-r, -1), centre.offset(-1, -r), centre.offset(r, -1),
                         centre.offset(r, 1), centre.offset(0, r), centre.offset(-r, 1)], green.mix(c.leafShade, i % 3 == 0 ? 0.3 : 0.05))
                span(centre.x - r + 1, centre.x, centre.y - r + 1, green.mix(c.shore, 0.17))
            }
            if style % 3 == 1 && season.blossom > threshold && c.weather.snowCover < 0.4 {
                span(centre.x - 1, centre.x + 1, centre.y - 1, c.color(0xDCB0B1, 0x816D88))
                span(centre.x, centre.x, centre.y - 2, c.color(0xF0D3C6, 0xA292A3))
            }
            if c.weather.snowCover > threshold {
                span(centre.x - 1, centre.x + 1, centre.y - max(0, radius - 1), c.snow)
            }
        }
    }

    mutating func lamp(at p: Dot, palette c: Palette) {
        line(p, p.offset(0, -8), c.outline)
        span(p.x - 2, p.x + 1, p.y - 8, c.outline)
        span(p.x - 2, p.x - 1, p.y - 7, c.night > 0.25 ? c.gold : c.curb)
        if c.night > 0.5 { span(p.x - 3, p.x, p.y, c.color(0xA29A76, 0x706047)) }
    }
}
