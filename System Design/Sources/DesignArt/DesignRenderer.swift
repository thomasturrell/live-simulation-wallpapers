import AppKit
import DesignEngine
import QuartzCore

struct HandoffProgress {
    let branches, card, surroundings, connection, neighbour, dissolve: CGFloat

    init(progress: Double) {
        let t = progress / Chapter.handoffEnd
        func phase(_ start: CGFloat, _ end: CGFloat) -> CGFloat { smooth((t - start) / (end - start)) }
        branches = phase(0, 0.38)
        card = phase(0.12, 0.52)
        surroundings = phase(0.42, 0.80)
        connection = phase(0.50, 0.81)
        neighbour = phase(0.80, 1)
        dissolve = smooth(t)
    }
}

@MainActor
package final class DesignRenderer {
    package let root = CALayer()

    let artwork = CALayer()
    private let grid = CALayer()
    private var gridInk: CGColor?

    private struct Sheet {
        let scene: DiagramScene
        let style: DesignStyle
        let dark: Bool
        let generation: Int
        let accentRevision: Int
        let seed: UInt64
        let camera: DiagramCamera
    }
    private var sheets: [Sheet] = []
    private var incoming: Chapter?
    private var accentRevision = 0

    package func systemAccentChanged() { accentRevision &+= 1 }

    package init() {
        root.masksToBounds = true
        root.addSublayer(grid)
        root.addSublayer(artwork)
    }

    private func displayPaper(camera: DiagramCamera, ink: Ink) {
        root.backgroundColor = ink.paper
        if gridInk != ink.text {
            gridInk = ink.text
            grid.backgroundColor = dotPattern(ink.text)
        }
        // Whole tiles on either side of the centre keep the grid phase stable on resize.
        let radius = ceil(hypot(camera.size.width, camera.size.height) / (2 * camera.factor * 24)) * 24
        grid.bounds = CGRect(x: 0, y: 0, width: 2 * radius, height: 2 * radius)
        grid.position = root.bounds.centre
        grid.setAffineTransform(camera.transform)
    }

    private func dotPattern(_ colour: CGColor) -> CGColor {
        let size = 40
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(colour.copy(alpha: 0.21)!)
        c.fillEllipse(in: CGRect(x: 19, y: 19, width: 2.4, height: 2.4))
        let tile = NSImage(cgImage: c.makeImage()!, size: CGSize(width: 24, height: 24))
        return NSColor(patternImage: tile).cgColor
    }

    package func draw(_ exploration: Exploration, size: CGSize, scale: CGFloat, style: DesignStyle, systemDark: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard size.width > 0, size.height > 0 else { return }
        root.frame = CGRect(origin: .zero, size: size)
        root.contentsScale = scale
        artwork.frame = root.bounds
        let camera = DiagramCamera(size: size, style: style, displaySeed: exploration.paletteSeed)
        let chapter = exploration.chapter
        let dark = style.appearance.isDark(systemDark: systemDark)
        let hueStep = exploration.age / (Exploration.ticksPerSecond * 2)
        let generation = style.colour == .spectrum ? hueStep : style.colour == .random ? (hueStep / 240) * 240 : 0

        func sheet(_ chapter: Chapter) -> Sheet {
            let existing = sheets.first { $0.scene.chapter.visit == chapter.visit }
            if let existing, existing.camera == camera, existing.scene.chapter.firstCount == chapter.firstCount, existing.scene.chapter.exit == chapter.exit,
               existing.seed == exploration.paletteSeed, existing.style == style, existing.dark == dark, existing.generation == generation,
               style.colour != .accent || existing.accentRevision == accentRevision { return existing }
            let layout: DiagramLayout
            if let existing, existing.camera == camera, existing.style.descriptions == style.descriptions && existing.style.groupNames == style.groupNames {
                layout = existing.scene.layout
            } else {
                layout = DiagramLayout(chapter: chapter, style: style, camera: camera)
            }
            let ink = Ink(style: style, dark: dark, generation: generation, seed: exploration.paletteSeed)
            let scene = DiagramScene(chapter: chapter, layout: layout, style: style, ink: ink)
            return Sheet(scene: scene, style: style, dark: dark, generation: generation,
                         accentRevision: accentRevision, seed: exploration.paletteSeed, camera: camera)
        }

        let current = sheet(chapter)
        displayPaper(camera: camera, ink: current.scene.ink)
        current.scene.display(camera: camera, beat: exploration.beat, progress: exploration.progress, elevation: exploration.elevation)
        current.scene.layer.opacity = 1
        var active = [current]
        if exploration.beat == chapter.lastBeat {
            if incoming?.visit != chapter.next { incoming = exploration.incomingChapter() }
            let next = sheet(incoming!)
            let handoff = HandoffProgress(progress: exploration.progress)
            if chapter.next.linkedEntry {
                let source = current.scene.components[chapter.exit]!
                let destination = next.scene.components[chapter.next.entry]!
                next.scene.display(camera: camera, beat: 0, progress: 0, elevation: exploration.elevation, opening: handoff)
                source.body.isHidden = true
                destination.morph(from: source, fraction: handoff.card)
                current.scene.layer.opacity = Float(1 - handoff.branches)
                next.scene.layer.opacity = 1
            } else {
                next.scene.display(camera: camera, beat: 0, progress: 0, elevation: exploration.elevation)
                current.scene.layer.opacity = Float(1 - handoff.dissolve)
                next.scene.layer.opacity = Float(handoff.dissolve)
            }
            active.append(next)
        } else { incoming = nil }
        for old in sheets where !active.contains(where: { $0.scene === old.scene }) { old.scene.layer.removeFromSuperlayer() }
        for (index, sheet) in active.enumerated() where sheet.scene.layer.superlayer == nil {
            artwork.insertSublayer(sheet.scene.layer, at: UInt32(index))
        }
        sheets = active
    }

    package func image(size: CGSize, scale: CGFloat = 1) -> CGImage? {
        let width = Int(ceil(size.width * scale)), height = Int(ceil(size.height * scale))
        guard width > 0, height > 0, let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.scaleBy(x: scale, y: scale)
        root.render(in: c)
        return c.makeImage()
    }
}
