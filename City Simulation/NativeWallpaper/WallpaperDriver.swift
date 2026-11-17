import AppKit
import CityArt
import CityEngine
import IOSurface
import QuartzCore

@MainActor
final class WallpaperDriver {
    static let shared = WallpaperDriver()
    private var displays: [String: DisplayPlayback] = [:]
    private var owners: [UUID: DisplayPlayback] = [:]
    private var saverHint: Bool?
    private var observers: [NSObjectProtocol] = []
    var invalidateSnapshots: (() -> Void)?

    private init() {
        let signals = [
            "com.apple.screensaver.didstart": true,
            "com.apple.screensaver.didstop": false,
            "com.apple.screenIsUnlocked": false
        ]
        observers = signals.map { name, active in
            DistributedNotificationCenter.default().addObserver(
                forName: .init(name), object: nil, queue: .main
            ) { note in
                guard note.object as? String != "runFromPref" else { return }
                MainActor.assumeIsolated {
                    WallpaperDriver.shared.saverHint = active
                    WallpaperDriver.shared.refreshAll()
                }
            }
        }
    }

    func acquire(_ id: UUID, _ request: Presentation) throws -> Any {
        guard LifeLoadWallpaperABI(), let size = request.size else { throw BridgeError.incompatible }
        let view = RemoteView(size: size, request: request)
        guard let context = view.makeContext(display: request.displayID) else { throw BridgeError.incompatible }

        let checkpointKey = request.preview ? nil : request.displayKey
        let key = checkpointKey ?? (request.preview ? "preview-\(id)" : "session-\(id)")
        let playback = displays[key] ?? DisplayPlayback(checkpointKey: checkpointKey)
        if let previous = owners[id], previous !== playback { invalidate(id) }
        if !view.preview && view.isSaver && owners[id] == nil { saverHint = nil }
        displays[key] = playback
        owners[id] = playback
        playback.views[id] = view
        playback.onSettled = { [weak self] in self?.invalidateSnapshots?() }
        view.draw(playback.city)
        playback.refresh(hint: saverHint)
        CATransaction.flush()
        return context
    }

