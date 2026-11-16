import AppKit
import CoreGraphics
import LifeArt
import QuartzCore

@main
@MainActor
enum VerifyWallpaper {
    static func main() async throws {
        let thumbnail = URL(fileURLWithPath: CommandLine.arguments[1])
        let state = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        guard LifeLoadWallpaperABI() else { throw BridgeError.incompatible }
        try verifyPickers(thumbnail: thumbnail)
        try verifyAppearance()
        let green = try creationRequest(colourID: LifeColour.green.id, appearanceID: "light")
        precondition(green.colour == .green && green.appearance == .light)
        precondition(green.size == CGSize(width: 400, height: 240))
        let legacy = try creationRequest(colourID: nil)
        precondition(legacy.colour == nil)
        print("The real WallpaperTypes model and creation requests decoded both pickers and their selections.")

        var locked = green
        locked.mode = "locked"
        locked.scale = 2
        locked.preview = false
        let landscape = CGSize(width: 780, height: 440)
        let portrait = CGSize(width: 442, height: 780)
        let left = RemoteView(size: landscape, request: locked)
        let right = RemoteView(size: portrait, request: legacy)
        precondition(left.colour == .green && right.colour == .original)
        _ = right.apply(locked)

        verifyFullFrame(left, size: landscape, scale: 2)
        verifyFullFrame(right, size: portrait, scale: 1)
        verifyFullFrame(left, size: portrait, scale: 1)
        verifyFullFrame(left, size: landscape, scale: 2)
        print("All four corners covered at 1× and 2×, including after a resize.")

        guard left.makeContext(display: nil) != nil, right.makeContext(display: nil) != nil else {
            throw BridgeError.noSurface
        }

        try await verifyPreviewPlayback()

        let first = DisplayPlayback(logicalSize: landscape, checkpointKey: "landscape", storage: state)
        let second = DisplayPlayback(logicalSize: portrait, checkpointKey: "portrait", storage: state)
        first.views[UUID()] = left
        second.views[UUID()] = right
        first.refresh(hint: nil)
        second.refresh(hint: nil)
        try await Task.sleep(for: .seconds(1.3))
        precondition(first.phase > 0 && second.phase > 0)
        let before = first.phase
        first.refresh(hint: false)
        second.refresh(hint: false)
        try await Task.sleep(for: .seconds(3.8))
        let frozen = first.phase
        precondition(frozen == before + 3)
        try await Task.sleep(for: .seconds(1.2))
        precondition(first.phase == frozen && second.phase == frozen)
        precondition(left.snapshot(first.scene, phase: frozen) != nil)
        precondition(right.snapshot(second.scene, phase: frozen) != nil)
        let recreated = DisplayPlayback(logicalSize: landscape, checkpointKey: "landscape", storage: state)
        precondition(recreated.phase == frozen)
        let originalState = try PropertyListEncoder().encode(first.scene.checkpoint)
        let restoredState = try PropertyListEncoder().encode(recreated.scene.checkpoint)
        precondition(originalState == restoredState)
        recreated.views[UUID()] = left
        recreated.refresh(hint: true)
        try await Task.sleep(for: .seconds(1.3))
        precondition(recreated.phase == frozen + 1)
        recreated.views.removeAll()
        recreated.refresh(hint: false)
        print("Two remote layers, two IOSurface snapshots, slowdown, stopped timer and checkpoint resume passed.")
    }

    private static func verifyPickers(thumbnail: URL) throws {
        guard let settings = buildSettingsViewModelsXPC(thumbnail: thumbnail) else {
            throw BridgeError.incompatible
        }
        let mirror = Mirror(reflecting: settings)
        let expected = [
            (id: lifeAppearanceOptionID, label: "Appearance", defaultID: "automatic",
             ids: ["automatic", "light", "dark"], names: ["Automatic", "Light", "Dark"]),
            (id: lifeColourOptionID, label: "Colour", defaultID: LifeColour.original.id,
             ids: LifeColour.allCases.map(\.id), names: LifeColour.allCases.map(\.title))
        ]
        for surface in ["desktop", "screenSaver"] {
            guard let group = (mirror.descendant("box", "rawValue", surface, "some", "groups") as? [Any])?.first,
                  let item = (Mirror(reflecting: group).descendant("items") as? [Any])?.first,
                  let options = Mirror(reflecting: item).descendant("choice", "options") as? [Any],
                  options.count == expected.count else {
                throw BridgeError.incompatible
            }
            for (option, expected) in zip(options, expected) {
                let picker = Mirror(reflecting: option)
                guard picker.descendant("picker", "id") as? String == expected.id,
                      picker.descendant("picker", "localizedLabel") as? String == expected.label,
                      picker.descendant("picker", "defaultValueID") as? String == expected.defaultID,
                      let items = picker.descendant("picker", "items") as? [Any],
                      items.compactMap({ Mirror(reflecting: $0).descendant("item", "id") as? String }) == expected.ids,
                      items.compactMap({ Mirror(reflecting: $0).descendant("item", "localizedName") as? String })
                        == expected.names else {
                    throw BridgeError.incompatible
                }
            }
        }
    }

