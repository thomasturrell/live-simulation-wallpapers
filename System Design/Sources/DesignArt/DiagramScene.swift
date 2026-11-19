import AppKit
import DesignEngine
import QuartzCore

@MainActor
final class DiagramScene {
    let layer = CALayer()
    let chapter: Chapter
    let layout: DiagramLayout
    private let world = CALayer()
    let ink: Ink
    private let style: DesignStyle
    private let caption: CALayer?
    private var legendViewport: CGSize?
    private var boxes: [(group: Subsystem, open: CALayer, closed: CALayer)] = []
    private(set) var components: [String: ComponentCard] = [:]
    private var edges: [(stroke: CAShapeLayer, marker: CALayer, label: CALayer?)] = []
    private let pulse: CAShapeLayer
    private let adjacency: [String: Set<String>]

    init(chapter: Chapter, layout: DiagramLayout, style: DesignStyle, ink: Ink) {
        self.chapter = chapter
        self.style = style
        caption = style.systemLabel ? CALayer() : nil
        self.ink = ink
        self.layout = layout
        adjacency = Dictionary(uniqueKeysWithValues: chapter.graph.nodes.map { ($0.id, chapter.graph.neighbours(of: $0.id)) })
        pulse = shape(CGPath(ellipseIn: CGRect(x: -4, y: -4, width: 8, height: 8), transform: nil),
                      fill: ink.text, stroke: ink.wash, width: 1.5)
        layer.anchorPoint = .zero
        layer.masksToBounds = true
        world.anchorPoint = .zero
        layer.addSublayer(world)
        buildGroups()
        buildEdges()
        world.addSublayer(pulse)
        for node in chapter.graph.nodes {
            let component = ComponentCard(node, rect: layout.nodes[node.id]!, ink: ink,
                                           principal: node.id == chapter.visit.entry, descriptions: style.descriptions)
            components[node.id] = component
            world.addSublayer(component.body)
        }
        if let caption {
            buildCaption(caption)
            layer.addSublayer(caption)
        }
    }

    private func buildGroups() {
        for group in chapter.graph.groups {
            let rect = layout.groups[group.id]!
            let body = CALayer()
            body.frame = rect
            let outline = shape(rounded(body.bounds, 22), fill: ink.accent.copy(alpha: group.parent == nil ? 0.048 : 0.065),
                                stroke: ink.line.copy(alpha: 0.63), width: 1.4)
            outline.lineDashPattern = [7, 6]
            body.addSublayer(outline)
            if style.groupNames {
                lettering(body, group.name.uppercased(), font(12, .semibold, mono: true), ink.muted,
                          CGRect(x: 17, y: rect.height - 24, width: rect.width - 34, height: 16), alignment: .left, tracking: 1)
            }
            world.addSublayer(body)
            let closed = CALayer()
            let width = measure(group.name, font(18, .medium)) + 52
            closed.frame = CGRect(x: rect.midX - width / 2, y: rect.midY - 25, width: width, height: 50)
            let card = rounded(closed.bounds, 12)
            let stack = shape(card, fill: ink.paper, stroke: ink.line)
            stack.position = CGPoint(x: 4, y: 4)
            closed.addSublayer(stack)
            closed.addSublayer(shape(card, fill: ink.wash, stroke: ink.line))
            lettering(closed, group.name, font(18, .medium), ink.text, CGRect(x: 0, y: 10, width: width, height: 25))
            world.addSublayer(closed)
            boxes.append((group, body, closed))
        }
    }

    private func buildEdges() {
        for (i, edge) in chapter.graph.edges.enumerated() {
            let route = layout.routes[i]
            let stroke = shape(route.path, stroke: ink.line, width: edge.kind == .flow ? 2.4 : 1.8)
            if edge.kind == .feedback || edge.kind == .inhibition { stroke.lineDashPattern = [7, 5] }
            if edge.kind == .signal || edge.kind == .dependency { stroke.lineDashPattern = [2, 4] }
            world.addSublayer(stroke)
            let b = route.point(at: 1), a = route.point(at: max(0, 1 - 7 / max(1, route.length)))
            let arrow = edge.kind == .inhibition
                ? shape(line([CGPoint(x: -4, y: -6), CGPoint(x: -4, y: 6)]), stroke: ink.text, width: 3)
                : shape(line([.zero, CGPoint(x: -11, y: 4.5), CGPoint(x: -11, y: -4.5)], closed: true), fill: ink.text)
            arrow.position = b
            arrow.setAffineTransform(CGAffineTransform(rotationAngle: atan2(b.y - a.y, b.x - a.x)))
            world.addSublayer(arrow)
            var label: CALayer?
            if style.relationships, let box = layout.labels[i] {
                let plate = CALayer()
                plate.frame = box
                plate.cornerRadius = 6
                plate.backgroundColor = ink.paper
                lettering(plate, edge.label, font(14, .medium), ink.muted, CGRect(x: 0, y: 0, width: box.width, height: 20))
                label = plate
                world.addSublayer(plate)
            }
            edges.append((stroke, arrow, label))
        }
    }

