import AppKit
import DesignEngine

/// All silhouettes use the same clockwise sequence of sides and corners. The cap
/// bows the top and bottom of a store, and the corner tangents round or bevel a card.
private struct CardContour {
    let inset: CGPoint
    let tangent: CGFloat
    let cap: CGFloat

    init(size: CGSize, kind: NodeKind) {
        let w = size.width / 2 - 1, h = size.height / 2 - 1
        tangent = kind == .hub || kind == .decision ? 0 : 0.55228475
        cap = kind == .store ? 12 : 0
        switch kind {
        case .sensor, .decision: inset = CGPoint(x: w, y: h)
        case .hub: inset = CGPoint(x: 19, y: h)
        case .store: inset = .zero
        case .entity: inset = CGPoint(x: 4, y: 4)
        case .process: inset = CGPoint(x: 16, y: 16)
        case .event: inset = CGPoint(x: h, y: h)
        }
    }

    func path(in bounds: CGRect, from old: Self, fraction t: CGFloat) -> CGPath {
        let r = bounds.insetBy(dx: 1, dy: 1)
        let d = lerp(old.inset, inset, t)
        let k = old.tangent + (tangent - old.tangent) * t
        let cap = old.cap + (cap - old.cap) * t
        let top = r.maxY - cap, bottom = r.minY + cap
        let left = r.minX, right = r.maxX
        let p = CGMutablePath()
        p.move(to: CGPoint(x: left + d.x, y: top))
        func curve(_ x: CGFloat, _ y: CGFloat, _ ax: CGFloat, _ ay: CGFloat, _ bx: CGFloat, _ by: CGFloat) {
            p.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: ax, y: ay), control2: CGPoint(x: bx, y: by))
        }
        curve(right - d.x, top, left + d.x, top + cap * 4 / 3, right - d.x, top + cap * 4 / 3)
        curve(right, top - d.y, right - d.x * (1 - k), top, right, top - d.y * (1 - k))
        p.addLine(to: CGPoint(x: right, y: bottom + d.y))
        curve(right - d.x, bottom, right, bottom + d.y * (1 - k), right - d.x * (1 - k), bottom)
        curve(left + d.x, bottom, right - d.x, bottom - cap * 4 / 3, left + d.x, bottom - cap * 4 / 3)
        curve(left, bottom + d.y, left + d.x * (1 - k), bottom, left, bottom + d.y * (1 - k))
        p.addLine(to: CGPoint(x: left, y: top - d.y))
        curve(left + d.x, top, left, top - d.y * (1 - k), left + d.x * (1 - k), top)
        p.closeSubpath()
        return p
    }
}

@MainActor
final class ComponentCard {
    let body = CALayer()
    let focus: CAShapeLayer
    private let content: CALayer
    private let node: Component
    private let size: CGSize
    private let contour: CardContour
    private let fill, stroke, text: CGColor
    private let width: CGFloat
    private let descriptions: Bool
    private let shadow, plate, rim: CAShapeLayer
    private var previous: ComponentCard?
    private var previousContent: CALayer?
    private var fraction: CGFloat = 1

    init(_ node: Component, rect: CGRect, ink: Ink, principal: Bool, descriptions: Bool) {
        self.node = node
        self.descriptions = descriptions
        size = rect.size
        contour = CardContour(size: rect.size, kind: node.kind)
        fill = principal ? ink.accent : ink.wash
        stroke = principal ? ink.text : ink.line
        text = principal ? ink.reverse : ink.text
        width = principal ? 2 : 1.6
        body.name = node.id
        body.frame = rect
        let path = contour.path(in: body.bounds, from: contour, fraction: 1)
        shadow = shape(path, fill: ink.line.copy(alpha: 0.23))
        shadow.position = CGPoint(x: 3, y: -4)
        plate = shape(path, fill: fill, stroke: stroke, width: width)
        rim = shape(Self.rimPath(in: body.bounds), stroke: text.copy(alpha: 0.65), width: 1.3)
        rim.opacity = node.kind == .store ? 1 : 0
        content = componentContent(node, size: size, text: text, descriptions: descriptions)
        content.position = body.bounds.centre
        focus = shape(path, stroke: ink.text, width: 3.2)
        for layer in [shadow, plate, rim, content, focus] { body.addSublayer(layer) }
    }

    private static func rimPath(in bounds: CGRect) -> CGPath {
        CGPath(ellipseIn: CGRect(x: 1, y: bounds.maxY - 24, width: bounds.width - 2, height: 22), transform: nil)
    }

    func setElevation(_ elevation: CGFloat) {
        shadow.position = CGPoint(x: 3 + 6 * elevation, y: -4 - 10 * elevation)
    }

    func morph(from source: ComponentCard, fraction t: CGFloat) {
        guard previous !== source || fraction != t else { return }
        if previous !== source {
            previousContent?.removeFromSuperlayer()
            let labels = componentContent(source.node, size: source.size, text: source.text, descriptions: source.descriptions)
            body.insertSublayer(labels, below: content)
            previousContent = labels
            previous = source
        }
        fraction = t
        body.bounds.size = CGSize(width: source.size.width + (size.width - source.size.width) * t,
                                  height: source.size.height + (size.height - source.size.height) * t)
        let path = contour.path(in: body.bounds, from: source.contour, fraction: t)
        for layer in [shadow, plate, focus] { layer.path = path }
        plate.fillColor = mix(source.fill, fill, t)
        plate.strokeColor = mix(source.stroke, stroke, t)
        plate.lineWidth = source.width + (width - source.width) * t
        rim.path = Self.rimPath(in: body.bounds)
        rim.opacity = Float((source.node.kind == .store ? 1 - t : 0) + (node.kind == .store ? t : 0))
        rim.strokeColor = mix(source.text, text, t).copy(alpha: 0.65)
        content.position = body.bounds.centre
        previousContent?.position = content.position
        content.opacity = Float(smooth((t - 0.38) / 0.45))
        previousContent?.opacity = Float(1 - smooth((t - 0.16) / 0.45))
    }

    func finishMorph() {
        guard let previous else { return }
        morph(from: previous, fraction: 1)
        previousContent?.removeFromSuperlayer()
        previousContent = nil
        self.previous = nil
    }
}
