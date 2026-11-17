import AppKit
import LifeEngine

struct LifeLayout {
    let viewport: CGSize
    let pitch: CGFloat
    let angle: CGFloat
    let columns: Int
    let rows: Int
    let visibleX: Range<Int>
    let visibleY: Range<Int>
    let transform: CGAffineTransform

    init(viewport: CGSize, settings: LifeSettings) {
        self.viewport = viewport
        pitch = settings.pitch
        angle = settings.angle * .pi / 180
        let reach = Int(ceil(hypot(viewport.width, viewport.height) / pitch)) + 8
        // Round to a common bucket so small dimensional changes preserve the world.
        columns = max(24, ((reach + 7) / 8) * 8)
        let verticalReach = Int(ceil((viewport.height + viewport.width * sin(20 * .pi / 180)) / pitch)) + 8
        rows = max(24, ((verticalReach + 7) / 8) * 8)
        transform = CGAffineTransform(translationX: viewport.width / 2, y: viewport.height / 2)
            .rotated(by: angle)
            .translatedBy(x: -CGFloat(columns) * pitch / 2, y: -CGFloat(rows) * pitch / 2)

        let bounds = CGRect(origin: .zero, size: viewport).applying(transform.inverted())
        let x0 = max(0, Int(floor(bounds.minX / pitch)) - 1)
        let y0 = max(0, Int(floor(bounds.minY / pitch)) - 1)
        visibleX = x0..<min(columns, Int(ceil(bounds.maxX / pitch)) + 1)
        visibleY = y0..<min(rows, Int(ceil(bounds.maxY / pitch)) + 1)
    }
}

struct LifePaths {
    let living: [CGMutablePath]
    let births: [CGMutablePath]
    let deaths: [CGMutablePath]

    init(world: LifeWorld, layout: LifeLayout, settings: LifeSettings, animate: Bool) {
        living = (0..<5).map { _ in CGMutablePath() }
        births = (0..<5).map { _ in CGMutablePath() }
        deaths = (0..<5).map { _ in CGMutablePath() }
        let inset = settings.spacing / 2
        let clip = CGRect(origin: .zero, size: layout.viewport).insetBy(dx: -layout.pitch, dy: -layout.pitch)
        for y in layout.visibleY {
            for x in layout.visibleX {
                let now = world.isAlive(x: x, y: y)
                let before = animate && world.wasAlive(x: x, y: y)
                guard now || before else { continue }
                let box = CGRect(x: CGFloat(x) * layout.pitch + inset,
                                 y: CGFloat(y) * layout.pitch + inset,
                                 width: settings.size, height: settings.size)
                guard box.applying(layout.transform).intersects(clip) else { continue }
                let tone = Self.tone(x: x, y: y)
                let path = now ? (animate && !before ? births[tone] : living[tone]) : deaths[tone]
                path.addRect(box, transform: layout.transform)
            }
        }
    }

    private static func tone(x: Int, y: Int) -> Int {
        // Fixed colours belong to regions of the grid, independent of cell age.
        let field = sin(Double(x) * 0.082 + Double(y) * 0.057)
            + cos(Double(y) * 0.086 - Double(x) * 0.051)
        let grain = (x &* 73_856_093 ^ y &* 19_349_663) % 100
        if grain < 35 && field > 0.53 { return 2 }
        if grain < 33 && field < -0.48 { return 3 }
        if grain < 14 && abs(field) <= 0.66 { return 4 }
        return grain < 58 ? 0 : 1
    }
}

public struct LifeScene {
    private(set) var settings: LifeSettings
    private(set) var layout: LifeLayout
    private(set) var world: LifeWorld
    private var seeding: LifeSeeding
    private var elapsedSinceInjection = 0.0

    package struct Checkpoint: Codable {
        let viewport: CGSize
        var size: Double
        var spacing: Double
        var seed: UInt64
        var world: LifeWorld.Checkpoint
        var generator: UInt64
        var injectionTime: Double
    }

    package var checkpoint: Checkpoint {
        Checkpoint(viewport: layout.viewport, size: settings.size, spacing: settings.spacing,
                   seed: settings.seed, world: world.checkpoint, generator: seeding.seed,
                   injectionTime: elapsedSinceInjection)
    }

    package init?(checkpoint: Checkpoint, settings: LifeSettings) {
        let viewport = checkpoint.viewport
        guard viewport.width.isFinite, viewport.height.isFinite,
              (16...8192).contains(viewport.width), (16...8192).contains(viewport.height),
              settings.size == checkpoint.size, settings.spacing == checkpoint.spacing,
              settings.seed == checkpoint.seed,
              (0...120).contains(checkpoint.injectionTime) else { return nil }
        let layout = LifeLayout(viewport: viewport, settings: settings)
        guard layout.columns == checkpoint.world.width, layout.rows == checkpoint.world.height,
              let world = LifeWorld(checkpoint: checkpoint.world) else { return nil }
        self.settings = settings
        self.layout = layout
        self.world = world
        seeding = LifeSeeding(seed: checkpoint.generator)
        elapsedSinceInjection = checkpoint.injectionTime
    }

    package var viewport: CGSize { layout.viewport }

    public init(viewport: CGSize, settings: LifeSettings) {
        self.settings = settings
        layout = LifeLayout(viewport: viewport, settings: settings)
        seeding = LifeSeeding(seed: settings.seed)
        world = LifeWorld(width: layout.columns, height: layout.rows)
        seeding.populate(&world)
    }

    mutating func configure(viewport: CGSize, settings: LifeSettings) {
        let next = LifeLayout(viewport: viewport, settings: settings)
        if next.columns != layout.columns || next.rows != layout.rows || settings.seed != self.settings.seed {
            self = LifeScene(viewport: viewport, settings: settings)
        } else {
            if settings.injection != self.settings.injection { elapsedSinceInjection = 0 }
            self.settings = settings
            layout = next
        }
    }

    package mutating func advance(by seconds: TimeInterval) {
        world.step()
        guard settings.injection > 0 else { return }
        elapsedSinceInjection += seconds
        guard elapsedSinceInjection >= settings.injection else { return }
        elapsedSinceInjection -= settings.injection
        let x = layout.visibleX
        let y = layout.visibleY
        for _ in 0..<max(1, x.count * y.count / 10_000) {
            seeding.introduce(into: &world, x: x, y: y)
        }
    }

    public func image(scale: CGFloat, dark: Bool) -> CGImage? {
        image(scale: scale, darkness: dark ? 1 : 0)
    }

    package func palette(darkness: Double, colour: LifeColour? = nil) -> LifePalette {
        LifePalette(darkness: darkness, colour: colour ?? settings.colour,
                    generation: world.generation, seed: settings.seed)
    }

    package func image(scale: CGFloat, darkness: Double, colour: LifeColour? = nil) -> CGImage? {
        let width = Int((layout.viewport.width * scale).rounded())
        let height = Int((layout.viewport.height * scale).rounded())
        guard width > 0, height > 0, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        let palette = palette(darkness: darkness, colour: colour)
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: palette.background as CFArray, locations: nil) {
            context.drawLinearGradient(gradient,
                                       start: CGPoint(x: 0, y: layout.viewport.height),
                                       end: .zero, options: [.drawsAfterEndLocation, .drawsBeforeStartLocation])
        }
        let paths = LifePaths(world: world, layout: layout, settings: settings, animate: false)
        for (path, color) in zip(paths.living, palette.cells) {
            context.setFillColor(color)
            context.addPath(path)
            context.fillPath()
        }
        return context.makeImage()
    }
}
