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
        let playback = DisplayPlayback(displayUUID: display, storage: base)
        let view = RemoteView(size: request.size!, request: request)
        if !local {
            let driver = WallpaperDriver.shared
            _ = try driver.acquire(viewID, request)
            _ = try driver.snapshot(viewID)
            driver.invalidate(viewID)
        }
        precondition(playback.select(request.optionIDs["explore"]))
        playback.views[viewID] = view
        playback.refresh(hint: nil)
        try await Task.sleep(for: .milliseconds(600))
        precondition(playback.hasTimer && playback.exploration.age > 0)
        let beat = playback.exploration.beat
        playback.refresh(hint: false)
        try await Task.sleep(for: .seconds(Playback.settleDuration + 0.3))
        let settled = try playback.exploration.checkpoint()
        precondition(!playback.hasTimer && playback.exploration.beat == beat)
        try await Task.sleep(for: .milliseconds(250))
        let still = try playback.exploration.checkpoint()
        precondition(still == settled)
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
