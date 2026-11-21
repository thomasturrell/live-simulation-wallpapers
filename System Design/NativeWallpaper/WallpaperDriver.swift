import AppKit
import DesignArt
import DesignEngine
import IOSurface
import QuartzCore

enum BridgeError: LocalizedError {
    case incompatible, noSurface
    var errorDescription: String? {
        switch self {
        case .incompatible: "The WallpaperAgent interface is incompatible with this build."
        case .noSurface: "The requested wallpaper surface is unavailable."
        }
    }
}

@MainActor
final class WallpaperDriver {
    static let shared = WallpaperDriver()
    var invalidateSnapshots: (() -> Void)?
    private var displays: [String: DisplayPlayback] = [:]
    private var owners: [UUID: DisplayPlayback] = [:]
    private var hint: Bool?
    private var observers: [NSObjectProtocol] = []

    private init() {
        let centre = DistributedNotificationCenter.default()
        for (name, active) in [("com.apple.screensaver.didstart", true), ("com.apple.screensaver.didstop", false),
                               ("com.apple.screenIsUnlocked", false)] {
            observers.append(centre.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] note in
                guard note.object as? String != "runFromPref" else { return }
                MainActor.assumeIsolated {
                    self?.hint = active
                    self?.refreshAll()
                }
            })
        }
        observers.append(centre.addObserver(forName: .init("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appearanceChanged() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSColor.systemColorsDidChangeNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                var changed = false
                for playback in self.displays.values {
                    for view in playback.views.values where view.refreshAccent(playback.exploration) {
                        changed = changed || !view.preview
                    }
                }
                if changed { self.invalidateSnapshots?() }
            }
        })
    }

    func acquire(_ id: UUID, _ request: Presentation) throws -> Any {
        guard LifeLoadWallpaperABI(), let size = request.size else { throw BridgeError.incompatible }
        let view = RemoteView(size: size, request: request)
        guard let context = view.makeContext(display: request.displayID) else { throw BridgeError.incompatible }
        let uuid = request.preview ? nil : request.displayKey.flatMap(UUID.init(uuidString:))
        let key = uuid?.uuidString ?? (request.preview ? "preview-\(id)" : "session-\(id)")
        let playback = displays[key] ?? DisplayPlayback(displayUUID: uuid)
        if let previous = owners[id], previous !== playback { invalidate(id) }
        if !view.preview && view.isSaver && owners[id] == nil { hint = nil }
        displays[key] = playback
        owners[id] = playback
        playback.views[id] = view
        playback.invalidateSnapshots = { [weak self] in self?.invalidateSnapshots?() }
        let changed = playback.select(request.optionIDs["explore"])
        playback.refresh(hint: hint)
        if changed { playback.drawAll() } else { view.draw(playback.exploration) }
        CATransaction.flush()
        return context
    }

    func update(_ id: UUID, _ request: Presentation) {
        guard let playback = owners[id], let view = playback.views[id] else { return }
        let previous = view.isSaver
        let change = view.apply(request)
        let selected = playback.select(request.optionIDs["explore"])
        if !view.preview && view.isSaver != previous {
            hint = nil
            refreshAll()
        } else { playback.refresh(hint: hint) }
        if selected { playback.drawAll() }
        else if change.redraw { view.draw(playback.exploration) }
        if !view.preview && (change.art || selected) { invalidateSnapshots?() }
    }

    func invalidate(_ id: UUID) {
        guard let playback = owners.removeValue(forKey: id) else { return }
        playback.views.removeValue(forKey: id)
        playback.refresh(hint: hint)
        if playback.views.isEmpty { displays = displays.filter { $0.value !== playback } }
    }

    func snapshot(_ id: UUID) throws -> Any {
        guard let playback = owners[id], let view = playback.views[id] else { throw BridgeError.noSurface }
        let desktop = !view.preview && (!view.isSaver || hint == false)
        let frame = desktop ? playback.desktopSnapshotFrame() : playback.exploration
        guard let snapshot = view.snapshot(frame) else {
            throw BridgeError.noSurface
        }
        return snapshot
    }

    private func refreshAll() {
        for playback in displays.values { playback.refresh(hint: hint) }
    }

    private func appearanceChanged() {
        var request = Presentation(nil)
        request.systemDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        var changed = false
        for playback in displays.values {
            for view in playback.views.values where view.apply(request).art {
                view.draw(playback.exploration)
                changed = changed || !view.preview
            }
        }
        if changed { invalidateSnapshots?() }
    }
}

