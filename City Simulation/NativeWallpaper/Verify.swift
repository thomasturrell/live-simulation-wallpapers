import AppKit
import CityArt
import CityEngine
import QuartzCore

@main
@MainActor
enum VerifyWallpaper {
    static func main() async {
        do {
            try await verify()
        } catch {
            fputs("Wallpaper probe: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func verify() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let localOnly = arguments.first == "--local"
        let files = localOnly ? Array(arguments.dropFirst()) : arguments
        guard files.count == 2 else {
            print("Usage: verify-wallpaper [--local] THUMBNAIL.png CHECKPOINT-DIRECTORY")
            exit(2)
        }
        guard LifeLoadWallpaperABI() else { throw ProbeError("WallpaperExtensionKit or its wrappers are unavailable.") }
        let thumbnail = URL(fileURLWithPath: files[0])
        let storage = URL(fileURLWithPath: files[1], isDirectory: true)
        let requested = try creationRequest()
        precondition(requested.preview && requested.size == CGSize(width: 640, height: 360) && requested.scale == 2)
        guard let settings = buildSettingsViewModelsXPC(thumbnail: thumbnail) else {
            throw ProbeError("The wallpaper settings model could not be decoded.")
        }
        for surface in ["desktop", "screenSaver"] {
            let box = Mirror(reflecting: settings)
            guard let groups = box.descendant("box", "rawValue", surface, "some", "groups") as? [Any],
                  let group = groups.first, let items = Mirror(reflecting: group).descendant("items") as? [Any],
                  let item = items.first,
                  Mirror(reflecting: item).descendant("id", "id") as? String == wallpaperChoice.id,
                  Mirror(reflecting: item).descendant("choice", "id", "descriptor", "provider", "rawValue") as? String
                      == wallpaperChoice.bundleID else {
                throw ProbeError("The decoded \(surface) model is missing the City Simulation choice.")
            }
        }
        print("City Simulation decoded in the real WallpaperAgent desktop and screen saver settings models.")

        var request = requested
        request.mode = "locked"
        request.preview = false
        let left = RemoteView(size: CGSize(width: 640, height: 360), request: request)
        let right = RemoteView(size: CGSize(width: 420, height: 760), request: request)
        if !localOnly {
            guard left.makeContext(display: nil) != nil, right.makeContext(display: nil) != nil else {
                throw ProbeError("Core Animation did not create a remote context. Run from a graphical macOS login session with WindowServer access.")
            }
            let previewID = UUID()
            _ = try WallpaperDriver.shared.acquire(previewID, requested)
            _ = try WallpaperDriver.shared.snapshot(previewID)
            WallpaperDriver.shared.invalidate(previewID)
        }
        let first = DisplayPlayback(checkpointKey: "landscape", storage: storage)
        let second = DisplayPlayback(checkpointKey: "portrait", storage: storage)
        let previous = first.city.tick
        precondition(first.city.map != second.city.map)
        first.views[UUID()] = left
        second.views[UUID()] = right
        first.refresh(hint: nil)
        second.refresh(hint: nil)
        try await Task.sleep(for: .seconds(0.7))
        precondition(first.city.tick > previous && second.city.tick > 0)
        try verifyImage(left, width: 640, height: 360)
        try verifyImage(right, width: 420, height: 760)

        var suspended = Presentation(nil)
        suspended.activity = "suspended"
        _ = right.apply(suspended)
        second.refresh(hint: nil)
        let paused = second.city
        let beforeUnlock = first.city.tick
        first.refresh(hint: false)
        try await Task.sleep(for: .seconds(3.4))
        let settled = first.city
        precondition(settled.tick > beforeUnlock && settled.tick - beforeUnlock <= 29)
        precondition(!first.hasTimer && !second.hasTimer && second.city == paused)
        try await Task.sleep(for: .seconds(0.4))
        precondition(first.city == settled)
        guard left.snapshot(settled) != nil, right.snapshot(paused) != nil else { throw BridgeError.noSurface }
        let restored = DisplayPlayback(checkpointKey: "landscape", storage: storage)
        precondition(restored.city == settled)
        restored.views[UUID()] = left
        restored.refresh(hint: true)
        try await Task.sleep(for: .seconds(0.7))
        precondition(restored.city.tick > settled.tick)
        restored.views.removeAll()
        restored.refresh(hint: false)
        precondition(!restored.hasTimer)
        let layers = localOnly ? "Local layers" : "Remote layers"
        print("\(layers) and IOSurface snapshots, suspended display, settling, zero idle timers and checkpoint resume passed.")
    }

    private static func creationRequest() throws -> Presentation {
        guard let cls = NSClassFromString("WallpaperCreationRequestXPC") as? any NSSecureCoding.Type,
              let space = CGColorSpace(name: CGColorSpace.sRGB)?.copyPropertyList() else {
            throw BridgeError.incompatible
        }
        let colorSpace = try PropertyListSerialization.data(fromPropertyList: space, format: .binary, options: 0)
        let request: [String: Any] = [
            "configuration": Data(), "isPreview": true, "debugBackgrounds": false,
            "destination": ["size": [640.0, 360.0], "scaleFactor": 2, "colorSpace": colorSpace],
            "presentationMode": ["idle": [:]], "activityState": ["active": [:]], "systemAppearance": ["dark": [:]]
        ]
        let archive = NSKeyedArchiver(requiringSecureCoding: true)
        archive.encode([], forKey: "files")
        archive.encode(nil, forKey: "cacheDirectory")
        archive.encode(request, forKey: "codable")
        let decoder = try NSKeyedUnarchiver(forReadingFrom: archive.encodedData)
        defer { decoder.finishDecoding() }
        decoder.requiresSecureCoding = true
        decoder.decodingFailurePolicy = .setErrorAndReturn
        guard let decoded = cls.init(coder: decoder) else { throw BridgeError.incompatible }
        return Presentation(decoded)
    }

    private static func verifyImage(_ view: RemoteView, width: Int, height: Int) throws {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw BridgeError.noSurface
        }
        view.root.render(in: context)
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        for (x, y) in [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)] {
            precondition(bytes[y * context.bytesPerRow + x * 4 + 3] == 255, "Uncovered corner at \(x),\(y)")
        }
    }
}


private struct ProbeError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
