import CityEngine
import CoreGraphics
import Foundation

/// The virtual image is enlarged by a whole number of device pixels and cropped at the edges.
public struct CityViewport: Equatable {
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let width: Int
    public let height: Int
    public let zoom: Int

    public init(pixelWidth: Int, pixelHeight: Int) {
        self.pixelWidth = max(1, pixelWidth)
        self.pixelHeight = max(1, pixelHeight)
        zoom = max(1, Int(max(Double(pixelWidth) / 640, Double(pixelHeight) / 386).rounded()))
        width = (self.pixelWidth + zoom - 1) / zoom
        height = (self.pixelHeight + zoom - 1) / zoom
    }

    /// Destination in backing pixels, expressed in Core Graphics' lower-left coordinate system.
    public var imageRect: CGRect {
        CGRect(x: (pixelWidth - width * zoom) / 2,
               y: (pixelHeight - height * zoom) / 2,
               width: width * zoom, height: height * zoom)
    }

    public func draw(_ image: CGImage, in context: CGContext) {
        context.interpolationQuality = image.shouldInterpolate ? .high : .none
        context.setShouldAntialias(false)
        context.draw(image, in: imageRect)
    }

    var origin: Dot { Dot(width / 2, height / 2 + 30) }

    func project(_ plot: Plot) -> Dot {
        let u = plot.x - CityMap.center.x, v = plot.y - CityMap.center.y
        return origin.offset((u - v) * 16, (u + v) * 8)
    }

    func project(_ x: Double, _ y: Double, altitude: Double = 0) -> Dot {
        let u = x - Double(CityMap.center.x), v = y - Double(CityMap.center.y)
        return origin.projectedOffset((u - v) * 16, (u + v) * 8 - altitude)
    }

    /// Invert the projection over the view and allow for tall buildings just below the crop.
    var drawingOrder: [Plot] {
        let u = width / 32 + 2
        let near = (-origin.y - 12) / 8
        let far = (height - origin.y + 80) / 8
        let center = CityMap.center
        var plots: [Plot] = []
        for sum in near...far {
            let firstX = (sum - u) / 2 - 1
            let lastX = (sum + u) / 2 + 1
            for x in firstX...lastX {
                plots.append(Plot(x + center.x, sum - x + center.y))
            }
        }
        return plots
    }
}

public final class CityRenderer {
    private struct BackgroundKey: Equatable {
        let viewport: CityViewport
        let map: CityMap
        let environment: EnvironmentFrame
        let site: Construction?
        let stage: Int
        let trafficConvention: TrafficConvention
        let skin: CitySkin
    }

    private struct Background {
        var pixels: Pixels
        var water: [(Dot, Int)]
        var stacks: [(Dot, Plot, Int)]
    }

    private var lastKey: BackgroundKey?
    private var background: Background?
    private var lastTick: Int?
    private var lastImage: CGImage?

    public init() {}

    /// Enlarged, shared artwork reference: twelve monthly rows, with evergreen,
    /// deciduous and blossom trees, lawn and garden details in each row.
    public static func vegetationPreview() -> CGImage {
        var pixels = Pixels(width: 192, height: 12 * 32, background: Ink(0x282E3A))
        let city = City()
        for month in 0..<12 {
            var preview = EnvironmentPreview()
            preview.month = Double(month + 1); preview.darkness = 0; preview.weather = .clear
            let frame = Environment.frame(city: city, mode: .realWorldNorthern, preview: preview)
            let palette = Palette(night: 0, environment: frame)
            pixels.box(Dot(0, month * 32), 192, 31, palette.grass(month))
            for (index, style) in [5, 16, 22, 38, 73, 119].enumerated() {
                pixels.tree(at: Dot(16 + index * 32, month * 32 + 24), style: style, palette: palette)
            }
        }
        return pixels.image()
    }

