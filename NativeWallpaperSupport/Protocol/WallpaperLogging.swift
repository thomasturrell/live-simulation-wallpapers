import os

let wallpaperLog = Logger(subsystem: wallpaperChoice.bundleID, category: "Extension")
func debugLog(_ message: String) { wallpaperLog.debug("\(message, privacy: .public)") }
