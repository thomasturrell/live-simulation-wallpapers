import AppKit
import IOSurface
import LifeArt
import QuartzCore

@MainActor
final class WallpaperDriver {
    static let shared = WallpaperDriver()
    private var displays: [String: DisplayPlayback] = [:]
    private var owners: [UUID: DisplayPlayback] = [:]
    private var saverHint: Bool?
    private var observers: [NSObjectProtocol] = []
    private var colourObserver: NSObjectProtocol?
    private let brandingStore = LifeBrandingStore.shared()
    private var branding = LifeBranding()
    private var brandingArtwork = LifeBrandingArtwork()
    var invalidateSnapshots: (() -> Void)?

    private init() {
        let names = [
            "com.apple.screensaver.didstart": true,
            "com.apple.screensaver.didstop": false,
            "com.apple.screenIsUnlocked": false
        ]
        let notifications = DistributedNotificationCenter.default()
        observers = names.map { name, active in
            notifications.addObserver(
                forName: .init(name), object: nil, queue: .main
            ) { note in
                guard note.object as? String != "runFromPref" else { return }
                MainActor.assumeIsolated {
                    WallpaperDriver.shared.saverHint = active
                    WallpaperDriver.shared.refreshAll()
                }
            }
        }
        colourObserver = NotificationCenter.default.addObserver(
            forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccent() }
        }
        observers.append(notifications.addObserver(forName: LifeBranding.didChange, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.refreshBranding() }
        })
        refreshBranding()
    }

    func acquire(_ id: UUID, _ request: Presentation) throws -> Any {
        guard LifeLoadWallpaperABI(), let size = request.size else { throw BridgeError.incompatible }
        let surface = RemoteView(size: size, request: request)
        surface.brandingArtwork = brandingArtwork
        guard let wrapped = surface.makeContext(display: request.displayID) else { throw BridgeError.incompatible }
        // Make the successor first. A repeated acquire with the same ID may
        // still have a live scene and subscribers.
        let key = request.preview ? "preview-\(id)" : (request.displayKey ?? "session-\(id)")
        let playback = displays[key] ?? DisplayPlayback(
            logicalSize: size, preview: request.preview, checkpointKey: request.preview ? nil : request.displayKey
        )
        if let old = owners[id], old !== playback { invalidate(id) }
        if !surface.preview && surface.isSaver && owners[id] == nil { saverHint = nil }
        displays[key] = playback
        owners[id] = playback
        playback.views[id] = surface
        playback.onSettled = { [weak self] in self?.invalidateSnapshots?() }
        playback.draw(animate: false)
        update(id, request)
        CATransaction.flush()
        return wrapped
    }

    func update(_ id: UUID, _ request: Presentation) {
        guard let playback = owners[id], let surface = playback.views[id] else { return }
        let oldMode = surface.presentationMode
        if surface.apply(request) {
            surface.draw(playback.scene, phase: playback.phase, animate: false, duration: 0)
        }
        if !surface.preview, oldMode != surface.presentationMode, request.mode != nil {
            saverHint = nil
            refreshAll()
        } else {
            playback.refresh(hint: saverHint)
        }
    }

    func invalidate(_ id: UUID) {
        guard let playback = owners.removeValue(forKey: id) else { return }
        playback.views.removeValue(forKey: id)
        playback.refresh(hint: saverHint)
        if playback.views.isEmpty {
            displays = displays.filter { $0.value !== playback }
        }
    }

    func snapshot(_ id: UUID) throws -> Any {
        guard let owner = owners[id], let view = owner.views[id],
              let snapshot = view.snapshot(owner.scene, phase: owner.phase) else { throw BridgeError.noSurface }
        return snapshot
    }

    private func refreshAll() {
        for display in displays.values { display.refresh(hint: saverHint) }
    }

    private func refreshAccent() {
        var changed = false
        for display in displays.values {
            for view in display.views.values where view.colour == .accent {
                view.updatePalette(display.scene, phase: display.phase)
                changed = true
            }
        }
        if changed { invalidateSnapshots?() }
    }

    private func refreshBranding() {
        guard let updated = brandingStore?.load(), updated != branding else { return }
        branding = updated
        brandingArtwork = LifeBrandingArtwork(updated)
        for display in displays.values {
            for view in display.views.values {
                view.brandingArtwork = brandingArtwork
                view.updatePalette(display.scene, phase: display.phase)
            }
        }
        invalidateSnapshots?()
    }
}

enum BridgeError: LocalizedError {
    case incompatible, noSurface
    var errorDescription: String? {
        switch self {
        case .incompatible: return "The WallpaperAgent interface is incompatible with this build."
        case .noSurface: return "The requested wallpaper surface is unavailable."
        }
    }
}

