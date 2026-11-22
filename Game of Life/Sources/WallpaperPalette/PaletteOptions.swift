import AppKit

public enum LifeAppearance: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    public var id: String { rawValue }

    public func isDark(in appearance: NSAppearance) -> Bool {
        isDark(systemDark: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    }

    public func isDark(systemDark: Bool) -> Bool {
        switch self {
        case .system: return systemDark
        case .light: return false
        case .dark: return true
        }
    }
}

public enum LifeColour: String, CaseIterable, Identifiable {
    case spectrum, random, accent
    case green, yellow, orange, red, purple, blue, grey, darkGrey
    case original

    public var id: String { rawValue }
    public var title: String { self == .darkGrey ? "Dark Grey" : rawValue.capitalized }
}
