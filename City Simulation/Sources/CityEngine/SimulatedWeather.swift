import Foundation

public enum Season: Int, CaseIterable, Sendable {
    case spring, summer, autumn, winter

    public var title: String { ["Spring", "Summer", "Autumn", "Winter"][rawValue] }

    /// Percentages for new weather spells. Keep each row's total at 100.
    public var weatherProbabilities: WeatherProbabilities {
        switch self {
        case .spring: return .init(clear: 40, cloudy: 30, rain: 30, snow: 0)
        case .summer: return .init(clear: 60, cloudy: 25, rain: 15, snow: 0)
        case .autumn: return .init(clear: 25, cloudy: 30, rain: 40, snow: 5)
        case .winter: return .init(clear: 20, cloudy: 25, rain: 20, snow: 35)
        }
    }
}

public struct WeatherProbabilities: Equatable, Sendable {
    public let clear: Int
    public let cloudy: Int
    public let rain: Int
    public let snow: Int
    public var total: Int { clear + cloudy + rain + snow }

    public init(clear: Int, cloudy: Int, rain: Int, snow: Int) {
        precondition([clear, cloudy, rain, snow].allSatisfy { (0...100).contains($0) } && clear + cloudy + rain + snow == 100)
        self.clear = clear; self.cloudy = cloudy; self.rain = rain; self.snow = snow
    }

    public func condition(for roll: Int) -> WeatherKind {
        precondition((0..<100).contains(roll))
        if roll < clear { return .clear }
        if roll < clear + cloudy { return .cloudy }
        if roll < clear + cloudy + rain { return .rain }
        return .snow
    }
}

/// Weather is a pure function of the saved city tick and its separate seed.
/// It cannot consume traffic/development randomness or advance while suspended.
public enum SimulatedWeather {
    public static let period = City.ticksPerSecond * 150
    public static let transition = City.ticksPerSecond * 24

    public static func season(at tick: Int) -> Season {
        Season(rawValue: (tick / (City.dayLength * 2)) % 4)!
    }

    static func target(slot: Int, seed: UInt64) -> EnvironmentalWeather {
        let tick = slot * period
        let random = hash(seed &+ UInt64(slot) &* 0x9E3779B97F4A7C15)
        let kind = season(at: tick).weatherProbabilities.condition(for: Int(random % 100))
        var weather = EnvironmentalWeather(kind)
        // Wind has its own random stream and can accompany every condition.
        weather.wind = Double(hash(random ^ 0x7769_6E64) % 91) / 100
        return weather
    }

    public static func at(tick: Int, seed: UInt64) -> EnvironmentalWeather {
        let slot = tick / period
        let current = target(slot: slot, seed: seed)
        let previous = target(slot: max(0, slot - 1), seed: seed)
        let elapsed = tick % period
        var weather = elapsed < transition
            ? previous.mixed(with: current, fraction: Environment.smooth(Double(elapsed) / Double(transition)))
            : current
        // Settled snow melts over the following spell, independently of flakes.
        if previous.snowCover > current.snowCover {
            weather.snowCover = previous.snowCover * (1 - Environment.smooth(Double(elapsed) / Double(period)))
        }
        return weather
    }

    private static func hash(_ value: UInt64) -> UInt64 {
        var n = value
        n = (n ^ (n >> 30)) &* 0xBF58476D1CE4E5B9
        n = (n ^ (n >> 27)) &* 0x94D049BB133111EB
        return n ^ (n >> 31)
    }
}