    private static func verifyAppearance() throws {
        let size = CGSize(width: 400, height: 240)
        let scene = LifeScene(viewport: size, settings: LifeSettings())
        let lightSystem = try creationRequest(systemDark: false)
        let darkSystem = try creationRequest()
        precondition(lightSystem.systemDark == false && darkSystem.systemDark == true)

        for (option, mode, darkInLight, darkInDark) in [
            ("light", LifeAppearance.light, false, false),
            ("dark", .dark, true, true),
            ("automatic", .system, false, true),
            (nil, nil, false, true),
            ("unknown", nil, false, true)
        ] {
            let request = try creationRequest(appearanceID: option)
            precondition(request.appearance == mode)
            let view = RemoteView(size: size, request: request)
            precondition(view.isDark == darkInDark)
            precondition(view.apply(lightSystem) == (darkInDark != darkInLight))
            precondition(view.isDark == darkInLight)
            view.draw(scene, phase: 0, animate: false, duration: 0)
            guard let backdrop = view.root.sublayers?.first?.sublayers?.first as? CAGradientLayer,
                  let colors = backdrop.colors as? [CGColor],
                  let red = colors.first?.components?.first else { throw BridgeError.noSurface }
            precondition(darkInLight ? red < 0.2 : red > 0.8)
            _ = view.apply(darkSystem)
            precondition(view.isDark == darkInDark)
        }
        print("Automatic follows system appearance and fixed modes retain their chosen palette.")
    }

    private static func creationRequest(colourID: String? = nil, appearanceID: String? = nil, systemDark: Bool = true,
                                        preview: Bool = false,
                                        size: CGSize = CGSize(width: 400, height: 240)) throws -> Presentation {
        guard let cls = NSClassFromString("WallpaperCreationRequestXPC") as? any NSSecureCoding.Type,
              let space = CGColorSpace(name: CGColorSpace.sRGB)?.copyPropertyList() else {
            throw BridgeError.incompatible
        }
        let colorSpace = try PropertyListSerialization.data(fromPropertyList: space, format: .binary, options: 0)
        var request: [String: Any] = [
            "configuration": Data(), "isPreview": preview, "debugBackgrounds": false,
            "destination": ["size": [size.width, size.height], "scaleFactor": 1, "colorSpace": colorSpace],
            "presentationMode": ["idle": [:]], "activityState": ["active": [:]],
            "systemAppearance": [systemDark ? "dark" : "light": [:]]
        ]
        let options = [lifeColourOptionID: colourID, lifeAppearanceOptionID: appearanceID]
            .compactMapValues { $0 }
            .mapValues { ["picker": ["_0": ["id": $0]]] }
        if !options.isEmpty {
            request["optionValues"] = ["values": options]
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

    private static func verifyPreviewPlayback() async throws {
        let size = CGSize(width: 1512, height: 982)
        var request = try creationRequest(colourID: LifeColour.green.id, preview: true, size: size)
        precondition(request.preview && request.size == size)
        let view = RemoteView(size: size, request: request)
        let playback = DisplayPlayback(logicalSize: size, preview: request.preview, checkpointKey: nil)
        let viewport = playback.scene.viewport
        precondition(view.colour == .green && viewport.width <= size.width / 5)
        precondition(abs(viewport.width / viewport.height - size.width / size.height) < 0.001)
        playback.views[UUID()] = view
        playback.draw(animate: false)
        precondition(view.root.frame.size == size)
        func thumbnailPixels() -> CFData? {
            let width = 160
            let height = Int((Double(width) * size.height / size.width).rounded())
            guard let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                         bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            bitmap.scaleBy(x: Double(width) / size.width, y: Double(height) / size.height)
            view.root.render(in: bitmap)
            return bitmap.makeImage()?.dataProvider?.data
        }
        let firstFrame = thumbnailPixels()

        playback.refresh(hint: false)
        try await Task.sleep(for: .seconds(1.3))
        let nextFrame = thumbnailPixels()
        precondition(firstFrame != nil && nextFrame != nil && firstFrame != nextFrame)

        request.activity = "suspended"
        _ = view.apply(request)
        playback.refresh(hint: true)
        let suspended = playback.phase
        try await Task.sleep(for: .seconds(1.3))
        precondition(playback.phase == suspended)

        request.activity = "active"
        _ = view.apply(request)
        playback.refresh(hint: false)
        try await Task.sleep(for: .seconds(1.3))
        precondition(playback.phase > suspended)

        playback.views.removeAll()
        playback.refresh(hint: false)
        let released = playback.phase
        try await Task.sleep(for: .seconds(1.3))
        precondition(playback.phase == released)
        print("Preview uses a coarser grid and the chosen colour, animates, pauses when suspended and stops on release.")
    }

    private static func verifyFullFrame(_ view: RemoteView, size: CGSize, scale: CGFloat) {
        var request = Presentation(nil)
        request.size = size
        request.scale = scale
        _ = view.apply(request)
        let scene = LifeScene(viewport: size, settings: LifeSettings())
        view.draw(scene, phase: 0, animate: false, duration: 0)
        let frame = CGRect(origin: .zero, size: size)
        precondition(view.root.frame == frame && view.root.contentsScale == scale)

        let parent = CALayer()
        parent.frame = frame
        parent.masksToBounds = true
        parent.addSublayer(view.root)
        defer { view.root.removeFromSuperlayer() }

        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                               bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        bitmap.scaleBy(x: scale, y: scale)
        parent.render(in: bitmap)
        let bytes = bitmap.data!.assumingMemoryBound(to: UInt8.self)
        for (x, y) in [(1, 1), (width - 2, 1), (1, height - 2), (width - 2, height - 2)] {
            precondition(bytes[y * bitmap.bytesPerRow + x * 4 + 3] == 255,
                         "Wallpaper did not cover pixel (\(x), \(y)) at \(scale)×")
        }
    }
}
