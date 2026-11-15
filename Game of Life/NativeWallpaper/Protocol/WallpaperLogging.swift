import os

let wallpaperLog = Logger(subsystem: "io.github.thomasturrell.live-simulation-wallpapers.life.wallpaper", category: "Extension")
func debugLog(_ message: String) { wallpaperLog.debug("\(message, privacy: .public)") }
