import CoreGraphics

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
}