    private func buildCaption(_ caption: CALayer) {
        let title = chapter.graph.name
        let type = NSFont(name: "NewYorkMedium-Regular", size: 35) ?? NSFont(descriptor:
            font(35, .medium).fontDescriptor.withDesign(.serif)!, size: 35)!
        let width = max(300, measure(title, type) + 48)
        let lines = wrapped(chapter.graph.description, width: width - 44, type: font(14))
        let height = 90 + 18 * CGFloat(lines.count)
        caption.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        caption.anchorPoint = .zero
        caption.backgroundColor = ink.paper
        caption.addSublayer(shape(line([CGPoint(x: 1, y: 3), CGPoint(x: 1, y: height - 3)]), stroke: ink.accent, width: 3))
        lettering(caption, chapter.graph.category.title.uppercased(), font(11, .bold, mono: true), ink.muted,
                  CGRect(x: 18, y: height - 24, width: width - 26, height: 15), alignment: .left, tracking: 1.4)
        lettering(caption, title, type, ink.text,
                  CGRect(x: 17, y: height - 76, width: width - 20, height: 48), alignment: .left)
        for (i, text) in lines.enumerated() {
            lettering(caption, text, font(14), ink.muted, CGRect(x: 19, y: height - 92 - CGFloat(i) * 18, width: width - 24, height: 20),
                      alignment: .left)
        }
    }

    func display(camera: DiagramCamera, beat: Int, progress: Double, opening: HandoffProgress? = nil) {
        let size = camera.size
        if opening == nil { components[chapter.visit.entry]!.finishMorph() }
        layer.bounds = CGRect(origin: .zero, size: size)
        let t = smooth(progress / Chapter.revealEnd)
        let focus = chapter.focus(at: beat), previous = chapter.focus(at: max(0, beat - 1))
        func reveal(on start: Int) -> CGFloat {
            if start == 0 || start < beat { return 1 }
            return start == beat ? t : 0
        }
        func reveal(_ node: String) -> CGFloat {
            let normal = reveal(on: chapter.nodeRevealBeats[node]!)
            if let opening, node != chapter.visit.entry { return normal * opening.neighbour }
            return normal
        }
        let surroundings = opening?.surroundings ?? 1
        caption?.opacity = Float(surroundings)
        for box in boxes {
            let members = layout.members[box.group.id]!
            let opened = members.map(reveal).max() ?? 0
            box.open.opacity = Float(opened * surroundings)
            // A closed subsystem first appears as a stack when an adjacent subsystem is visible.
            let near = members.contains { node in adjacency[node]!.contains { reveal($0) > 0.8 } }
            box.closed.opacity = near && style.groupNames ? Float((1 - opened) * 0.85 * surroundings) : 0
        }
        for (id, layers) in components {
            let component = layers.body
            component.isHidden = false
            layers.focus.opacity = Float((previous == id ? 1 - t : 0) + (focus == id ? t : 0))
            let prominent: (String) -> CGFloat = { f in id == f || self.adjacency[f]!.contains(id) ? 1 : 0.66 }
            let alpha = reveal(id)
            component.opacity = Float(alpha * (prominent(previous) * (1 - t) + prominent(focus) * t))
            if alpha > 0 && alpha < 1 { component.setAffineTransform(CGAffineTransform(scaleX: 0.93 + alpha * 0.07, y: 0.93 + alpha * 0.07)) }
            else if !component.affineTransform().isIdentity { component.setAffineTransform(.identity) }
        }
        var active: [Int] = []
        for (i, edge) in chapter.graph.edges.enumerated() {
            let visible = reveal(on: chapter.edgeRevealBeats[i]) * (opening?.connection ?? 1)
            let related = edge.source == focus || edge.target == focus
            let parts = edges[i]
            let backwards = opening != nil && edge.target == chapter.visit.entry
            parts.stroke.strokeStart = backwards ? 1 - visible : 0
            parts.stroke.strokeEnd = backwards ? 1 : visible
            parts.stroke.opacity = related ? 1 : 0.62
            parts.marker.opacity = Float(smooth((visible - 0.7) / 0.3))
            parts.label?.opacity = Float(smooth((visible - 0.5) * 2) * (related ? 1 : 0.8))
            if related && visible >= 0.98 && edge.kind != .dependency { active.append(i) }
        }
        pulse.opacity = 0
        if beat != chapter.lastBeat, !active.isEmpty, progress > Chapter.pulseStart, progress < Chapter.pulseEnd {
            let i = active[(beat + Int(chapter.visit.seed % UInt64(active.count))) % active.count]
            let u = (progress - Chapter.pulseStart) / (Chapter.pulseEnd - Chapter.pulseStart)
            pulse.position = layout.routes[i].point(at: u)
            pulse.opacity = Float(smooth(u * 8) * smooth((1 - u) * 8))
        }
        frame(camera: camera, beat: beat, fraction: t)
    }