    public func image(for city: City, viewport: CityViewport, environment: EnvironmentFrame? = nil,
                      skin: CitySkin = .original) -> CGImage {
        let environment = (environment ?? Environment.frame(city: city)).quantized
        let key = BackgroundKey(viewport: viewport, map: city.map, environment: environment,
                                site: city.construction, stage: city.constructionStage,
                                trafficConvention: city.trafficConvention, skin: skin)
        let palette = Palette(night: environment.darkness, environment: environment, skin: skin)
        if lastKey != key {
            background = makeBackground(city, viewport, palette)
            lastKey = key
            lastTick = nil
        }
        if lastTick == city.tick, let lastImage { return lastImage }
        let base = background!
        var pixels = base.pixels
        pixels.overlay = true

        pixels.depth = 0
        for (p, detail) in base.water where (city.tick / 9 + detail) % 17 < 5 {
            let n = (city.tick / 5 + detail) % 5
            pixels.span(p.x - 3 + n, p.x + n, p.y + detail % 5, palette.waterLight)
            pixels.span(p.x - 7 + n, p.x - 6 + n, p.y + detail % 5 + 2, palette.waterDark)
        }

        // Cars share the depth scale of the buildings. A car on the street
        // behind a roof disappears along the actual silhouette of that roof.
        let vehicles = city.vehicles.map { ($0, $0.pose(in: city.trafficConvention)) }
            .sorted { $0.1.x + $0.1.y < $1.1.x + $1.1.y }
        for (vehicle, pose) in vehicles where pose.visibility > 0.18 {
            pixels.depth = depth(pose.x + pose.y)
            let dot = viewport.project(pose.x, pose.y)
            guard (-12...pixels.width + 12).contains(dot.x), (-10...pixels.height + 10).contains(dot.y) else { continue }
            pixels.car(at: dot, pose: pose, color: vehicle.color, long: vehicle.long, palette: palette)
        }
        for (p, plot, style) in base.stacks {
            pixels.depth = depth(Double(plot.x + plot.y)) + 1
            let cycle = (city.tick + style * 37) % 187
            for age in [cycle, cycle - 16, cycle - 33] where (0..<42).contains(age) {
                let puff = p.offset(age / 5, -age / 4)
                let tone = palette.color(age < 18 ? 0xB8B4A2 : 0xA0A398, 0x555667)
                pixels.span(puff.x - 1, puff.x + age / 14, puff.y, tone)
                if age < 31 { pixels.span(puff.x, puff.x + 1, puff.y - 1, tone) }
            }
        }
        for plane in city.aviation.aircraft {
            let pose = plane.pose()
            pixels.depth = depth(pose.x + pose.y + pose.altitude / 8)
            let dot = viewport.project(pose.x, pose.y, altitude: pose.altitude)
            guard (-40...pixels.width + 40).contains(dot.x), (-40...pixels.height + 40).contains(dot.y) else { continue }
            pixels.aircraft(at: dot, pose: pose, livery: plane.livery,
                            blink: (city.tick + Int(plane.id % 30)) % 45 < 4, palette: palette)
        }
        pixels.weatherEffects(tick: city.tick, palette: palette)
        let image = pixels.image()
        lastTick = city.tick
        lastImage = image
        return image
    }

    private func depth(_ worldSum: Double) -> Int16 { Int16((worldSum + 128) * 32) }

    private func makeBackground(_ city: City, _ viewport: CityViewport, _ c: Palette) -> Background {
        // Keep the camera in logical units. Bound the moving colour and depth buffers on 5K displays.
        let scale = c.skin == .contemporary ? min(4, max(2, viewport.zoom + 1)) : 1
        var pixels = Pixels(width: viewport.width, height: viewport.height, background: c.grass(0), rasterScale: scale)
        var water: [(Dot, Int)] = []
        var stacks: [(Dot, Plot, Int)] = []
        let plots = viewport.drawingOrder.map { ($0, viewport.project($0), city.map[$0]) }
        for (plot, p, lot) in plots {
            pixels.ground(lot, at: p, plot: plot, map: city.map, convention: city.trafficConvention, palette: c)
            if lot.ground == .water, lot.detail % 3 == 0 { water.append((p, lot.detail)) }
        }
        for (plot, p, lot) in plots where lot.ground == .grass || lot.ground == .park {
            if lot.building != nil {
                pixels.tile(p.offset(4, 1), -6, -5, 12, 13, c.shadow)
            } else if hasTree(lot, at: plot) {
                let shadow = p.offset(4, 1)
                if c.skin == .contemporary {
                    pixels.oval(at: shadow, radiusX: 4.8, radiusY: 1.9, top: c.shadow, bottom: c.grass(lot.detail))
                    continue
                }
                pixels.span(shadow.x - 2, shadow.x + 4, shadow.y, c.shadow)
                pixels.span(shadow.x, shadow.x + 3, shadow.y + 1, c.shadow)
            }
        }

        for (plot, p, lot) in plots {
            pixels.depth = depth(Double(plot.x + plot.y))
            if city.construction?.plot == plot {
                pixels.site(at: p, stage: city.constructionStage, road: city.construction?.replacement == nil, palette: c)
            } else if let building = lot.building {
                if lot.zone == .homes && lot.detail % 2 == 0 {
                    pixels.tree(at: p.iso(-6, 5), style: lot.detail, palette: c)
                }
                pixels.building(building, zone: lot.zone, at: p, palette: c)
                if lot.zone == .industry && building.style.isMultiple(of: 4) {
                    stacks.append((p.iso(5, -4, 22), plot, building.style))
                }
            } else if hasTree(lot, at: plot) {
                let pos = lot.ground == .park ? p.iso(5, 5) : p.offset(lot.detail % 7 - 3, 1)
                pixels.tree(at: pos, style: lot.detail, palette: c)
                if lot.ground == .park && lot.detail.isMultiple(of: 2) {
                    pixels.tree(at: p.iso(-5, -4), style: lot.detail / 2, palette: c)
                }
            } else if c.skin == .contemporary && lot.ground == .bridge {
                pixels.bridgeRails(at: p, palette: c)
                if plot.x.isMultiple(of: 2) { pixels.lamp(at: p.iso(0, 7), palette: c) }
            } else if lot.ground == .road && lot.detail.isMultiple(of: 3) {
                pixels.depth += 22
                pixels.lamp(at: p.iso(6, 6), palette: c)
            } else if lot.ground == .promenade && lot.detail.isMultiple(of: 7) {
                pixels.lamp(at: p.iso(-1, 4), palette: c)
            }
        }
        return Background(pixels: pixels, water: water, stacks: stacks)
    }

