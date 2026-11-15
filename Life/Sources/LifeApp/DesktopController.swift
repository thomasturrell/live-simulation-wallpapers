import AppKit
import ImageIO
import LifeArt
import UniformTypeIdentifiers

enum DesktopMotion: String, CaseIterable, Identifiable {
    case settleOnReturn
    case continuous
    case off

    var id: Self { self }
    var title: String {
        switch self {
        case .settleOnReturn: return "Settle on Return"
        case .continuous: return "Continuous"
        case .off: return "Off"
        }
    }

    var explanation: String {
        switch self {
        case .settleOnReturn: return "Slows to a still when the desktop comes back into view."
        case .continuous: return "Keeps evolving behind Finder while the app is open."
        case .off: return "Uses your macOS wallpaper."
        }
    }

    init(defaults: UserDefaults) {
        if let saved = defaults.string(forKey: "desktopMotion").flatMap(Self.init(rawValue:)) {
            self = saved
        } else if defaults.object(forKey: "liveDesktop") != nil && !defaults.bool(forKey: "liveDesktop") {
            self = .off
        } else {
            self = .settleOnReturn
        }
    }
}

@MainActor
final class DesktopController {
    private struct Surface {
        let window: NSWindow
        let view: LifeView
    }

    private var surfaces: [CGDirectDisplayID: Surface] = [:]
    private var motion: DesktopMotion = .off
    private var saverWasRunning = false
    var settings: LifeSettings {
        didSet {
            for surface in surfaces.values { surface.view.settings = settings }
        }
    }

    init(settings: LifeSettings) {
        self.settings = settings
    }

    func setMotion(_ motion: DesktopMotion) {
        self.motion = motion
        refreshScreens()
    }

    func saverStarted() {
        saverWasRunning = true
    }

    func saverStopped() {
        guard saverWasRunning else { return }
        saverWasRunning = false
        for surface in surfaces.values { surface.view.replaySettleIfIdle() }
    }

    func refreshScreens() {
        let screens = motion == .off ? [] : NSScreen.screens
        let playback: LifeView.Playback = motion == .settleOnReturn ? .settleOnReveal : .continuous
        let connected = Set(screens.compactMap(\.displayID))
        for id in Set(surfaces.keys).subtracting(connected) {
            guard let surface = surfaces.removeValue(forKey: id) else { continue }
            surface.view.playbackEnabled = false
            surface.window.orderOut(nil)
        }
        for screen in screens {
            guard let id = screen.displayID else { continue }
            if let surface = surfaces[id] {
                surface.view.playback = playback
                surface.window.setFrame(screen.frame, display: true)
                continue
            }
            let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.setFrame(screen.frame, display: false)
            window.level = .init(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.isOpaque = true
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.hidesOnDeactivate = false
            window.isExcludedFromWindowsMenu = true
            window.animationBehavior = .none
            window.isReleasedWhenClosed = false
            let view = LifeView(frame: CGRect(origin: .zero, size: screen.frame.size),
                                settings: settings)
            view.playback = playback
            window.contentView = view
            window.orderBack(nil)
            surfaces[id] = Surface(window: window, view: view)
        }
    }

    func setStillWallpaper() throws {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { throw WallpaperError.noDisplays }
        let folder = try FileManager.default.url(for: .applicationSupportDirectory,
                                                  in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Cosimmetry Life/Wallpapers", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Create every image before changing any desktop.
        let files = try screens.map { screen in
            let scale = screen.backingScaleFactor
            let image: CGImage?
            if let id = screen.displayID, let surface = surfaces[id] {
                image = surface.view.snapshot(scale: scale)
            } else {
                let scene = LifeScene(viewport: screen.frame.size, settings: settings)
                image = scene.image(scale: scale, dark: settings.appearance.isDark(in: NSApp.effectiveAppearance))
            }
            guard let image else { throw WallpaperError.imageFailed }
            let url = folder.appendingPathComponent("Life-\(UUID().uuidString).png")
            try writePNG(image, to: url)
            return (screen, url)
        }
        var failures = 0
        for (screen, url) in files {
            do {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen,
                                                           options: [.imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                                                                     .allowClipping: false])
            } catch {
                failures += 1
            }
        }
        if failures > 0 { throw WallpaperError.applyFailed(failures, files.count) }
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

enum WallpaperError: LocalizedError {
    case noDisplays, imageFailed, applyFailed(Int, Int)

    var errorDescription: String? {
        switch self {
        case .noDisplays: return "macOS reported no available displays."
        case .imageFailed: return "The wallpaper image could not be created."
        case let .applyFailed(number, total):
            return "macOS could not set the wallpaper on \(number) of \(total) displays."
        }
    }
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString,
                                                            1, nil) else {
        throw WallpaperError.imageFailed
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw WallpaperError.imageFailed }
}
