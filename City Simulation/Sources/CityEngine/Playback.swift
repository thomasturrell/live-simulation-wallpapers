import Foundation

/// Wall time is converted to fixed ticks here. Drawing can sample the city at any cadence.
public struct Playback {
    public enum Mode: Equatable { case suspended, playing, settling, still }

    public static let settleDuration = 2.7
    public private(set) var mode: Mode = .suspended
    public private(set) var city: City
    private var remainder: Double = 0
    private var settleElapsed: Double = 0

    public init(city: City) { self.city = city }

    public var needsTimer: Bool { mode == .playing || mode == .settling }

    public mutating func present(visible: Bool, animated: Bool) {
        if !visible {
            mode = .suspended
        } else if animated {
            mode = .playing
        } else if mode == .playing {
            mode = .settling
            settleElapsed = 0
        } else if mode == .suspended {
            mode = .still
        }
    }

    public mutating func advance(elapsed: Double) {
        guard elapsed.isFinite, elapsed > 0, needsTimer else { return }
        // Discard time lost to sleep or a stalled host rather than fast-forwarding.
        let interval = min(0.25, elapsed)
        if mode == .settling {
            let total = Self.settleDuration
            let before = settleElapsed / total
            settleElapsed = min(total, settleElapsed + interval)
            let after = settleElapsed / total
            // Integral of the quadratic slowdown. Cars reach zero speed at the end.
            remainder += total / 3 * (pow(1 - before, 3) - pow(1 - after, 3))
            if settleElapsed == total { mode = .still }
        } else {
            remainder += interval
        }
        let step = 1 / Double(City.ticksPerSecond)
        let count = Int((remainder + 1e-10) / step)
        remainder -= Double(count) * step
        for _ in 0..<count { city.step() }
    }
}
