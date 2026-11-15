import AppKit

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
