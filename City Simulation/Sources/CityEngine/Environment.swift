import Foundation

public enum EnvironmentMode: String, Codable, CaseIterable, Sendable {
    case simulationWorld, realWorldNorthern, realWorldSouthern

    public var title: String {
        switch self {
        case .simulationWorld: return "Simulation World"
        case .realWorldNorthern: return "Real World · Northern Hemisphere"
        case .realWorldSouthern: return "Real World · Southern Hemisphere"
        }
    }
    public var isSimulation: Bool { self == .simulationWorld }
}

public enum WeatherKind: String, CaseIterable, Sendable {
    case clear, cloudy, rain, snow
    public var title: String { rawValue.capitalized }
}

/// CityPreview overrides presentation without changing the saved city clock.
public struct EnvironmentPreview: Equatable, Sendable {
    /// One-based fractional month: 1...13 in Real World, 1...5 in Simulation World.
    public var month: Double?
    public var darkness: Double?
    public var weather: WeatherKind?
    public var wind: Double?
    public init() {}
}

public struct EnvironmentalWeather: Equatable, Sendable {
    public var cloud: Double
    public var rain: Double
    public var snow: Double
    public var wind: Double
    public var snowCover: Double
    public init(cloud: Double = 0, rain: Double = 0, snow: Double = 0, wind: Double = 0, snowCover: Double = 0) {
        self.cloud = cloud; self.rain = rain; self.snow = snow; self.wind = wind; self.snowCover = snowCover
    }
    public init(_ kind: WeatherKind) {
        switch kind {
        case .clear: self.init()
        case .cloudy: self.init(cloud: 0.8)
        case .rain: self.init(cloud: 0.9, rain: 0.8)
        case .snow: self.init(cloud: 0.7, snow: 0.75, snowCover: 0.8)
        }
    }
    public var kind: WeatherKind { snow > 0.1 ? .snow : rain > 0.1 ? .rain : cloud > 0.5 ? .cloudy : .clear }
    public var isValid: Bool { [cloud, rain, snow, wind, snowCover].allSatisfy { $0.isFinite && (0...1).contains($0) } }
    public func mixed(with other: Self, fraction: Double) -> Self {
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * fraction }
        return Self(cloud: mix(cloud, other.cloud), rain: mix(rain, other.rain), snow: mix(snow, other.snow),
                    wind: mix(wind, other.wind), snowCover: mix(snowCover, other.snowCover))
    }
    public var quantized: Self {
        func q(_ n: Double) -> Double { (n * 16).rounded() / 16 }
        return Self(cloud: q(cloud), rain: q(rain), snow: q(snow), wind: q(wind), snowCover: q(snowCover))
    }
}

public struct SeasonAppearance: Equatable, Sendable {
    public let foliage: Double
    public let blossom: Double
    public let flowers: Double
    public let warmth: Double
    public let leafColor: UInt32
    public let grassColor: UInt32

    /// First-day-of-month reference artwork parameters, January through December.
    public static let months: [Self] = [
        .init(foliage: 0.02, blossom: 0, flowers: 0, warmth: 0, leafColor: 0x9A8754, grassColor: 0x99977C),
        .init(foliage: 0.04, blossom: 0, flowers: 0.03, warmth: 0.1, leafColor: 0x8B9A56, grassColor: 0x909572),
        .init(foliage: 0.24, blossom: 0.45, flowers: 0.25, warmth: 0.35, leafColor: 0x9DB568, grassColor: 0x8DAB6D),
        .init(foliage: 0.68, blossom: 1, flowers: 0.8, warmth: 0.55, leafColor: 0x8DA95D, grassColor: 0x8DA864),
        .init(foliage: 0.96, blossom: 0.15, flowers: 1, warmth: 0.75, leafColor: 0x789B55, grassColor: 0x88A25F),
        .init(foliage: 1, blossom: 0, flowers: 0.8, warmth: 0.95, leafColor: 0x6A914F, grassColor: 0x82975D),
        .init(foliage: 1, blossom: 0, flowers: 0.6, warmth: 1, leafColor: 0x709451, grassColor: 0x8B9B60),
        .init(foliage: 0.98, blossom: 0, flowers: 0.4, warmth: 0.95, leafColor: 0x839653, grassColor: 0x999E66),
        .init(foliage: 0.9, blossom: 0, flowers: 0.18, warmth: 0.7, leafColor: 0xA49A4F, grassColor: 0xA2A06A),
        .init(foliage: 0.62, blossom: 0, flowers: 0.04, warmth: 0.45, leafColor: 0xBA7845, grassColor: 0xA1986C),
        .init(foliage: 0.16, blossom: 0, flowers: 0, warmth: 0.2, leafColor: 0xA46A45, grassColor: 0x969477),
        .init(foliage: 0.03, blossom: 0, flowers: 0, warmth: 0.05, leafColor: 0x9A8053, grassColor: 0x96957E)
    ]

