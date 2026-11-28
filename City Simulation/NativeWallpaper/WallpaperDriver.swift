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
    private var localObservers: [NSObjectProtocol] = []
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
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: .init("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshEnvironment(appearanceChanged: true) }
        })
        let calendarEvents: [Notification.Name] = [.NSCalendarDayChanged, .NSSystemClockDidChange, .NSSystemTimeZoneDidChange]
        localObservers = calendarEvents.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshEnvironment() }
            }
        }
        localObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refreshEnvironment() } })
    }

    func acquire(_ id: UUID, _ request: Presentation) throws -> Any {
        guard LifeLoadWallpaperABI(), let size = request.size else { throw BridgeError.incompatible }
        let view = RemoteView(size: size, request: request)
        guard let context = view.makeContext(display: request.displayID) else { throw BridgeError.incompatible }

        let displayUUID = request.preview ? nil : request.displayKey.flatMap(UUID.init(uuidString:))
        let key = displayUUID?.uuidString ?? (request.preview ? "preview-\(id)" : "session-\(id)")
        let playback = displays[key] ?? DisplayPlayback(displayUUID: displayUUID)
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
        let applied = view.apply(request)
        let artworkChanged = view.needsArtworkRedraw(playback.city)
        if applied || artworkChanged { view.draw(playback.city) }
        if !view.preview && wasSaver != view.isSaver {
            saverHint = nil
            refreshAll()
        } else {
            playback.refresh(hint: saverHint)
        }
        // Host activity/geometry updates and its own preview refreshes must not
        // invalidate snapshots again. WallpaperAgent can answer an invalidation
        // with another update, creating a refresh loop while Settings loads.
        if artworkChanged && !view.preview { invalidateSnapshots?() }
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
              let surface = view.snapshot(playback.city), let snapshot = LifeWrapWallpaperSnapshot(surface) else { throw BridgeError.noSurface }
        return snapshot
    }

    private func refreshAll() {
        for playback in displays.values {
            playback.refresh(hint: saverHint)
            for view in playback.views.values where !view.suspended { view.draw(playback.city) }
        }
    }

    private func refreshEnvironment(appearanceChanged: Bool = false) {
        var changed = false
        for playback in displays.values {
            for view in playback.views.values {
                if appearanceChanged { view.refreshSystemAppearance() }
                guard view.needsArtworkRedraw(playback.city) else { continue }
                changed = !view.preview || changed
                view.draw(playback.city)
            }
        }
        if changed { invalidateSnapshots?() }
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

    init(displayUUID: UUID?, storage: URL? = nil) {
        var path: URL?
        if let displayUUID,
           let base = storage ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let directory = base.appendingPathComponent("City Simulation/Wallpaper State", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                path = directory.appendingPathComponent(displayUUID.uuidString).appendingPathExtension("plist")
            } catch {
                wallpaperLog.error("Cannot create the checkpoint directory: \(error.localizedDescription)")
            }
        }
        self.path = path
        let restored = path.flatMap { try? Data(contentsOf: $0, options: .mappedIfSafe) }.flatMap(City.init(checkpoint:))
        playback = Playback(city: restored ?? City(displayUUID: displayUUID))
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
    private var systemDark: Bool
    private(set) var environmentMode: EnvironmentMode = .simulationWorld
    private(set) var skin: CitySkin = .original
    private var renderedSkin: CitySkin?
    private var renderedEnvironment: EnvironmentFrame?
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
        systemDark = request.systemDark ?? (UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark")
        if let selected = request.optionIDs["skin"].flatMap(CitySkin.init(rawValue:)) { skin = selected }
        if let mode = request.optionIDs["environment"].flatMap(EnvironmentMode.init(rawValue:)) { environmentMode = mode }
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
        let oldMode = environmentMode
        let oldDark = systemDark
        if let selected = request.optionIDs["skin"].flatMap(CitySkin.init(rawValue:)) { skin = selected }
        if let mode = request.optionIDs["environment"].flatMap(EnvironmentMode.init(rawValue:)) { environmentMode = mode }
        if let dark = request.systemDark { systemDark = dark }
        if let mode = request.mode {
            self.mode = mode
            hasPlacement = request.hasPlacement
        }
        if let activity = request.activity { suspended = activity == "suspended" }
        if let size = request.size { self.size = size }
        if let scale = request.scale { self.scale = scale }
        return previous != (size, scale, suspended) || oldMode != environmentMode || oldDark != systemDark
    }

    func refreshSystemAppearance() { systemDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" }

    func environment(for city: City) -> EnvironmentFrame {
        Environment.frame(city: city, mode: environmentMode, systemDark: systemDark)
    }

    func needsArtworkRedraw(_ city: City) -> Bool {
        renderedSkin != skin || renderedEnvironment != environment(for: city).quantized
    }

    func draw(_ city: City) {
        // Suspension stops simulation ticks, not explicit static-frame painting.
        // WallpaperAgent can acquire or reconfigure a desktop while suspended.
        let frame = viewport(scale)
        let rect = frame.imageRect
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.frame = CGRect(origin: .zero, size: size)
        root.contentsScale = scale
        let environment = environment(for: city)
        pixels.frame = CGRect(x: rect.minX / scale, y: rect.minY / scale,
                              width: rect.width / scale, height: rect.height / scale)
        pixels.minificationFilter = skin == .contemporary ? .linear : .nearest
        pixels.magnificationFilter = skin == .contemporary ? .linear : .nearest
        pixels.contents = renderer.image(for: city, viewport: frame, environment: environment, skin: skin)
        renderedSkin = skin
        renderedEnvironment = environment.quantized
        CATransaction.commit()
    }

    func snapshot(_ city: City) -> IOSurface? {
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
        let snapshotRenderer = frame == viewport(scale) ? renderer : CityRenderer()
        let image = snapshotRenderer.image(for: city, viewport: frame, environment: environment(for: city), skin: skin)
        frame.draw(image, in: context)
        context.flush()
        return surface
    }

    private func viewport(_ factor: CGFloat) -> CityViewport {
        CityViewport(pixelWidth: Int((size.width * factor).rounded(.up)),
                     pixelHeight: Int((size.height * factor).rounded(.up)))
    }
}
