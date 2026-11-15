import AppKit
import Testing
@testable import LifeArt

@Test(arguments: [0.25, 0.5, 1.25, 3.0, 6.0])
func desktopCadenceSlowsAndEnds(speed: Double) {
    let delays = SettleCadence.delays(speed: speed)
    #expect((3...18).contains(delays.count))
    #expect(delays[0] < 0.2)
    #expect(zip(delays, delays.dropFirst()).allSatisfy { $0 < $1 })
    #expect((3...6).contains(delays.reduce(0, +)))
}

@Test @MainActor
func desktopSettlesAndResumesAfterReappearing() throws {
    _ = NSApplication.shared
    let frame = CGRect(x: 0, y: 0, width: 640, height: 360)
    var settings = LifeSettings()
    settings.appearance = .dark
    let view = LifeView(frame: frame, settings: settings, tracksWindowOcclusion: false)
    view.playback = .settleOnReveal

    func snapshot() throws -> Data {
        let data = try #require(view.snapshot(scale: 1)?.dataProvider?.data)
        return data as Data
    }

    func wait(_ duration: Double) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: duration))
    }

    let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: true)
    let initial = try snapshot()
    window.contentView = view
    wait(0.45)
    #expect(try snapshot() != initial)

    wait(SettleCadence.delays(speed: settings.speed).reduce(0, +) + 0.8)
    let settled = try snapshot()
    wait(1.0)
    #expect(try snapshot() == settled)

    view.isHidden = true
    wait(0.35)
    #expect(try snapshot() == settled)
    view.isHidden = false
    wait(0.45)
    #expect(try snapshot() != settled)

    settings.paused = true
    view.settings = settings
    let paused = try snapshot()
    wait(1.0)
    #expect(try snapshot() == paused)
    window.contentView = nil
}
