import AppKit
import DesignArt
import DesignEngine

/// Run with a temporary directory so the probe never touches installed display histories.
@main
@MainActor
enum VerifyWallpaper {
    static func main() async {
        do { try await verify() } catch {
            fputs("Wallpaper probe failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func verify() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let local = arguments.first == "--local"
        let files = local ? Array(arguments.dropFirst()) : arguments
        guard files.count == 2 else {
            fputs("Usage: verify-wallpaper [--local] THUMBNAIL.png TEMP-DIRECTORY\n", stderr)
            exit(2)
        }
        guard LifeLoadWallpaperABI(),
              let settings = buildSettingsViewModelsXPC(thumbnail: URL(fileURLWithPath: files[0])) else { throw BridgeError.incompatible }
        for surface in ["desktop", "screenSaver"] {
            guard let groups = Mirror(reflecting: settings).descendant("box", "rawValue", surface, "some", "groups") as? [Any],
                  let group = groups.first, let items = Mirror(reflecting: group).descendant("items") as? [Any],
                  let item = items.first, Mirror(reflecting: item).descendant("id", "id") as? String == wallpaperChoice.id,
                  let options = Mirror(reflecting: item).descendant("choice", "options") as? [Any],
                  let label = options.first(where: { Mirror(reflecting: $0).descendant("picker", "id") as? String == "systemLabel" }),
                  Mirror(reflecting: label).descendant("picker", "defaultValueID") as? String == "hide",
                  let explore = options.first, let choices = Mirror(reflecting: explore).descendant("picker", "items") as? [Any],
                  choices.count == 1 + Subject.allCases.count + Catalogue.bundled.graphs.count,
                  options.count == wallpaperChoice.options.count else { throw BridgeError.incompatible }
        }

        let base = URL(fileURLWithPath: files[1], isDirectory: true)
        let display = UUID()
        let viewID = UUID()
        var request = Presentation(nil)
        request.mode = "locked"
        request.size = CGSize(width: 800, height: 500)
        request.optionIDs = ["explore": "domestic-solar-power", "colour": "purple"]
        var playback = DisplayPlayback(displayUUID: display, storage: base)
        var view = RemoteView(size: request.size!, request: request)
        if !local {
            let driver = WallpaperDriver.shared
            _ = try driver.acquire(viewID, request)
            _ = try driver.snapshot(viewID)
            driver.invalidate(viewID)
        }
        precondition(playback.select(request.optionIDs["explore"]))
        playback.views[viewID] = view
        playback.refresh(hint: nil)
        let quietTick = Int(Double(playback.exploration.chapter.beatTicks) * 0.37)
        let deadline = ContinuousClock.now + .seconds(6)
        while playback.exploration.tick < quietTick && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        let locked = playback.exploration
        precondition(playback.hasTimer && locked.elevation == 1 && locked.progress < Chapter.pulseStart)
        let world = view.root.sublayers!.last!.sublayers!.first!.sublayers!.first!
        let raised = world.position
        var offers = 0
        playback.invalidateSnapshots = { offers += 1 }
        playback.refresh(hint: false)
        try await Task.sleep(for: .milliseconds(750))
        let middle = playback.exploration
        precondition(playback.hasTimer && middle.age == locked.age && middle.elevation < 1 && middle.elevation > 0)
        let halfway = world.position
        precondition(halfway != raised, "The remote layer must visibly settle even between diagram actions")
        precondition(offers == 1, "A host that does not sample snapshots needs only one intermediate offer")
        guard view.snapshot(middle.restingFrame) != nil else { throw BridgeError.noSurface }
        precondition(world.position == halfway, "A desktop snapshot must not jump the live layer")

        playback.views.removeAll()
        playback.refresh(hint: false)
        precondition(!playback.hasTimer)
        playback = DisplayPlayback(displayUUID: display, storage: base)
        request.mode = "default"
        view = RemoteView(size: request.size!, request: request)
        playback.views[viewID] = view
        playback.refresh(hint: nil)
        precondition(playback.hasTimer && playback.exploration.elevation == middle.elevation)
        var snapshotElevations: [Double] = []
        playback.invalidateSnapshots = {
            let frame = playback.desktopSnapshotFrame()
            snapshotElevations.append(frame.elevation)
            precondition(view.snapshot(frame) != nil)
        }
        try await Task.sleep(for: .seconds(Playback.settleDuration + 0.3))
        let settled = try playback.exploration.checkpoint()
        precondition(!playback.hasTimer && playback.exploration.age == locked.age && playback.exploration.elevation == 0)
        let samples = snapshotElevations
        precondition((2...11).contains(samples.count) && samples.first! > 0 && samples.last == 0)
        precondition(samples == samples.sorted(by: >))
        try await Task.sleep(for: .milliseconds(250))
        let still = try playback.exploration.checkpoint()
        precondition(still == settled && snapshotElevations == samples)
        playback.invalidateSnapshots = nil
        let restored = DisplayPlayback(displayUUID: display, storage: base)
        let saved = try restored.exploration.checkpoint()
        precondition(saved == settled)
        guard view.snapshot(restored.exploration) != nil else { throw BridgeError.noSurface }

        var suspended = Presentation(nil)
        suspended.activity = "suspended"
        _ = view.apply(suspended)
        restored.views[viewID] = view
        restored.refresh(hint: true)
        precondition(!restored.hasTimer)
        var active = Presentation(nil)
        active.activity = "active"
        _ = view.apply(active)
        restored.refresh(hint: true)
        try await Task.sleep(for: .milliseconds(250))
        precondition(restored.exploration.age > playback.exploration.age)
        restored.views.removeAll()
        restored.refresh(hint: nil)
        precondition(!restored.hasTimer)
        print("Picker models, IOSurface, lock playback, desktop settling, suspension and per-display restore passed.")
    }
}
