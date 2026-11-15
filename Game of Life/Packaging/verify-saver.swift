import AppKit
import QuartzCore
import ScreenSaver

// Runs the packaged plug-in in a lightweight AppKit host without installing it.
try MainActor.assumeIsolated {
    precondition(CommandLine.arguments.count == 2, "Pass the path to the .saver bundle.")
    _ = NSApplication.shared
    let bundle = Bundle(path: CommandLine.arguments[1])!
    try bundle.loadAndReturnError()
    guard let saverClass = bundle.principalClass as? ScreenSaverView.Type else {
        fatalError("Bundle principal class is not a ScreenSaverView.")
    }

    func paths(_ saver: ScreenSaverView) -> [CGPath?] {
        (saver.subviews.first?.layer?.sublayers ?? [])
            .compactMap { $0 as? CAShapeLayer }
            .map(\.path)
    }

    func tick() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.1))
    }

    let regular = NSRect(x: 0, y: 0, width: 2560, height: 1440)
    let portrait = NSRect(x: 0, y: 0, width: 1080, height: 1920)
    let left = saverClass.init(frame: regular, isPreview: false)!
    let right = saverClass.init(frame: portrait, isPreview: false)!
    precondition(left.hasConfigureSheet && left.configureSheet?.contentView != nil)

    let leftWindow = NSWindow(contentRect: regular, styleMask: .borderless, backing: .buffered, defer: true)
    let rightWindow = NSWindow(contentRect: portrait, styleMask: .borderless, backing: .buffered, defer: true)
    leftWindow.contentView = left
    rightWindow.contentView = right
    let initialLeft = paths(left)
    let initialRight = paths(right)
    precondition(initialLeft.count == 15 && initialRight.count == 15)
    left.startAnimation()
    right.startAnimation()
    let activeStart = clock()
    tick()
    let activeCPU = Double(clock() - activeStart) / Double(CLOCKS_PER_SEC)
    precondition(paths(left) != initialLeft && paths(right) != initialRight, "Both worlds should advance.")

    left.stopAnimation()
    rightWindow.contentView = nil
    let stopped = paths(left)
    let detached = paths(right)
    let stoppedStart = clock()
    tick()
    let stoppedCPU = Double(clock() - stoppedStart) / Double(CLOCKS_PER_SEC)
    precondition(paths(left) == stopped && paths(right) == detached, "Stopped and detached views should freeze.")
    right.stopAnimation()

    left.startAnimation()
    tick()
    precondition(paths(left) != stopped, "The stopped view should resume.")
    left.stopAnimation()
    print("Plug-in loaded and configured. Two viewport sizes animated. Stop, detach and resume passed.")
    print(String(format: "Test host CPU time over 1.1 s: %.1f ms active, %.1f ms stopped.",
                 activeCPU * 1_000, stoppedCPU * 1_000))
}
