import os

let wallpaperLog = Logger(subsystem: "uk.co.cosimmetry.life.wallpaper", category: "Extension")
func debugLog(_ message: String) { wallpaperLog.debug("\(message, privacy: .public)") }