    func update(_ id: UUID, _ request: Presentation) {
        guard let playback = owners[id], let view = playback.views[id] else { return }
        let wasSaver = view.isSaver
        if view.apply(request) { view.draw(playback.city) }
        if !view.preview && wasSaver != view.isSaver {
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
        guard let playback = owners[id], let view = playback.views[id],
              let snapshot = view.snapshot(playback.city) else { throw BridgeError.noSurface }
        return snapshot
    }

    private func refreshAll() {
        for playback in displays.values { playback.refresh(hint: saverHint) }
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
    var views: [UUID: RemoteView] = [:]
    var onSettled: (() -> Void)?
    private var playback: Playback
    private let path: URL?
    private var lastSavedTick: Int
    private var lastWriteAttempt: Int
    private var timer: DispatchSourceTimer?
    private var timestamp = 0.0

    var city: City { playback.city }
    var hasTimer: Bool { timer != nil }

    init(checkpointKey: String?, storage: URL? = nil) {
        var path: URL?
        var seed = City.defaultSeed
        if let checkpointKey,
           let base = storage ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let directory = base.appendingPathComponent("City Simulation/Wallpaper State", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                path = directory.appendingPathComponent(checkpointKey).appendingPathExtension("plist")
            } catch {
                wallpaperLog.error("Cannot create the checkpoint directory: \(error.localizedDescription)")
            }
            for byte in checkpointKey.utf8 { seed = (seed ^ UInt64(byte)) &* 1_099_511_628_211 }
        }
        self.path = path
        let restored = path.flatMap { try? Data(contentsOf: $0, options: .mappedIfSafe) }.flatMap(City.init(checkpoint:))
        playback = Playback(city: restored ?? City(seed: seed))
        lastSavedTick = restored?.tick ?? 0
        lastWriteAttempt = lastSavedTick
    }

    deinit { timer?.cancel() }

    func refresh(hint: Bool?) {
        let visible = views.values.filter { !$0.suspended }
        let animated = visible.contains { $0.preview } || (hint ?? visible.contains { $0.isSaver })
        let previous = playback.mode
        playback.present(visible: !visible.isEmpty, animated: animated)
        if playback.needsTimer {
            if timer == nil {
                timestamp = ProcessInfo.processInfo.systemUptime
                let timer = DispatchSource.makeTimerSource(queue: .main)
                timer.schedule(deadline: .now() + .milliseconds(50), repeating: .milliseconds(50), leeway: .milliseconds(4))
                timer.setEventHandler { [weak self] in
                    MainActor.assumeIsolated { self?.advance() }
                }
                self.timer = timer
                timer.activate()
            }
        } else {
            stopTimer()
            if previous != playback.mode { save() }
        }
        // Persist at unlock, in case the host replaces the live surface before
        // the slowdown can finish. The settled frame supersedes this checkpoint.
        if previous == .playing && playback.mode == .settling { save() }
    }

    private func advance() {
        let now = ProcessInfo.processInfo.systemUptime
        let before = city.tick
        playback.advance(elapsed: now - timestamp)
        timestamp = now
        if city.tick != before {
            for view in views.values where !view.suspended { view.draw(city) }
            if city.tick - lastWriteAttempt >= City.ticksPerSecond * 15 { save() }
        }
        if !playback.needsTimer {
            stopTimer()
            save()
            onSettled?()
        }
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func save() {
        guard let path, city.tick != lastSavedTick else { return }
        // Space out retries as well as successful writes during active playback.
        lastWriteAttempt = city.tick
        do {
            try city.checkpoint().write(to: path, options: .atomic)
            lastSavedTick = city.tick
        } catch {
            wallpaperLog.error("Checkpoint write failed: \(error.localizedDescription)")
        }
    }
}

@MainActor
final class RemoteView {
    let root = CALayer()
    private let pixels = CALayer()
    private let renderer = CityRenderer()
    private var context: AnyObject?
    private var size: CGSize
    private var scale: CGFloat
    private var hasPlacement: Bool
    private var mode: String
    private(set) var suspended: Bool
    let preview: Bool

    var isSaver: Bool { mode == "locked" || (mode == "idle" && !hasPlacement) }

    init(size: CGSize, request: Presentation) {
        self.size = size
        scale = request.scale ?? 1
        mode = request.mode ?? "default"
        hasPlacement = request.hasPlacement
        suspended = request.activity == "suspended"
        preview = request.preview
        root.frame = CGRect(origin: .zero, size: size)
        root.contentsScale = scale
        root.masksToBounds = true
        pixels.magnificationFilter = .nearest
        pixels.minificationFilter = .nearest
        pixels.contentsGravity = .resize
        root.addSublayer(pixels)
    }

    func makeContext(display: UInt32?) -> Any? {
        guard let context = LifeMakeWallpaperContext(root, scale, display.map { NSNumber(value: $0) }) else { return nil }
        self.context = context as AnyObject
        return LifeWrapWallpaperContext(context)
    }

    func apply(_ request: Presentation) -> Bool {
        let previous = (size, scale, suspended)
        if let mode = request.mode {
            self.mode = mode
            hasPlacement = request.hasPlacement
        }
        if let activity = request.activity { suspended = activity == "suspended" }
        if let size = request.size { self.size = size }
        if let scale = request.scale { self.scale = scale }
        return previous != (size, scale, suspended)
    }

    func draw(_ city: City) {
        guard !suspended else { return }
        let frame = viewport(scale)
        let rect = frame.imageRect
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.frame = CGRect(origin: .zero, size: size)
        root.contentsScale = scale
        pixels.frame = CGRect(x: rect.minX / scale, y: rect.minY / scale,
                              width: rect.width / scale, height: rect.height / scale)
        pixels.contents = renderer.image(for: city, viewport: frame)
        CATransaction.commit()
    }

    func snapshot(_ city: City) -> Any? {
        let frame = viewport(min(scale, 5120 / max(size.width, size.height)))
        guard let surface = IOSurface(properties: [
            .width: frame.pixelWidth, .height: frame.pixelHeight, .bytesPerElement: 4,
            .pixelFormat: UInt32(0x42475241) // BGRA
        ]), surface.lock(options: [], seed: nil) == 0 else { return nil }
        defer { _ = surface.unlock(options: [], seed: nil) }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: surface.baseAddress, width: frame.pixelWidth, height: frame.pixelHeight,
                                      bitsPerComponent: 8, bytesPerRow: surface.bytesPerRow, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue |
                                          CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        // A snapshot should not evict the animation's cached viewport.
        let image = (frame == viewport(scale) ? renderer : CityRenderer()).image(for: city, viewport: frame)
        frame.draw(image, in: context)
        context.flush()
        return LifeWrapWallpaperSnapshot(surface)
    }

    private func viewport(_ factor: CGFloat) -> CityViewport {
        CityViewport(pixelWidth: Int((size.width * factor).rounded(.up)),
                     pixelHeight: Int((size.height * factor).rounded(.up)))
    }
}