@MainActor
final class DisplayPlayback {
    private struct Saved: Codable {
        let version: Int
        let scene: LifeScene.Checkpoint
        let phase: UInt16
    }

    static let cycle: UInt16 = 240
    static let settlingDelays = [0.42, 0.82, 1.42]

    var views: [UUID: RemoteView] = [:]
    var onSettled: (() -> Void)?
    private(set) var scene: LifeScene
    private(set) var phase: UInt16 = 0
    private let path: URL?
    private var timer: DispatchSourceTimer?
    private var running = false
    private var remaining: ArraySlice<Double> = []

    init(logicalSize: CGSize, preview: Bool = false, checkpointKey: String?, storage: URL? = nil) {
        var path: URL?
        if let checkpointKey,
           let base = storage ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let directory = base.appendingPathComponent("Game of Life/Wallpaper State", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                path = directory.appendingPathComponent(checkpointKey).appendingPathExtension("plist")
            } catch {
                wallpaperLog.error("Cannot create the checkpoint directory: \(error.localizedDescription)")
            }
        }
        self.path = path
        var settings = LifeSettings()
        settings.speed = 1.0
        if preview {
            // A small grid shows fewer colonies. Start with an active composition
            // and introduce new patterns more often to keep the preview moving.
            settings.seed = 0x2B7D_A8C3_63FE_64E8
            settings.injection = 4
        } else if let checkpointKey {
            // Unlike Swift's randomized Hasher, this displacement is stable between launches.
            for byte in checkpointKey.utf8 { settings.seed = (settings.seed ^ UInt64(byte)) &* 1_099_511_628_211 }
        }

        if let path, let data = try? Data(contentsOf: path), data.count <= 4_000_000,
           let saved = try? PropertyListDecoder().decode(Saved.self, from: data),
           saved.version == 1, saved.phase < Self.cycle,
           let restored = LifeScene(checkpoint: saved.scene, settings: settings) {
            scene = restored
            phase = saved.phase
        } else {
            // System Settings requests a full display surface and scales it down for the preview.
            // Limit the scene to about 30 cells along its longer edge so motion stays visible.
            let scale = preview ? min(1, 240 / max(logicalSize.width, logicalSize.height)) : 1
            let viewport = CGSize(width: max(16, logicalSize.width * scale),
                                  height: max(16, logicalSize.height * scale))
            scene = LifeScene(viewport: viewport, settings: settings)
        }
    }

    deinit { timer?.cancel() }

    func draw(animate: Bool, duration: TimeInterval = 0.33) {
        for view in views.values {
            view.draw(scene, phase: phase, animate: animate, duration: duration)
        }
    }

    func refresh(hint: Bool?) {
        let visible = views.values.filter { !$0.suspended }
        if visible.isEmpty {
            timer?.cancel()
            timer = nil
            running = false
            remaining = []
            return
        }

        // System Settings acquires its own preview world. Keep it playing
        // while visible, regardless of the desktop's saver notifications.
        let shouldRun = visible.contains { $0.preview } || (hint ?? visible.contains { $0.isSaver })
        guard shouldRun != running else { return }
        running = shouldRun
        timer?.cancel()
        timer = nil
        remaining = []
        if running {
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(60))
            timer.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.advance(elapsed: 1, duration: 0.33) }
            }
            self.timer = timer
            timer.activate()
        } else {
            remaining = Self.settlingDelays[...]
            settle()
        }
    }

    private func settle() {
        if let delay = remaining.popFirst() {
            schedule(after: delay) { playback in
                playback.advance(elapsed: 0, duration: min(0.65, delay * 0.7))
                playback.settle()
            }
        } else {
            schedule(after: 0.65) { $0.onSettled?() }
        }
    }

    private func schedule(after delay: TimeInterval, run: @escaping (DisplayPlayback) -> Void) {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + delay, leeway: .milliseconds(30))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.timer?.cancel()
                self.timer = nil
                run(self)
            }
        }
        self.timer = timer
        timer.activate()
    }

    private func advance(elapsed: TimeInterval, duration: TimeInterval) {
        scene.advance(by: elapsed)
        phase = (phase + 1) % Self.cycle
        draw(animate: true, duration: duration)
        guard let path else { return }
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(Saved(version: 1, scene: scene.checkpoint, phase: phase))
            try data.write(to: path, options: .atomic)
        } catch {
            wallpaperLog.error("Checkpoint write failed: \(error.localizedDescription)")
        }
    }
}

@MainActor
final class RemoteView {
    let root = CALayer()
    private let art = LifeLayers()
    private let logo = LifeBrandingLayer()
    var brandingArtwork: LifeBrandingArtwork {
        get { logo.artwork }
        set { logo.artwork = newValue }
    }
    private var context: AnyObject?
    private var size: CGSize
    private var scale: CGFloat
    private var dark: Bool
    let colour: LifeColour
    private var hasPlacement: Bool
    private(set) var presentationMode: String
    private(set) var suspended: Bool
    let preview: Bool

