import AppKit
import CityArt
import CityEngine
import IOSurface
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
                      == wallpaperChoice.bundleID,
                  let options = Mirror(reflecting: item).descendant("choice", "options") as? [Any],
                  options.count == 2,
                  matchesPicker(options[0], id: "environment", defaultID: EnvironmentMode.simulationWorld.rawValue,
                                items: EnvironmentMode.allCases.map(\.rawValue)),
                  matchesPicker(options[1], id: "skin", defaultID: CitySkin.original.rawValue,
                                items: CitySkin.allCases.map(\.rawValue)) else {
                throw ProbeError("The decoded \(surface) model is missing the City Simulation choice.")
            }
        }
        print("City Simulation decoded in the real WallpaperAgent desktop and screen saver settings models.")
        try await verifyNativeDownloadStatus()
        try verifySuspendedFrames(requested)

        let unchanged = City()
        let defaults = RemoteView(size: CGSize(width: 640, height: 360), request: requested)
        precondition(defaults.environmentMode == .simulationWorld && defaults.skin == .original)
        for mode in EnvironmentMode.allCases {
            let request = try creationRequest(options: ["environment": mode.rawValue])
            let view = RemoteView(size: CGSize(width: 640, height: 360), request: request)
            precondition(view.environmentMode == mode)
            view.draw(unchanged)
            let frame = view.environment(for: unchanged)
            if mode.isSimulation {
                precondition(frame == Environment.frame(city: unchanged))
            } else {
                precondition(frame.darkness == 1 && frame.weather == EnvironmentalWeather())
                let offset = mode == .realWorldSouthern ? 6.0 : 0
                precondition(abs(frame.month - Environment.wrap(Environment.realMonth(at: Date()) + offset, length: 12)) < 0.001)
            }
            guard view.snapshot(unchanged) != nil else { throw BridgeError.noSurface }
            var change = Presentation(nil)
            change.systemDark = false
            _ = view.apply(change)
            precondition(view.environmentMode == mode)
            precondition(view.environment(for: unchanged).darkness == (mode.isSimulation ? unchanged.darkness : 0))
            change.optionIDs = ["environment": EnvironmentMode.simulationWorld.rawValue]
            _ = view.apply(change)
            precondition(view.environment(for: unchanged) == Environment.frame(city: unchanged))
        }
        precondition(unchanged == City())
        print("One Environment picker with three choices, neutral Real World weather, appearance updates and snapshots passed.")

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
            try verifySnapshotRefreshes(requested)
        }
        let landscapeUUID = UUID(uuidString: "70F239C2-D6FC-4B58-BB3F-02FAA45FE309")!
        let portraitUUID = UUID(uuidString: "70F239C2-D6FC-4B58-BB3F-02FAA45FE302")!
        let first = DisplayPlayback(displayUUID: landscapeUUID, storage: storage)
        let second = DisplayPlayback(displayUUID: portraitUUID, storage: storage)
        let previous = first.city.tick
        precondition(CityMap.plots.contains { first.city.map[$0].ground != second.city.map[$0].ground })
        precondition(DisplayPlayback(displayUUID: nil, storage: storage).city == City())
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
        try await Task.sleep(for: .seconds(Playback.settleDuration + 0.7))
        let settled = first.city
        precondition(settled.tick > beforeUnlock && settled.tick - beforeUnlock <= 41)
        precondition(!first.hasTimer && !second.hasTimer && second.city == paused)
        try await Task.sleep(for: .seconds(0.4))
        precondition(first.city == settled)
        guard left.snapshot(settled) != nil, right.snapshot(paused) != nil else { throw BridgeError.noSurface }
        let restored = DisplayPlayback(displayUUID: landscapeUUID, storage: storage)
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

    private static func matchesPicker(_ option: Any, id: String, defaultID: String, items: [String]) -> Bool {
        let mirror = Mirror(reflecting: option)
        guard mirror.descendant("picker", "id") as? String == id,
              mirror.descendant("picker", "defaultValueID") as? String == defaultID,
              let choices = mirror.descendant("picker", "items") as? [Any] else { return false }
        return choices.compactMap { Mirror(reflecting: $0).descendant("item", "id") as? String } == items
    }

    private static func verifyNativeDownloadStatus() async throws {
        guard let native = NSProtocolFromString("WallpaperExtensionKit.WallpaperExtensionXPCProtocol"),
              let models = NSClassFromString("WallpaperSettingsViewModelsXPC") else {
            throw BridgeError.incompatible
        }
        let listener = NSXPCListener.anonymous()
        let delegate = ProbeListener()
        listener.delegate = delegate
        listener.resume()
        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        // Use Apple's interface, not a second copy of our declarations: matching
        // mistakes at both ends would otherwise hide an incompatible reply type.
        connection.remoteObjectInterface = NSXPCInterface(with: native)
        let exported = NSXPCInterface(with: WallpaperExtensionProxyXPCProtocol.self)
        let classes = NSSet(array: [models, NSString.self, NSNumber.self, NSData.self,
                                    NSArray.self, NSDictionary.self, NSURL.self])
        exported.setClasses(Set(classes.compactMap { $0 as? AnyHashable }),
                            for: #selector(ProbeHost.updateSettingsViewModels(_:reply:)),
                            argumentIndex: 0, ofReply: false)
        connection.exportedInterface = exported
        connection.exportedObject = ProbeHost()
        connection.resume()
        let timeout = DispatchWorkItem { connection.invalidate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeout)
        defer {
            timeout.cancel()
            connection.invalidate()
            listener.invalidate()
            withExtendedLifetime(delegate) {}
        }
        try await withCheckedThrowingContinuation { (reply: CheckedContinuation<Void, Error>) in
            let proxy = connection.remoteObjectProxyWithErrorHandler { reply.resume(throwing: $0) } as AnyObject
            proxy.isChoiceDownloaded(with: nil) { status, error in
                if let error { reply.resume(throwing: error) }
                else if status?.boolValue == true { reply.resume() }
                else { reply.resume(throwing: ProbeError("The native download-status reply is missing or false.")) }
            }
        }
        print("Apple's native download-status interface received an NSNumber reply without disconnecting.")
    }

    private static func verifySnapshotRefreshes(_ requested: Presentation) throws {
        let driver = WallpaperDriver.shared
        let id = UUID()
        var request = requested
        request.preview = false
        request.mode = "default"
        request.hasPlacement = true
        request.optionIDs = ["environment": EnvironmentMode.realWorldNorthern.rawValue]
        request.systemDark = false
        _ = try driver.acquire(id, request)
        var invalidations = 0
        driver.invalidateSnapshots = { invalidations += 1 }
        defer { driver.invalidateSnapshots = nil; driver.invalidate(id) }
        let noChange = Presentation(nil)
        for _ in 0..<100 { driver.update(id, noChange) }
        precondition(invalidations == 0, "No-op host updates must not invalidate snapshots")
        var activity = Presentation(nil)
        activity.activity = "active"
        driver.update(id, activity)
        precondition(invalidations == 0)
        var night = Presentation(nil)
        night.systemDark = true
        driver.update(id, night)
        precondition(invalidations == 1, "A real frozen-frame change must invalidate once")
        for _ in 0..<100 { driver.update(id, night); driver.update(id, noChange) }
        precondition(invalidations == 1, "Host responses must not start a snapshot refresh loop")
        NotificationCenter.default.post(name: .NSSystemClockDidChange, object: nil)
        precondition(invalidations == 1, "An unchanged environment notification must not invalidate again")
        _ = try driver.snapshot(id)

        var suspended = Presentation(nil)
        suspended.activity = "suspended"
        driver.update(id, suspended)
        var southern = Presentation(nil)
        southern.optionIDs = ["environment": EnvironmentMode.realWorldSouthern.rawValue]
        driver.update(id, southern)
        precondition(invalidations == 2, "A static suspended wallpaper must refresh after an environment change")
        for _ in 0..<100 { driver.update(id, southern) }
        precondition(invalidations == 2, "Suspended settings updates must not cause a refresh loop")

        var skinChange = Presentation(nil)
        skinChange.optionIDs = ["skin": CitySkin.contemporary.rawValue]
        driver.update(id, skinChange)
        precondition(invalidations == 3, "Changing skin on the suspended desktop must invalidate its snapshot")
        driver.update(id, skinChange)
        driver.update(id, noChange)
        precondition(invalidations == 3)
        _ = try driver.snapshot(id)

        let previewID = UUID()
        _ = try driver.acquire(previewID, requested)
        driver.update(previewID, night)
        driver.update(previewID, skinChange)
        driver.invalidate(previewID)
        precondition(invalidations == 3, "Disposable Settings previews must not invalidate desktop snapshots")
        print("No-op updates, activity updates, duplicate appearance updates and Settings previews caused no snapshot refresh loops.")
    }

    private static func verifySuspendedFrames(_ requested: Presentation) throws {
        let city = City()
        for mode in EnvironmentMode.allCases {
            var request = requested
            request.preview = false
            request.mode = "default"
            request.hasPlacement = true
            request.activity = "suspended"
            request.systemDark = false
            request.optionIDs = ["environment": mode.rawValue]
            let view = RemoteView(size: CGSize(width: 640, height: 360), request: request)
            let playback = DisplayPlayback(displayUUID: nil)
            playback.views[UUID()] = view
            playback.refresh(hint: false)
            view.draw(city)
            precondition(!view.needsArtworkRedraw(city))
            let original = try snapshotBytes(view, city)
            let originalLayer = try verifyImage(view, width: 640, height: 360)
            var skinChange = Presentation(nil)
            skinChange.optionIDs = try creationRequest(options: ["skin": CitySkin.contemporary.rawValue]).optionIDs
            _ = view.apply(skinChange)
            precondition(view.skin == .contemporary && view.needsArtworkRedraw(city))
            view.draw(city)
            precondition(!view.needsArtworkRedraw(city))
            let contemporary = try snapshotBytes(view, city)
            let contemporaryLayer = try verifyImage(view, width: 640, height: 360)
            precondition(original != contemporary && originalLayer != contemporaryLayer)
            _ = view.apply(Presentation(nil))
            precondition(view.skin == .contemporary && !view.needsArtworkRedraw(city))
            skinChange.optionIDs = ["skin": CitySkin.original.rawValue]
            _ = view.apply(skinChange)
            view.draw(city)
            let restored = try snapshotBytes(view, city)
            precondition(restored == original)
            var night = Presentation(nil)
            night.systemDark = true
            _ = view.apply(night)
            view.draw(city)
            try verifyImage(view, width: 640, height: 360)
            guard view.snapshot(city) != nil else { throw BridgeError.noSurface }
            precondition(view.suspended && !playback.hasTimer && playback.city == city)
        }
        print("Suspended layers and snapshots switch skins at the same tick and redraw day/night frames without starting playback.")
    }

    private static func creationRequest(options: [String: String] = [:]) throws -> Presentation {
        guard let cls = NSClassFromString("WallpaperCreationRequestXPC") as? any NSSecureCoding.Type,
              let space = CGColorSpace(name: CGColorSpace.sRGB)?.copyPropertyList() else {
            throw BridgeError.incompatible
        }
        let colorSpace = try PropertyListSerialization.data(fromPropertyList: space, format: .binary, options: 0)
        var request: [String: Any] = [
            "configuration": Data(), "isPreview": true, "debugBackgrounds": false,
            "destination": ["size": [640.0, 360.0], "scaleFactor": 2, "colorSpace": colorSpace],
            "presentationMode": ["idle": [:]], "activityState": ["active": [:]], "systemAppearance": ["dark": [:]]
        ]
        if !options.isEmpty {
            request["optionValues"] = ["values": options.mapValues { ["picker": ["_0": ["id": $0]]] }]
        }
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

    private static func snapshotBytes(_ view: RemoteView, _ city: City) throws -> Data {
        guard let surface = view.snapshot(city), LifeWrapWallpaperSnapshot(surface) != nil,
              surface.lock(options: .readOnly, seed: nil) == 0 else { throw BridgeError.noSurface }
        defer { _ = surface.unlock(options: .readOnly, seed: nil) }
        return Data(bytes: surface.baseAddress, count: surface.bytesPerRow * surface.height)
    }

    @discardableResult
    private static func verifyImage(_ view: RemoteView, width: Int, height: Int) throws -> Data {
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
        var colors: Set<UInt32> = []
        for y in stride(from: 0, to: height, by: max(1, height / 32)) {
            for x in stride(from: 0, to: width, by: max(1, width / 32)) {
                let offset = y * context.bytesPerRow + x * 4
                colors.insert(UInt32(bytes[offset]) << 16 | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]))
            }
        }
        precondition(colors.count > 16, "The wallpaper frame must show city detail, not a blank surface")
        return Data(bytes: bytes, count: context.bytesPerRow * height)
    }
}

private final class ProbeListener: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        WallpaperExtensionConfig().accept(connection: connection)
    }
}

private final class ProbeHost: NSObject, WallpaperExtensionProxyXPCProtocol {
    func ping(withId _: Any?) {}
    func updateSettingsViewModels(_: Any?, reply: @escaping (Error?) -> Void) { reply(nil) }
    func requestReadOnlyAccess(to _: Any?, reply: @escaping (Any?) -> Void) { reply(nil) }
    func invalidateSnapshots(reply: @escaping (Error?) -> Void) { reply(nil) }
}


private struct ProbeError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
