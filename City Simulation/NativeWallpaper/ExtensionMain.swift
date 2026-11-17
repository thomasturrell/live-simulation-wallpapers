import ExtensionFoundation
import Foundation

@main
final class CityWallpaper: NSObject, AppExtension {
    var configuration: some AppExtensionConfiguration { WallpaperExtensionConfig() }

    override required init() {
        super.init()
        if !LifeLoadWallpaperABI() {
            wallpaperLog.error("WallpaperExtensionKit ABI was unavailable or failed its layout checks.")
        }
    }
}
