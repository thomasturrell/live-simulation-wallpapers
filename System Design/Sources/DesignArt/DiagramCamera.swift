import CoreGraphics
import DesignEngine

struct DiagramCamera: Equatable {
    let size: CGSize
    let scale, angle, zoom: CGFloat
    var factor: CGFloat { scale * zoom }
    var transform: CGAffineTransform { CGAffineTransform(rotationAngle: angle).scaledBy(x: factor, y: factor) }
    var focusPoint: CGPoint { CGPoint(x: size.width * (size.width < size.height ? 0.5 : 0.54), y: size.height * 0.48) }

    init(size: CGSize, style: DesignStyle, displaySeed: UInt64) {
        self.size = size
        scale = max(min(size.width / 1040, size.height / 650), size.height / 920, size.width / 1770)
        zoom = style.framing == .wide ? 0.80 : style.framing == .close ? 1.35 : 1
        let tilt = CGFloat.pi * 17 / 180
        switch style.tilt {
        case .left: angle = tilt
        case .right: angle = -tilt
        case .level: angle = 0
        case .varied: angle = displaySeed.isMultiple(of: 2) ? tilt : -tilt
        }
    }

    func stops(for chapter: Chapter, nodes: [String: CGRect]) -> [CGPoint] {
        let viewport = CGRect(origin: .zero, size: size).insetBy(dx: 12, dy: 12)
        var centre = nodes[chapter.visit.entry]!.centre
        return (0...chapter.lastBeat).map { beat in
            if beat >= chapter.lastBeat - 1 { return nodes[chapter.exit]!.centre }
            let focus = nodes[chapter.focus(at: beat)]!
            if beat.isMultiple(of: 3) {
                let visible = chapter.order.prefix(chapter.firstCount + beat)
                let sum = visible.reduce(CGPoint.zero) { sum, id in
                    let point = nodes[id]!.centre
                    return CGPoint(x: sum.x + point.x, y: sum.y + point.y)
                }
                let dx = sum.x / CGFloat(visible.count) - focus.midX
                let dy = sum.y / CGFloat(visible.count) - focus.midY
                let limitX = size.width * 0.20 / factor, limitY = size.height * 0.19 / factor
                centre = CGPoint(x: focus.midX + max(-limitX, min(limitX, dx)),
                                 y: focus.midY + max(-limitY, min(limitY, dy)))
            }
            // Hold the current stop between regional pans while the next card fits.
            // The inset leaves room for the sheet to lift during playback.
            let projected = focus.offsetBy(dx: -centre.x, dy: -centre.y).applying(transform)
                .offsetBy(dx: focusPoint.x, dy: focusPoint.y)
            if beat > 0 && !viewport.contains(projected) { centre = focus.centre }
            return centre
        }
    }
}
