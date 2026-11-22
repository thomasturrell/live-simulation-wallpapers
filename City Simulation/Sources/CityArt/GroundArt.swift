import CityEngine

func parkWalks(at plot: Plot) -> (across: Bool, down: Bool) {
    (plot.y % 4 == 1, plot.x % 4 == 2)
}

extension Pixels {
    mutating func ground(_ lot: Lot, at p: Dot, plot: Plot, map: CityMap, convention: TrafficConvention, palette c: Palette) {
        let n = lot.detail
        if lot.ground == .water {
            tile(p, -8, -8, 16, 16, c.water)
            let west = map[Plot(plot.x - 1, plot.y)].ground == .promenade
            let east = map[Plot(plot.x + 1, plot.y)].ground == .promenade
            if c.skin == .contemporary && c.night > 0.18 && plot.x.isMultiple(of: 2)
                && map[Plot(plot.x, plot.y - 1)].ground == .bridge {
                let foot = p.iso(0, -8)
                let light = c.water.mix(c.gold, min(0.8, c.night))
                for y in [1, 3, 4, 7] {
                    let shimmer = foot.offset(-1 + y % 2, y)
                    line(shimmer, shimmer.offset(y % 3 + 1, 0), light.mix(c.water, Double(y) / 10), width: 0.5)
                }
            }
            if west { tile(p, -8, -8, 3, 16, c.waterDark) }
            if east { tile(p, 5, -8, 3, 16, c.waterDark) }
            if n.isMultiple(of: 4) {
                span(p.x - 7, p.x - 2 + n % 4, p.y + n % 5 - 2, c.waterLight)
            }
        } else if lot.ground.carriesTraffic {
            road(at: p, plot: plot, map: map, convention: convention, palette: c, bridge: lot.ground == .bridge)
        } else if lot.ground == .promenade {
            tile(p, -8, -8, 16, 16, c.grass(n))
            let eastBank = map.landscape(at: Plot(plot.x - 1, plot.y)).ground == .water
            let edge = eastBank ? -8 : 7
            if c.skin == .contemporary {
                let walk = eastBank ? -7 : 1
                let stone = c.roof(0xDACFB8)
                tile(p, walk, -8, 7, 16, stone)
                let joint = c.roof(0xAAA999)
                for v in stride(from: -8, to: 8, by: 4) {
                    line(p.iso(walk, v), p.iso(walk + 7, v), joint, width: 0.3)
                    let u = walk + (v.isMultiple(of: 8) ? 2 : 5)
                    line(p.iso(u, v), p.iso(u, v + 4), joint, width: 0.3)
                }
                line(p.iso(edge, -8), p.iso(edge, 8), c.color(0x83949A))
                line(p.iso(edge, -8, 2), p.iso(edge, 8, 2), c.roof(0xDCE3DD))
                for v in [-7, 1] {
                    line(p.iso(edge, v), p.iso(edge, v, 3), c.color(0x667C86))
                }
            } else {
                line(p.iso(edge, -8, -2), p.iso(edge, 8, -2), c.waterDark)
                line(p.iso(edge, -8), p.iso(edge, 8), c.shore)
                tile(p, eastBank ? -7 : 3, -8, 4, 16, c.paths)
                if n.isMultiple(of: 3) { line(p.iso(edge, 2), p.iso(edge, 6), c.curb) }
            }
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

    private mutating func road(at p: Dot, plot: Plot, map: CityMap, convention: TrafficConvention, palette c: Palette, bridge: Bool) {
        let connections = plot.neighbors.filter(map.isRoad)
        let east = connections.contains(Plot(plot.x + 1, plot.y))
        let west = connections.contains(Plot(plot.x - 1, plot.y))
        let south = connections.contains(Plot(plot.x, plot.y + 1))
        let north = connections.contains(Plot(plot.x, plot.y - 1))
        if bridge {
            tile(p, -8, -8, 16, 16, c.water)
            tile(p.offset(0, 3), -8, -6, 16, 13, c.waterDark)
            tile(p.offset(0, 2), -8, -6, 16, 13, c.outline)
            tile(p, -8, -6, 16, 13, c.sidewalk)
        } else {
            tile(p, -8, -8, 16, 16, c.sidewalk)
            if c.skin == .contemporary {
                let joint = c.sidewalk.mix(c.roadEdge, 0.29)
                for seam in stride(from: -8, to: 8, by: 4) {
                    line(p.iso(seam, -8), p.iso(seam, 8), joint, width: 0.32)
                    line(p.iso(-8, seam), p.iso(8, seam), joint, width: 0.32)
                }
            }
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
        roadMarkings(at: p, plot: plot, connections: connections, map: map, convention: convention, palette: c)
        if bridge && c.skin == .original {
            line(p.iso(-8, -6, 2), p.iso(8, -6, 2), c.curb)
            line(p.iso(-8, 6, 2), p.iso(8, 6, 2), c.curb)
            for u in [-8, 0, 7] {
                line(p.iso(u, 6), p.iso(u, 6, 4), c.outline)
                line(p.iso(u, -6), p.iso(u, -6, 4), c.curb)
            }
        }
    }

    mutating func bridgeRails(at p: Dot, palette c: Palette) {
        for v in [-6, 6] {
            line(p.iso(-8, v), p.iso(8, v), c.roof(0xD2C7B3))
            for u in [-8, 0] {
                line(p.iso(u, v, 1), p.iso(u + 7, v, 4), c.color(0x788C9A))
                line(p.iso(u, v), p.iso(u, v, 4), c.color(0x536C7A))
            }
            line(p.iso(-8, v, 4), p.iso(8, v, 4), c.roof(0xCEDAD9))
        }
    }

    private mutating func roadMarkings(at p: Dot, plot: Plot, connections: [Plot], map: CityMap,
                                      convention: TrafficConvention, palette c: Palette) {
        let controlled = connections.filter { map.hasJunctionControl(at: $0) }
        if connections.count == 2 {
            // Each straight and bridge tile contributes one full dash, with an
            // even gap at the seam. Bends carry the dash around the corner.
            let first = SIMD2(connections[0].x - plot.x, connections[0].y - plot.y)
            let second = SIMD2(connections[1].x - plot.x, connections[1].y - plot.y)
            let ink = convention == .uk ? c.whiteRoadPaint : c.yellowRoadPaint
            func dot(_ direction: SIMD2<Int>, _ distance: Int) -> Dot {
                p.iso(direction.x * distance, direction.y * distance)
            }
            // Leave a gap between the end of the dash and the transverse paint.
            let firstTrim = controlled.contains(connections[0]) ? 2 : 0
            let secondTrim = controlled.contains(connections[1]) ? 2 : 0
            if first.x == second.x || first.y == second.y {
                line(dot(first, 4 - firstTrim), dot(second, 4 - secondTrim), ink, width: 0.46)
            } else {
                line(dot(first, 5 - firstTrim), dot(first, 2), ink)
                line(dot(first, 2), dot(second, 2), ink)
                line(dot(second, 2), dot(second, 5 - secondTrim), ink)
            }
        }
        for junction in controlled {
            let dx = junction.x - plot.x, dy = junction.y - plot.y
            let lane = convention.laneNormal(x: dx, y: dy)
            let offset = RoadGeometry.tileSize - RoadGeometry.stopLineOffset
            let x = dx * offset, y = dy * offset
            line(p.iso(x + lane.x, y + lane.y), p.iso(x + 4 * lane.x, y + 4 * lane.y), c.whiteRoadPaint)
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
            if c.skin == .contemporary && growth > 0.12 {
                let radius = 3.35 * growth
                let leaf = green.mix(c.foliage, 0.28 + Double(i % 3) * 0.08)
                var sun = leaf.mix(c.color(0xACC780), 0.45)
                if style % 3 == 1 && season.blossom > threshold { sun = sun.mix(c.color(0xE6C4CE), 0.76) }
                if c.weather.snowCover > threshold { sun = c.snow }
                oval(at: centre, radiusX: radius, radiusY: radius * 1.12,
                     top: sun, bottom: leaf.mix(c.leafShade, 0.78))
                let crown = centre.projectedOffset(-0.65 * growth, -1.05 * growth)
                oval(at: crown, radiusX: radius * 0.65, radiusY: radius * 0.55,
                     top: sun, bottom: leaf)
                continue
            }
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
        if c.skin == .contemporary {
            let light = p.offset(-1, -8)
            line(p, p.offset(0, -8), c.color(0x627384), width: 0.55)
            line(p.offset(0, -8), light, c.curb, width: 0.45)
            oval(at: light, radiusX: 0.95, radiusY: 0.6,
                 top: c.night > 0.2 ? c.gold : c.shore, bottom: c.curb)
            return
        }
        line(p, p.offset(0, -8), c.outline)
        span(p.x - 2, p.x + 1, p.y - 8, c.outline)
        span(p.x - 2, p.x - 1, p.y - 7, c.night > 0.25 ? c.gold : c.curb)
        if c.night > 0.5 { span(p.x - 3, p.x, p.y, c.color(0xA29A76, 0x706047)) }
    }
}