@MainActor
final class DisplayPlayback {
    var views: [UUID: RemoteView] = [:]
    var invalidateSnapshots: (() -> Void)?
    private let path: URL?
    private let seed: UInt64
    private var playback: Playback
    private var timer: DispatchSourceTimer?
    private var timestamp = 0.0
    private var refreshDesktopSnapshot = false
    private var lastSnapshotRefresh = 0.0
    private var lastSaved: (Int, Double)
    private var lastAttempt: Int
    var exploration: Exploration { playback.exploration }
    var hasTimer: Bool { timer != nil }
    private var frame: (Int, Double) { (exploration.age, exploration.elevation) }

    init(displayUUID: UUID?, storage: URL? = nil) {
        var path: URL?
        if let displayUUID, let base = storage ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let folder = base.appendingPathComponent("System Design/Wallpaper State", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                path = folder.appendingPathComponent(displayUUID.uuidString).appendingPathExtension("plist")
            } catch { wallpaperLog.error("Cannot create checkpoint directory: \(error.localizedDescription)") }
        }
        self.path = path
        seed = displayUUID?.uuidString.utf8.reduce(42) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 } ?? 42
        let restored = path.flatMap { try? Data(contentsOf: $0) }.flatMap { Exploration(checkpoint: $0) }
        playback = Playback(restored ?? Exploration(seed: seed))
        lastSaved = (playback.exploration.age, playback.exploration.elevation)
        lastAttempt = playback.exploration.age
    }

    deinit { timer?.cancel() }

    func desktopSnapshotFrame() -> Exploration {
        if playback.mode == .settling { refreshDesktopSnapshot = true }
        return playback.mode == .suspended ? exploration.restingFrame : exploration
    }

    func select(_ scope: String?) -> Bool {
        guard let scope, exploration.scope != scope,
              scope == "all" || Subject(rawValue: scope) != nil || Catalogue.bundled[scope] != nil else { return false }
        playback = Playback(Exploration(seed: seed, scope: scope))
        lastSaved = (-1, 0)
        save()
        return true
    }

    func refresh(hint: Bool?) {
        let visible = views.values.filter { !$0.suspended }
        let animated = visible.contains { $0.preview } || (hint ?? visible.contains { $0.isSaver })
        let previous = playback.mode
        playback.present(visible: !visible.isEmpty, animated: animated)
        if previous != .settling && playback.mode == .settling {
            refreshDesktopSnapshot = true
            lastSnapshotRefresh = ProcessInfo.processInfo.systemUptime
        }
        if playback.needsTimer && timer == nil {
            timestamp = ProcessInfo.processInfo.systemUptime
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + .milliseconds(63), repeating: .milliseconds(63), leeway: .milliseconds(5))
            timer.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.advance() } }
            self.timer = timer
            timer.activate()
        } else if !playback.needsTimer { stop() }
        if previous != playback.mode && playback.mode != .playing { save() }
        if previous == .playing && playback.mode == .still && visible.contains(where: { !$0.preview }) {
            invalidateSnapshots?()
        }
    }

    func drawAll() { for view in views.values { view.draw(exploration) } }

    private func advance() {
        let now = ProcessInfo.processInfo.systemUptime
        let before = frame
        playback.advance(elapsed: now - timestamp)
        timestamp = now
        if before != frame {
            for view in views.values where !view.suspended { view.draw(exploration) }
            if exploration.age - lastAttempt >= 15 * Exploration.ticksPerSecond { save() }
            // Offer one intermediate image on unlock. Keep refreshing only while the
            // host samples it, at most four times per second and only during settling.
            if playback.mode == .settling, refreshDesktopSnapshot, now - lastSnapshotRefresh >= 0.25 {
                refreshDesktopSnapshot = false
                lastSnapshotRefresh = now
                if views.values.contains(where: { !$0.preview }) { invalidateSnapshots?() }
            }
        }
        if !playback.needsTimer {
            stop()
            save()
            if views.values.contains(where: { !$0.preview }) { invalidateSnapshots?() }
        }
    }

    private func stop() { timer?.cancel(); timer = nil }

    private func save() {
        guard let path, lastSaved != frame else { return }
        lastAttempt = exploration.age
        do {
            try exploration.checkpoint().write(to: path, options: .atomic)
            lastSaved = frame
        } catch { wallpaperLog.error("Checkpoint write failed: \(error.localizedDescription)") }
    }
}

