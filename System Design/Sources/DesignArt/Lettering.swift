import AppKit
import QuartzCore
import DesignEngine

func shape(_ path: CGPath, fill: CGColor? = nil, stroke: CGColor? = nil, width: CGFloat = 1) -> CAShapeLayer {
    let layer = CAShapeLayer()
    layer.path = path
    layer.fillColor = fill
    layer.strokeColor = stroke
    layer.lineWidth = width
    layer.lineJoin = .round
    layer.lineCap = .round
    return layer
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func line(_ points: [CGPoint], closed: Bool = false) -> CGPath {
    let path = CGMutablePath()
    path.addLines(between: points)
    if closed { path.closeSubpath() }
    return path
}

@discardableResult
func lettering(_ parent: CALayer, _ string: String, _ type: NSFont, _ color: CGColor,
               _ rect: CGRect, alignment: CATextLayerAlignmentMode = .center, tracking: CGFloat = 0) -> CATextLayer {
    let layer = CATextLayer()
    layer.contentsScale = 2
    layer.string = NSAttributedString(string: string, attributes: [.font: type, .foregroundColor: NSColor(cgColor: color)!,
                                                                    .kern: tracking])
    layer.alignmentMode = alignment
    layer.frame = rect
    parent.addSublayer(layer)
    return layer
}

func wrapped(_ string: String, width: CGFloat, type: NSFont) -> [String] {
    var lines: [String] = []
    var current = ""
    for word in string.split(separator: " ") {
        let next = current.isEmpty ? String(word) : current + " " + word
        if !current.isEmpty && measure(next, type) > width {
            lines.append(current)
            current = String(word)
        } else { current = next }
    }
    if !current.isEmpty { lines.append(current) }
    return lines
}

private func silhouette(_ r: CGRect, kind: NodeKind) -> CGPath {
    switch kind {
    case .entity, .process: return rounded(r, kind == .entity ? 4 : 16)
    case .event: return rounded(r, r.height / 2)
    case .sensor: return CGPath(ellipseIn: r, transform: nil)
    case .hub, .decision:
        let d = kind == .decision ? r.width * 0.5 : 19
        return line([CGPoint(x: r.minX, y: r.midY), CGPoint(x: r.minX + d, y: r.maxY),
                     CGPoint(x: r.maxX - d, y: r.maxY), CGPoint(x: r.maxX, y: r.midY),
                     CGPoint(x: r.maxX - d, y: r.minY), CGPoint(x: r.minX + d, y: r.minY)], closed: true)
    case .store:
        let p = CGMutablePath()
        let cap: CGFloat = 12
        p.move(to: CGPoint(x: r.minX, y: r.maxY - cap))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.maxY - cap), control1: CGPoint(x: r.minX, y: r.maxY + cap / 3),
                   control2: CGPoint(x: r.maxX, y: r.maxY + cap / 3))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + cap))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + cap), control1: CGPoint(x: r.maxX, y: r.minY - cap / 3),
                   control2: CGPoint(x: r.minX, y: r.minY - cap / 3))
        p.closeSubpath()
        return p
    }
}

@MainActor
func componentLayer(_ node: Component, rect: CGRect, ink: Ink, principal: Bool, descriptions: Bool) -> (body: CALayer, focus: CAShapeLayer) {
    let layer = CALayer()
    layer.frame = rect
    let r = layer.bounds
    let path = silhouette(r.insetBy(dx: 1, dy: 1), kind: node.kind)
    let shadow = shape(path, fill: ink.line.copy(alpha: 0.23))
    shadow.position = CGPoint(x: 3, y: -4)
    layer.addSublayer(shadow)
    let fill = principal ? ink.accent : ink.wash
    let text = principal ? ink.reverse : ink.text
    layer.addSublayer(shape(path, fill: fill, stroke: principal ? ink.text : ink.line, width: principal ? 2 : 1.6))
    if node.kind == .store {
        let rim = CGRect(x: 1, y: r.maxY - 24, width: r.width - 2, height: 22)
        layer.addSublayer(shape(CGPath(ellipseIn: rim, transform: nil), stroke: text.copy(alpha: 0.65), width: 1.3))
    }
    let detail = descriptions ? node.detail : nil
    let typeSize: CGFloat = 10
    let bodyType = font(13.5)
    let lines = detail.map { wrapped($0, width: r.width * (node.kind == .decision ? 0.50 : 0.83), type: bodyType) } ?? []
    let middle = r.midY - (node.kind == .store ? 5 : 0)
    let titleY = middle - 14 + CGFloat(lines.count) * 8
    lettering(layer, node.name, font(20, .semibold), text, CGRect(x: 0, y: titleY, width: r.width, height: 26))
    let role = node.kind == .store ? "STORE" : node.kind.rawValue.uppercased()
    let roleType = font(typeSize, .semibold, mono: true)
    var heading = CGRect(x: 0, y: titleY + 26, width: r.width, height: 14)
    if let name = node.symbol, let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil),
       let bitmap = symbol.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        let width = measure(role, roleType) + 1.6 * CGFloat(role.count)
        let glyph = CALayer()
        glyph.bounds = CGRect(x: 0, y: 0, width: 19, height: 17)
        glyph.position = CGPoint(x: (r.width - width) / 2 - 3, y: heading.midY + 1)
        glyph.backgroundColor = text
        let mask = CALayer()
        mask.frame = glyph.bounds
        mask.contents = bitmap
        mask.contentsGravity = .resizeAspect
        glyph.mask = mask
        layer.addSublayer(glyph)
        heading.origin.x += 12
    }
    lettering(layer, role, roleType, text.copy(alpha: 0.88)!, heading, tracking: 1.6)
    for (i, value) in lines.enumerated() {
        lettering(layer, value, bodyType, text, CGRect(x: 0, y: titleY - 17 * CGFloat(i + 1), width: r.width, height: 18))
    }
    let focus = shape(path, stroke: ink.text, width: 3.2)
    layer.addSublayer(focus)
    return (layer, focus)
}