    var isSaver: Bool {
        presentationMode == "locked" || (presentationMode == "idle" && !hasPlacement)
    }

    init(size: CGSize, request: Presentation) {
        self.size = size
        scale = request.scale ?? 1
        dark = request.dark ?? true
        colour = request.colour ?? .original
        hasPlacement = request.hasPlacement
        presentationMode = request.mode ?? "default"
        suspended = request.activity == "suspended"
        preview = request.preview
        root.frame = CGRect(origin: .zero, size: size)
        root.masksToBounds = true
        root.contentsScale = scale
        art.root.anchorPoint = .zero
        root.addSublayer(art.root)
        root.addSublayer(logo.layer)
    }

    func makeContext(display: UInt32?) -> Any? {
        guard let context = LifeMakeWallpaperContext(root, scale, display.map { NSNumber(value: $0) }) else { return nil }
        self.context = context as AnyObject
        return LifeWrapWallpaperContext(context)
    }

    func apply(_ request: Presentation) -> Bool {
        let previousGeometry = (size, scale, dark, suspended)
        if let mode = request.mode { presentationMode = mode }
        if let activity = request.activity { suspended = activity == "suspended" }
        if let dark = request.dark { self.dark = dark }
        if let size = request.size { self.size = size }
        if let scale = request.scale { self.scale = scale }
        return previousGeometry != (size, scale, dark, suspended)
    }

    private func darkness(phase: UInt16) -> Double {
        guard colour == .original else { return dark ? 1 : 0 }
        let pulse = (1 - cos(2 * .pi * Double(phase) / Double(DisplayPlayback.cycle))) / 2
        return dark ? 1 - 0.055 * pulse : 0.045 * pulse
    }

    func updatePalette(_ scene: LifeScene, phase: UInt16) {
        let palette = scene.palette(darkness: darkness(phase: phase), colour: colour)
        art.setPalette(palette)
        logo.update(viewport: size, palette: palette)
    }

    private func projection(_ scene: LifeScene) -> (zoom: CGFloat, offset: CGPoint) {
        let zoom = max(size.width / scene.viewport.width, size.height / scene.viewport.height)
        return (zoom, CGPoint(x: (size.width - scene.viewport.width * zoom) / 2,
                              y: (size.height - scene.viewport.height * zoom) / 2))
    }

    func draw(_ scene: LifeScene, phase: UInt16, animate: Bool, duration: TimeInterval) {
        guard !suspended else { return }
        let (zoom, offset) = projection(scene)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // WallpaperAgent clips the remote layer to its zero-origin window.
        // A bounds-only resize leaves position at the origin with a centered
        // anchor point, so three quarters of the layer fall outside that window.
        root.frame = CGRect(origin: .zero, size: size)
        root.contentsScale = scale
        art.root.position = offset
        art.root.setAffineTransform(CGAffineTransform(scaleX: zoom, y: zoom))
        let layerScale = min(8, scale * zoom)
        if art.contentsScale != layerScale { art.contentsScale = layerScale }
        updatePalette(scene, phase: phase)
        art.draw(scene, animate: animate, duration: duration)
        CATransaction.commit()
    }

    func snapshot(_ scene: LifeScene, phase: UInt16) -> Any? {
        let (zoom, offset) = projection(scene)
        let pixelScale = min(scale, 5120 / max(size.width, size.height))
        let width = Int((size.width * pixelScale).rounded(.up))
        let height = Int((size.height * pixelScale).rounded(.up))
        let sourceScale = min(pixelScale * zoom, 5120 / max(scene.viewport.width, scene.viewport.height))
        guard let image = scene.image(scale: sourceScale, darkness: darkness(phase: phase), colour: colour),
              let surface = IOSurface(properties: [
                .width: width, .height: height, .bytesPerElement: 4,
                .pixelFormat: UInt32(0x42475241) // BGRA
              ]) else { return nil }
        guard surface.lock(options: [], seed: nil) == 0 else { return nil }
        defer { _ = surface.unlock(options: [], seed: nil) }
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: surface.baseAddress, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: surface.bytesPerRow,
                                  space: srgb,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue |
                                      CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.scaleBy(x: pixelScale, y: pixelScale)
        ctx.draw(image, in: CGRect(origin: offset, size: CGSize(width: scene.viewport.width * zoom,
                                                                 height: scene.viewport.height * zoom)))
        brandingArtwork.draw(in: ctx, viewport: size,
                             palette: scene.palette(darkness: darkness(phase: phase), colour: colour))
        return LifeWrapWallpaperSnapshot(surface)
    }
}