    private func frame(camera: DiagramCamera, beat: Int, fraction: CGFloat) {
        let size = camera.size, factor = camera.factor
        // Hold the camera while neighbours develop. Once a new region becomes the subject,
        // ease towards it; the handoff finishes on the common component in both diagrams.
        func anchor(_ step: Int) -> CGPoint {
            let id = step >= chapter.lastBeat - 1 ? chapter.exit : chapter.focus(at: step - step % 3)
            let centre = layout.nodes[id]!.centre
            if step >= chapter.lastBeat - 1 { return centre }
            let count = min(chapter.order.count, chapter.firstCount + step - step % 3)
            let visible = chapter.order.prefix(count).compactMap { layout.nodes[$0]?.centre }
            let mean = visible.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
            let dx = (mean.x / CGFloat(count) - centre.x) * factor
            let dy = (mean.y / CGFloat(count) - centre.y) * factor
            return CGPoint(x: centre.x + max(-size.width * 0.20, min(size.width * 0.20, dx)) / factor,
                           y: centre.y + max(-size.height * 0.19, min(size.height * 0.19, dy)) / factor)
        }
        let previous = beat == 0 && chapter.visit.linkedEntry ? layout.nodes[chapter.visit.entry]!.centre : anchor(max(0, beat - 1))
        let centre = lerp(previous, anchor(beat), fraction)
        let transform = camera.transform
        let offset = centre.applying(transform)
        world.position = CGPoint(x: camera.focusPoint.x - offset.x, y: camera.focusPoint.y - offset.y)
        world.setAffineTransform(transform)
        guard let caption, legendViewport != size else { return }
        legendViewport = size
        let captionScale = min(camera.scale, size.width * 0.79 / caption.bounds.width)
        let legendTransform = CGAffineTransform(rotationAngle: camera.angle).scaledBy(x: captionScale, y: captionScale)
        let extent = caption.bounds.applying(legendTransform)
        caption.setAffineTransform(legendTransform)
        // Choose a margin once for the whole visit. Consider each planned camera stop
        // so the legend can avoid component titles without hopping between corners.
        let margin = 22 * camera.scale
        var origins = [CGPoint(x: margin, y: margin), CGPoint(x: size.width - margin - extent.width, y: margin)]
        origins += origins.map { CGPoint(x: $0.x, y: size.height - margin - extent.height) }
        var penalties: [CGFloat] = [0, 0.1, 1.5, 1.6]
        let clock = CGRect(x: size.width * 0.30, y: size.height * 0.69, width: size.width * 0.40, height: size.height * 0.31)
        for i in origins.indices {
            let legend = CGRect(origin: origins[i], size: extent.size)
            if legend.intersects(clock) { penalties[i] += 6 }
            for step in 0...chapter.lastBeat {
                let centre = anchor(step).applying(transform)
                for id in chapter.order.prefix(chapter.firstCount + step) {
                    let point = layout.nodes[id]!.centre.applying(transform)
                    let title = CGPoint(x: point.x - centre.x + camera.focusPoint.x, y: point.y - centre.y + camera.focusPoint.y)
                    if legend.contains(title) { penalties[i] += id == chapter.focus(at: step) ? 4 : 1 }
                }
            }
        }
        let origin = origins[penalties.indices.min { penalties[$0] < penalties[$1] }!]
        caption.position = CGPoint(x: origin.x - extent.minX, y: origin.y - extent.minY)
    }
}
