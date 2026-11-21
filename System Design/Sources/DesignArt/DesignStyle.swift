import AppKit
import WallpaperPalette

package typealias Colour = LifeColour
package typealias Appearance = LifeAppearance

package struct DesignStyle: Equatable {
    package enum Tilt: String, CaseIterable { case varied, left, right, level }
    package enum Framing: String, CaseIterable { case balanced, close, wide }
    package var colour: Colour = .green
    package var appearance: Appearance = .system
    package var tilt: Tilt = .varied
    package var framing: Framing = .balanced
    package var systemLabel = false
    package var descriptions = true
    package var relationships = true
    package var groupNames = true
    package init() {}

    package mutating func apply(_ options: [String: String]) {
        if let value = options["colour"].flatMap(Colour.init) { colour = value }
        if let value = options["appearance"].flatMap(Appearance.init) { appearance = value }
        if let value = options["tilt"].flatMap(Tilt.init) { tilt = value }
        if let value = options["framing"].flatMap(Framing.init) { framing = value }
        if let value = options["systemLabel"] { systemLabel = value == "show" }
        if let value = options["descriptions"] { descriptions = value == "show" }
        if let value = options["relationships"] { relationships = value == "show" }
        if let value = options["groups"] { groupNames = value == "show" }
    }
}

struct Ink {
    let paper, wash, line, text, muted, accent, reverse: CGColor

    init(style: DesignStyle, dark: Bool, generation: Int, seed: UInt64) {
        let palette = LifePalette(darkness: dark ? 1 : 0, colour: style.colour, generation: generation, seed: seed)
        let field = palette.background[0]
        let pigment = palette.cells[2]
        // The Life greys switch to pale ink on charcoal. Chromatic schemes keep dark ink on dyed paper.
        let paleInk = (style.colour == .original && dark) || style.colour == .darkGrey
        let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let black = CGColor(srgbRed: 0.025, green: 0.028, blue: 0.022, alpha: 1)
        let page = mix(field, paleInk ? black : white, paleInk ? 0.08 : (dark ? 0.28 : 0.38))
        paper = page
        wash = mix(page, paleInk ? pigment : white, paleInk ? 0.18 : 0.32)
        text = mix(pigment, paleInk ? white : black, paleInk ? 0.81 : 0.68)
        line = mix(page, text, 0.64)
        muted = mix(page, text, 0.90)
        accent = mix(palette.cells[3], text, 0.44)
        reverse = mix(page, paleInk ? black : white, 0.48)
    }
}

func mix(_ a: CGColor, _ b: CGColor, _ t: CGFloat) -> CGColor {
    let x = a.components!, y = b.components!
    return CGColor(srgbRed: x[0] + (y[0] - x[0]) * t, green: x[1] + (y[1] - x[1]) * t,
                   blue: x[2] + (y[2] - x[2]) * t, alpha: 1)
}

func smooth(_ t: CGFloat) -> CGFloat {
    let u = max(0, min(1, t))
    return u * u * (3 - 2 * u)
}

func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
}

extension CGRect {
    var centre: CGPoint { CGPoint(x: midX, y: midY) }
}

func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular, mono: Bool = false) -> NSFont {
    mono ? .monospacedSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
}

func measure(_ text: String, _ font: NSFont) -> CGFloat {
    ceil((text as NSString).size(withAttributes: [.font: font]).width)
}
