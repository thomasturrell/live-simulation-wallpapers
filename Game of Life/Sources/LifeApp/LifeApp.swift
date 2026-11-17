import AppKit
import SwiftUI
import LifeArt

@main
@MainActor
enum LifeApp {
    static func main() throws {
        let arguments = CommandLine.arguments
        if arguments.count == 3, arguments[1] == "--export-wallpaper" {
            try WallpaperExport.write(to: URL(fileURLWithPath: arguments[2], isDirectory: true))
            return
        }
        if arguments.count == 3, arguments[1] == "--render-samples" {
            let folder = URL(fileURLWithPath: arguments[2], isDirectory: true)
            let scene = LifeScene(viewport: CGSize(width: 1440, height: 900),
                                  settings: LifeSettings())
            for (name, dark) in [("Dark", true), ("Light", false)] {
                guard let image = scene.image(scale: 1, dark: dark) else { throw WallpaperError.imageFailed }
                try writePNG(image, to: folder.appendingPathComponent("Game of Life – \(name).png"))
            }
            return
        }

        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let preferences = LifeSettings.moduleDefaults()
    private lazy var model = SettingsModel(settings: LifeSettings(defaults: preferences),
                                           desktopMotion: DesktopMotion(defaults: .standard))
    private lazy var desktop = DesktopController(settings: model.settings)
    private var statusItem: NSStatusItem?
    private var pauseItem: NSMenuItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.onSettingsChange = { [weak self] settings in
            guard let self else { return }
            settings.save(to: self.preferences)
            self.desktop.settings = settings
            self.pauseItem?.title = settings.paused ? "Resume Animation" : "Pause Animation"
        }
        model.onDesktopChange = { [weak self] motion in
            UserDefaults.standard.set(motion.rawValue, forKey: "desktopMotion")
            self?.desktop.setMotion(motion)
        }
        createMenu()
        desktop.setMotion(model.desktopMotion)
        let notifications = DistributedNotificationCenter.default()
        notifications.addObserver(self, selector: #selector(saverStarted(_:)),
                                  name: SaverPlaybackSignal.started, object: nil,
                                  suspensionBehavior: .deliverImmediately)
        notifications.addObserver(self, selector: #selector(saverStopped(_:)),
                                  name: SaverPlaybackSignal.stopped, object: nil,
                                  suspensionBehavior: .deliverImmediately)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged(_:)),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        openSettings()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        openSettings()
        return true
    }

    private func createMenu() {
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "square.grid.3x3", accessibilityDescription: "Game of Life")
        let menu = NSMenu()
        menu.addItem(item("Open Settings…", #selector(openSettings), key: ","))
        let pause = item(model.settings.paused ? "Resume Animation" : "Pause Animation",
                         #selector(togglePause), key: "")
        menu.addItem(pause)
        menu.addItem(.separator())
        menu.addItem(item("Quit Game of Life", #selector(NSApplication.terminate(_:)), key: "q",
                          target: NSApp))
        status.menu = menu
        statusItem = status
        pauseItem = pause
    }

    private func item(_ title: String, _ action: Selector, key: String, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        return item
    }

    @objc private func screensChanged(_ notification: Notification) { desktop.refreshScreens() }

    @objc private func saverStarted(_ notification: Notification) { desktop.saverStarted() }

    @objc private func saverStopped(_ notification: Notification) { desktop.saverStopped() }

    @objc private func togglePause() { model.settings.paused.toggle() }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 728, height: 650),
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "Game of Life"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            window.contentView = NSHostingView(rootView: SettingsView(model: model) { [weak self] in
                self?.applyStill()
            })
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        settingsWindow = nil
    }

    private func applyStill() {
        let alert = NSAlert()
        do {
            try desktop.setStillWallpaper()
            model.desktopMotion = .off
            alert.messageText = "Still wallpaper set"
            alert.informativeText = "The current composition has been applied to your connected displays."
        } catch {
            alert.alertStyle = .warning
            alert.messageText = "Couldn’t set every wallpaper"
            alert.informativeText = error.localizedDescription
        }
        if let window = settingsWindow { alert.beginSheetModal(for: window) }
    }
}
