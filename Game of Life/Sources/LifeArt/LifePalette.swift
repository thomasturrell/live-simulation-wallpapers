import AppKit

package struct LifePalette {
    let background: [CGColor]
    let cells: [CGColor]

    private typealias RGB = SIMD3<Double>
    private static let green = rgb(0x9bb749)
    private static let yellow = rgb(0xe8ca60)
    private static let orange = rgb(0xe8a05a)
    private static let red = rgb(0xe47d77)
    private static let purple = rgb(0xb58ad7)
    private static let blue = rgb(0x76a7e8)
    private static let spectrum = [green, yellow, orange, red, purple, blue]
    private static let generationsPerHue = 40

    init(darkness: Double, colour: LifeColour, generation: Int, seed: UInt64) {
        let backgrounds: [RGB]
        let inks: [RGB]
        switch colour {
        case .original:
            backgrounds = Self.blend(light: [0xf5f3ee, 0xeceae5], dark: [0x151618, 0x101112], by: darkness)
            inks = Self.blend(light: [0xa8aaa5, 0x8d908b, 0x799387, 0x9887a1, 0xa28e6d],
                              dark: [0x505457, 0x686b6c, 0x677b70, 0x72647c, 0x82745d], by: darkness)
        case .darkGrey:
            backgrounds = Self.blend(light: [0x535353, 0x464646], dark: [0x2d2d2d, 0x222222], by: darkness)
            inks = Self.blend(light: [0xbbbbbb, 0xd0d0d0, 0xb0b0b0, 0xc3c3c3, 0xdadada],
                              dark: [0x888888, 0xaaaaaa, 0x7f7f7f, 0x999999, 0xb6b6b6], by: darkness)
        default:
            let hue = Self.hue(for: colour, generation: generation, seed: seed, dark: darkness >= 0.5)
            let paper = Self.mix(Self.rgb(0xffffff), Self.rgb(0x121212), by: darkness)
            let ink = Self.rgb(0x111111)
            backgrounds = [0.30, 0.22].map { Self.mix(hue, paper, by: $0 + 0.09 * darkness) }
            inks = [0.26, 0.17, 0.30, 0.21, 0.33].map { Self.mix(ink, hue, by: $0 - 0.07 * darkness) }
        }
        background = backgrounds.map(Self.cgColor)
        cells = inks.map(Self.cgColor)
    }

    private static func hue(for colour: LifeColour, generation: Int, seed: UInt64, dark: Bool) -> RGB {
        switch colour {
        case .spectrum:
            let segment = (generation / generationsPerHue) % spectrum.count
            let fraction = Double(generation % generationsPerHue) / Double(generationsPerHue)
            let eased = fraction * fraction * (3 - 2 * fraction)
            return mix(spectrum[segment], spectrum[(segment + 1) % spectrum.count], by: eased)
        case .random:
            // Pick once per cycle. Deriving it from the world keeps snapshots and restored playback in sync.
            let cycle = UInt64(generation / (generationsPerHue * spectrum.count))
            var bits = seed &+ cycle &* 0x9e3779b97f4a7c15
            bits = (bits ^ (bits >> 30)) &* 0xbf58476d1ce4e5b9
            bits = (bits ^ (bits >> 27)) &* 0x94d049bb133111eb
            bits ^= bits >> 31
            return spectrum[Int(bits % UInt64(spectrum.count))]
        case .accent:
            var accent = blue
            NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
                if let color = NSColor.controlAccentColor.usingColorSpace(.sRGB) {
                    // Lift deep system accents so the dark cell tones remain visible.
                    accent = mix(RGB(color.redComponent, color.greenComponent, color.blueComponent),
                                 rgb(0xffffff), by: 0.30)
                }
            }
            return accent
        case .green: return green
        case .yellow: return yellow
        case .orange: return orange
        case .red: return red
        case .purple: return purple
        case .blue: return blue
        case .grey: return rgb(0xa5a5a5)
        case .original, .darkGrey: preconditionFailure("Handled by the palette initializer")
        }
    }

    private static func blend(light: [Int], dark: [Int], by fraction: Double) -> [RGB] {
        zip(light, dark).map { mix(rgb($0), rgb($1), by: fraction) }
    }

    private static func mix(_ a: RGB, _ b: RGB, by fraction: Double) -> RGB {
        a + (b - a) * fraction
    }

    private static func rgb(_ hex: Int) -> RGB {
        RGB(Double((hex >> 16) & 255), Double((hex >> 8) & 255), Double(hex & 255)) / 255
    }

    private static func cgColor(_ rgb: RGB) -> CGColor {
        CGColor(srgbRed: rgb.x, green: rgb.y, blue: rgb.z, alpha: 1)
    }
}
