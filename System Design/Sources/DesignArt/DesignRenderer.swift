import AppKit
import DesignEngine
import QuartzCore

@MainActor
package final class DesignRenderer {
    package let root = CALayer()

    private struct Sheet {
        let scene: DiagramScene
        let style: DesignStyle
        let dark: Bool
        let generation: Int
        let accentRevision: Int
    }
    private var sheets: [Sheet] = []
    private var incoming: Chapter?
    private var accentRevision = 0

    package func systemAccentChanged() { accentRevision &+= 1 }

    package init() { root.masksToBounds = true }

    package func draw(_ exploration: Exploration, size: CGSize, scale: CGFloat, style: DesignStyle, systemDark: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        root.frame = CGRect(origin: .zero, size: size)
        root.contentsScale = scale
        let chapter = exploration.chapter
        let dark = style.appearance.isDark(systemDark: systemDark)
        let hueStep = exploration.age / (Exploration.ticksPerSecond * 2)
        let generation = style.colour == .spectrum ? hueStep : style.colour == .random ? (hueStep / 240) * 240 : 0

        func sheet(_ chapter: Chapter) -> Sheet {
            let existing = sheets.first { $0.scene.chapter.visit == chapter.visit }
            if let existing, existing.style == style, existing.dark == dark, existing.generation == generation,
               style.colour != .accent || existing.accentRevision == accentRevision { return existing }
            let layout: DiagramLayout
            if let existing, existing.style.descriptions == style.descriptions && existing.style.groupNames == style.groupNames {
                layout = existing.scene.layout
            } else {
                layout = DiagramLayout(graph: chapter.graph, style: style, seed: chapter.visit.seed)
            }
            let ink = Ink(style: style, dark: dark, generation: generation, seed: exploration.paletteSeed)
            let scene = DiagramScene(chapter: chapter, layout: layout, style: style, ink: ink)
            return Sheet(scene: scene, style: style, dark: dark, generation: generation, accentRevision: accentRevision)
        }

        let current = sheet(chapter)
        current.scene.display(size: size, beat: exploration.beat, progress: exploration.progress)
        current.scene.layer.opacity = 1
        var active = [current]
        if exploration.beat == chapter.lastBeat {
            if incoming?.visit != chapter.next { incoming = exploration.incomingChapter() }
            let next = sheet(incoming!)
            next.scene.display(size: size, beat: 0, progress: 0)
            next.scene.layer.opacity = Float(smooth(exploration.progress / Chapter.revealEnd))
            active.append(next)
        } else { incoming = nil }
        for old in sheets where !active.contains(where: { $0.scene === old.scene }) { old.scene.layer.removeFromSuperlayer() }
        for (index, sheet) in active.enumerated() where sheet.scene.layer.superlayer == nil {
            root.insertSublayer(sheet.scene.layer, at: UInt32(index))
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