    private func hasTree(_ lot: Lot, at plot: Plot) -> Bool {
        switch lot.ground {
        case .grass: return lot.detail % 11 < 5
        case .park:
            let path = parkWalks(at: plot)
            return !(path.across && path.down) && lot.detail % 5 != 0
        case .promenade: return lot.detail % 5 == 1
        default: return false
        }
    }
}

private extension Pixels {
    mutating func car(at p: Dot, pose: Vehicle.Pose, color: Int, long: Bool, palette c: Palette) {
        let alongX = abs(pose.dx) >= abs(pose.dy)
        let rightward = alongX ? pose.dx >= 0 : pose.dy < 0
        let slope = alongX ? 1 : -1
        let half = pose.visibility < 0.65 ? 2 : long ? 5 : 3
        let hue: UInt32 = [0xD67C56, 0xE4BB77, 0xC5BBA8, 0x739A98, 0xA85C55, 0x8B8CA2, 0xCFD1BB, 0x72939D][color]
        let body = c.color(hue)
        let windshield = c.color(0x44646D, 0x4B6070)
        let left = p.offset(-half, -(half * slope) / 2)
        let right = p.offset(half, (half * slope) / 2)
        if c.skin == .contemporary {
            let side = Dot(2, -slope)
            let front = right.offset(0, -1), rear = left.offset(0, -1)
            let farFront = front.offset(side.x, side.y), farRear = rear.offset(side.x, side.y)
            polygon([rear, front, front.offset(0, 1), rear.offset(0, 1)], body.mix(c.outline, 0.46))
            polygon([rear, farRear, farFront, front], body)
            let cab = p.offset(rightward && long ? 2 : 0, -2)
            let nose = cab.offset(1, slope), tail = cab.offset(-2, -slope)
            polygon([tail, tail.offset(1, -1), nose.offset(1, -1), nose], windshield)
            line(tail.offset(1, -1), nose.offset(1, -1), body.mix(c.shore, 0.4), width: 0.5)
            if c.night > 0.3 {
                let head = rightward ? front : rear
                line(head, head.offset(1, 0), c.gold, width: 0.5)
            }
            return
        }
        line(left.offset(0, 1), right.offset(0, 1), c.roadEdge)
        line(left.offset(0, -1), right.offset(0, -1), body)
        line(left.offset(0, -2), right.offset(0, -2), body.mix(c.curb, 0.33))
        let cab = p.offset((rightward ? 1 : -1) * (long ? 2 : 1), -2)
        line(cab, cab.offset(1, slope > 0 ? 1 : 0), windshield)
        if c.night > 0.4 {
            let head = rightward ? right : left
            let tail = rightward ? left : right
            span(head.x, head.x + 1, head.y, c.gold)
            span(tail.x, tail.x, tail.y, c.color(0xC56D59, 0xBC654D))
        }
    }
}
