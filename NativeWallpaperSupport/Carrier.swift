import AppKit

let bundle = Bundle.main
let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Live Wallpaper"
let application = NSApplication.shared
application.setActivationPolicy(.regular)
application.activate(ignoringOtherApps: true)
let alert = NSAlert()
alert.messageText = name

do {
    let directories = try FileManager.default.contentsOfDirectory(
        at: bundle.bundleURL.appendingPathComponent("Contents/Extensions"), includingPropertiesForKeys: nil
    )
    guard let extensionURL = directories.first(where: { $0.pathExtension == "appex" }),
          let choice = Bundle(url: extensionURL)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String else {
        throw CocoaError(.fileReadCorruptFile)
    }

    let installer = Process()
    installer.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
    installer.arguments = ["-a", extensionURL.path]
    try installer.run()
    installer.waitUntilExit()
    if installer.terminationStatus == 0 {
        alert.informativeText = "Select \(choice) for both Wallpaper and Screen Saver in System Settings. macOS runs the extension once this window closes."
    } else {
        alert.alertStyle = .warning
        alert.informativeText = "macOS could not register the wallpaper extension. Keep the app in Applications and try opening it again."
    }
} catch {
    alert.alertStyle = .warning
    alert.informativeText = "macOS could not start extension registration. \(error.localizedDescription)"
}

alert.addButton(withTitle: "Done")
alert.runModal()
