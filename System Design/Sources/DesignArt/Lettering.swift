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

@MainActor
func componentContent(_ node: Component, size: CGSize, text: CGColor, descriptions: Bool) -> CALayer {
    let layer = CALayer()
    layer.bounds = CGRect(origin: .zero, size: size)
    let r = layer.bounds
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
    return layer
}
