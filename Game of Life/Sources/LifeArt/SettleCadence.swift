import Foundation

enum SettleCadence {
    static func delays(speed: Double) -> [TimeInterval] {
        let base = min(1.05, 1 / speed)
        let count = max(3, min(18, Int((3.0 / base).rounded())))
        return (0..<count).map { index in
            if index == 0 { return min(0.14, base * 0.55) }
            let progress = Double(index) / Double(count - 1)
            return base * (0.65 + 1.75 * pow(progress, 1.8))
        }
    }
}

public enum SaverPlaybackSignal {
    public static let started = Notification.Name("io.github.thomasturrell.live-simulation-wallpapers.life.saver.started")
    public static let stopped = Notification.Name("io.github.thomasturrell.live-simulation-wallpapers.life.saver.stopped")

    public static func post(_ name: Notification.Name) {
        DistributedNotificationCenter.default().postNotificationName(
            name, object: nil, userInfo: nil, deliverImmediately: true
        )
    }
}