@MainActor
final class RemoteView {
    private let renderer = DesignRenderer()
    private lazy var snapshotRenderer = DesignRenderer()
    var root: CALayer { renderer.root }
    private var context: AnyObject?
    private var size: CGSize
    private var scale: CGFloat = 1
    private var style = DesignStyle()
    private var dark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    private var placement = false
    private var mode = "default"
    private(set) var suspended = false
    let preview: Bool
    var isSaver: Bool { mode == "locked" || (mode == "idle" && !placement) }

    init(size: CGSize, request: Presentation) {
        self.size = size
        preview = request.preview
        _ = apply(request)
    }

    func apply(_ request: Presentation) -> (redraw: Bool, art: Bool) {
        let before = (size, scale, suspended)
        let oldStyle = style, wasDark = style.appearance.isDark(systemDark: dark)
        if let mode = request.mode { self.mode = mode; placement = request.hasPlacement }
        if let size = request.size { self.size = size }
        if let scale = request.scale { self.scale = scale }
        if let active = request.activity { suspended = active == "suspended" }
        if let dark = request.systemDark { self.dark = dark }
        style.apply(request.optionIDs)
        let art = style != oldStyle || wasDark != style.appearance.isDark(systemDark: dark)
        return (art || before != (size, scale, suspended), art)
    }

    func makeContext(display: UInt32?) -> Any? {
        guard let context = LifeMakeWallpaperContext(root, scale, display.map { NSNumber(value: $0) }) else { return nil }
        self.context = context as AnyObject
        return LifeWrapWallpaperContext(context)
    }

    func draw(_ exploration: Exploration) { renderer.draw(exploration, size: size, scale: scale, style: style, systemDark: dark) }

    func refreshAccent(_ exploration: Exploration) -> Bool {
        guard style.colour == .accent else { return false }
        renderer.systemAccentChanged()
        snapshotRenderer.systemAccentChanged()
        draw(exploration)
        return true
    }

    func snapshot(_ exploration: Exploration) -> Any? {
        // WallpaperAgent may request the resting snapshot while the remote layer is
        // still settling. Capturing it must not advance the live surface.
        snapshotRenderer.draw(exploration, size: size, scale: scale, style: style, systemDark: dark)
        let factor = min(scale, 5120 / max(size.width, size.height))
        let width = Int(ceil(size.width * factor)), height = Int(ceil(size.height * factor))
        guard let surface = IOSurface(properties: [.width: width, .height: height, .bytesPerElement: 4,
                                                  .pixelFormat: UInt32(0x42475241)]),
              surface.lock(options: [], seed: nil) == 0 else { return nil }
        defer { _ = surface.unlock(options: [], seed: nil) }
        guard let c = CGContext(data: surface.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: surface.bytesPerRow, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        c.scaleBy(x: CGFloat(width) / size.width, y: CGFloat(height) / size.height)
        snapshotRenderer.root.render(in: c)
        c.flush()
        return LifeWrapWallpaperSnapshot(surface)
    }
}