    public static func at(month: Double) -> Self {
        let phase = Environment.wrap(month, length: 12)
        let index = Int(phase)
        let a = months[index], b = months[(index + 1) % 12]
        let t = Environment.smooth(phase - Double(index))
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        func color(_ a: UInt32, _ b: UInt32) -> UInt32 {
            [0, 8, 16].reduce(0) { $0 | UInt32(mix(Double((a >> $1) & 255), Double((b >> $1) & 255)).rounded()) << $1 }
        }
        return .init(foliage: mix(a.foliage, b.foliage), blossom: mix(a.blossom, b.blossom),
                     flowers: mix(a.flowers, b.flowers), warmth: mix(a.warmth, b.warmth),
                     leafColor: color(a.leafColor, b.leafColor), grassColor: color(a.grassColor, b.grassColor))
    }
}

public struct EnvironmentFrame: Equatable, Sendable {
    /// Shared artwork phase: zero-based January...December, already hemisphere-adjusted.
    public let month: Double
    public let darkness: Double
    public let weather: EnvironmentalWeather
    public var season: SeasonAppearance { SeasonAppearance.at(month: month) }
    public var quantized: Self {
        Self(month: (month * 64).rounded() / 64, darkness: (darkness * 24).rounded() / 24, weather: weather.quantized)
    }
}

public enum Environment {
    public static let yearTicks = City.dayLength * 8
    public static func wrap(_ value: Double, length: Double) -> Double {
        guard value.isFinite else { return 0 }
        return (value.truncatingRemainder(dividingBy: length) + length).truncatingRemainder(dividingBy: length)
    }
    static func smooth(_ value: Double) -> Double { let t = max(0, min(1, value)); return t * t * (3 - 2 * t) }

    /// The Mac's local Gregorian calendar, including actual month lengths and leap years.
    public static func realMonth(at date: Date, timeZone: TimeZone = .current) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let month = calendar.dateInterval(of: .month, for: date) else { return 0 }
        return Double(calendar.component(.month, from: date) - 1) + date.timeIntervalSince(month.start) / month.duration
    }
    public static func simulationMonth(tick: Int) -> Double { Double(tick % yearTicks) / Double(yearTicks) * 4 }
    public static func calendarLabel(tick: Int) -> String {
        let day = tick / City.dayLength
        return "Year \(day / 8 + 1) · Month \(day % 8 / 2 + 1) · Day \(day % 2 + 1)"
    }

    public static func frame(city: City, mode: EnvironmentMode = .simulationWorld, date: Date = Date(),
                             systemDark: Bool = false, preview: EnvironmentPreview = .init(),
                             timeZone: TimeZone = .current) -> EnvironmentFrame {
        let month: Double
        if mode.isSimulation {
            month = 2 + (preview.month.map { $0 - 1 } ?? simulationMonth(tick: city.tick)) * 3
        } else {
            month = (preview.month.map { $0 - 1 } ?? realMonth(at: date, timeZone: timeZone)) + (mode == .realWorldSouthern ? 6 : 0)
        }
        var weather = preview.weather.map(EnvironmentalWeather.init) ??
            (mode.isSimulation ? SimulatedWeather.at(tick: city.tick, seed: city.environmentSeed) : EnvironmentalWeather())
        if let wind = preview.wind { weather.wind = max(0, min(1, wind)) }
        return .init(month: wrap(month, length: 12),
                     darkness: preview.darkness.map { max(0, min(1, $0)) } ?? (mode.isSimulation ? city.darkness : (systemDark ? 1 : 0)),
                     weather: weather)
    }
}
