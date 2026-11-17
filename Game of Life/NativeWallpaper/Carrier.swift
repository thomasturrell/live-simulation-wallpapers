import AppKit
import LifeArt
import SwiftUI

@main
@MainActor
enum WallpaperInstaller {
    static func main() {
        let extensionURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Extensions/LifeWallpaper.appex")
        let installer = Process()
        installer.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        installer.arguments = ["-a", extensionURL.path]

        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        application.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Game of Life Wallpaper"

        do {
            try installer.run()
            installer.waitUntilExit()
            if installer.terminationStatus == 0 {
                alert.informativeText = "Select Game of Life for both Wallpaper and Screen Saver in System Settings. macOS runs the extension once this window closes."
                if let store = LifeBrandingStore.shared() {
                    let model = WallpaperBrandingModel(store: store)
                    let view = NSHostingView(rootView: WallpaperBrandingSettings(model: model))
                    view.frame = NSRect(x: 0, y: 0, width: 400, height: 104)
                    alert.accessoryView = view
                }
            } else {
                alert.alertStyle = .warning
                alert.informativeText = "macOS could not register the wallpaper extension. Keep the app in Applications and try opening it again. The separate wallpaper and screen saver pack is also available."
            }
        } catch {
            alert.alertStyle = .warning
            alert.informativeText = "macOS could not start extension registration. \(error.localizedDescription)"
        }

        alert.addButton(withTitle: "Done")
        alert.runModal()
    }
}

@MainActor
private final class WallpaperBrandingModel: ObservableObject {
    private let store: LifeBrandingStore
    @Published private(set) var branding: LifeBranding

    init(store: LifeBrandingStore) {
        self.store = store
        branding = store.load()
    }

    func update(_ updated: LifeBranding) throws {
        try store.save(updated)
        branding = updated
        DistributedNotificationCenter.default().postNotificationName(
            LifeBranding.didChange, object: nil, userInfo: nil, deliverImmediately: true
        )
    }
}

@MainActor
private struct WallpaperBrandingSettings: View {
    @ObservedObject var model: WallpaperBrandingModel

    var body: some View {
        LifeBrandingControls(branding: model.branding, onChange: model.update)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
