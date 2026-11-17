import AppKit
import QuartzCore

@MainActor
package final class LifeLayers {
    package let root = CALayer()
    private let backdrop = CAGradientLayer()
    private let steady = (0..<5).map { _ in CAShapeLayer() }
    private let births = (0..<5).map { _ in CAShapeLayer() }
    private let deaths = (0..<5).map { _ in CAShapeLayer() }
    private let logo = LifeBrandingLayer()
    private var palette: LifePalette?
    private var allShapes: [CAShapeLayer] { steady + births + deaths }
    package var brandingArtwork: LifeBrandingArtwork {
        get { logo.artwork }
        set {
            logo.artwork = newValue
            if let palette { logo.update(viewport: root.bounds.size, palette: palette) }
        }
    }

    package init() {
        root.masksToBounds = true
        for layer in [backdrop] + allShapes { root.addSublayer(layer) }
        backdrop.startPoint = CGPoint(x: 0.5, y: 1)
        backdrop.endPoint = CGPoint(x: 0.5, y: 0)
        root.addSublayer(logo.layer)
    }

    package var contentsScale: CGFloat = 1 {
        didSet {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            backdrop.contentsScale = contentsScale
            for shape in allShapes { shape.contentsScale = contentsScale }
            CATransaction.commit()
        }
    }

    package func setPalette(_ palette: LifePalette) {
        self.palette = palette
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.colors = palette.background
        for group in [steady, births, deaths] {
            for (shape, color) in zip(group, palette.cells) { shape.fillColor = color }
        }
        logo.update(viewport: root.bounds.size, palette: palette)
        CATransaction.commit()
    }

    package func draw(_ scene: LifeScene, animate: Bool, duration: TimeInterval) {
        let paths = LifePaths(world: scene.world, layout: scene.layout,
                              settings: scene.settings, animate: animate)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let bounds = CGRect(origin: .zero, size: scene.viewport)
        if root.bounds != bounds {
            root.bounds = bounds
            if let palette { logo.update(viewport: bounds.size, palette: palette) }
        }
        backdrop.frame = bounds
        for shape in allShapes where shape.frame != bounds { shape.frame = bounds }
        for i in 0..<steady.count {
            steady[i].path = paths.living[i]
            births[i].removeAnimation(forKey: "opacity")
            deaths[i].removeAnimation(forKey: "opacity")
            births[i].path = paths.births[i]
            deaths[i].path = paths.deaths[i]
            births[i].opacity = 1
            deaths[i].opacity = 0
            if !paths.births[i].isEmpty { fade(births[i], from: 0, to: 1, duration: duration) }
            if !paths.deaths[i].isEmpty { fade(deaths[i], from: 1, to: 0, duration: duration) }
        }
        CATransaction.commit()
    }

    private func fade(_ shape: CAShapeLayer, from: Float, to: Float, duration: TimeInterval) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        shape.add(animation, forKey: "opacity")
    }

}
