import AppKit
import ScreenSaver

public enum LifeAppearance: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    public var id: String { rawValue }

    public func isDark(in appearance: NSAppearance) -> Bool {
        switch self {
        case .system: return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        case .light: return false
        case .dark: return true
        }
    }
}

public struct LifeSettings: Equatable {
    public static let moduleID = "io.github.thomasturrell.live-simulation-wallpapers.life.saver"
    public static let speedRange = 0.25...6.0
    public static let sizeRange = 3.0...10.0
    public static let spacingRange = 1.0...5.0
    public static let angleRange = -20.0...20.0
    public static let injectionOptions: [Double] = [0, 8, 16, 30, 60, 120]

    public var speed = 1.25
    public var size = 5.5
    public var spacing = 2.5
    public var angle = 12.0
    public var injection = 16.0
    public var appearance = LifeAppearance.system
    public var paused = false
    public var seed: UInt64 = 0x2B7D_A8C3_63FE_6491
    public var pitch: Double { size + spacing }

    public init() {}

    public static func moduleDefaults() -> UserDefaults {
        ScreenSaverDefaults(forModuleWithName: moduleID) ?? .standard
    }

    public init(defaults: UserDefaults) {
        self.init()
        func read(_ key: String, fallback: Double, in range: ClosedRange<Double>) -> Double {
            guard let number = defaults.object(forKey: key) as? NSNumber,
                  range.contains(number.doubleValue) else { return fallback }
            return number.doubleValue
        }
        speed = read("speed", fallback: speed, in: Self.speedRange)
        size = read("size", fallback: size, in: Self.sizeRange)
        spacing = read("spacing", fallback: spacing, in: Self.spacingRange)
        angle = read("angle", fallback: angle, in: Self.angleRange)
        let interval = read("injection", fallback: injection, in: 0...120)
        if Self.injectionOptions.contains(interval) { injection = interval }
        appearance = defaults.string(forKey: "appearance").flatMap(LifeAppearance.init) ?? .system
        paused = defaults.bool(forKey: "paused")
        if let value = defaults.string(forKey: "seed").flatMap(UInt64.init) { seed = value }
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(speed, forKey: "speed")
        defaults.set(size, forKey: "size")
        defaults.set(spacing, forKey: "spacing")
        defaults.set(angle, forKey: "angle")
        defaults.set(injection, forKey: "injection")
        defaults.set(appearance.rawValue, forKey: "appearance")
        defaults.set(paused, forKey: "paused")
        defaults.set(String(seed), forKey: "seed")
    }
}
