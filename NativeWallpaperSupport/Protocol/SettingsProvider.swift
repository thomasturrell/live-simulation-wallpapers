// Adapted from Aerial, MIT. See Protocol/LICENSE.
// One picker entry serves every display. The extension uses
// `directDisplayID` at acquire time to render the correct world.

import AppKit
import Foundation

struct WallpaperChoice {
    let id: String
    let name: String
    let description: String
    let bundleID: String
    let thumbnail: String
    var options: [WallpaperOption] = []
}

func buildSettingsViewModelsXPC(thumbnail: URL? = nil) -> AnyObject? {
    let bundleID = Bundle.main.bundleIdentifier ?? wallpaperChoice.bundleID
    // Both extensions contribute their own choice to the same Settings section.
    let groupID = GroupID(id: "io.github.thomasturrell.live-simulation-wallpapers")

    guard let thumbnailURL = thumbnail ?? bundledThumbnailURL() else {
        debugLog("  [Settings] Failed to generate thumbnail")
        return makeEmptyGroupsResponse()
    }

    let choiceID = ChoiceID(
        id: wallpaperChoice.id,
        descriptor: ChoiceIDDescriptor(
            provider: ChoiceProviderID(rawValue: bundleID),
            identifier: wallpaperChoice.id,
            files: [],
            configuration: Data(wallpaperChoice.id.utf8),
        ),
    )

    let choiceDescriptor = ChoiceDescriptor(
        id: choiceID,
        provider: ChoiceProviderID(rawValue: bundleID),
        identifier: wallpaperChoice.id,
        name: wallpaperChoice.name,
        localizedDescription: wallpaperChoice.description,
        thumbnail: .image(url: thumbnailURL),
        isDownloaded: true,
        options: wallpaperChoice.options,
    )

    let item = SettingsItem(
        id: choiceID,
        localizedName: wallpaperChoice.name,
        thumbnail: .image(url: thumbnailURL),
        choice: choiceDescriptor,
        contentBadge: .dynamic,
        showInTopLevel: true,
        sortOrder: 0,
        disposability: .none,
    )

    let group = SettingsGroup(
        id: groupID,
        items: [item],
        localizedName: "Simulation Wallpapers",
        disposability: .none,
        sortOrder: -50,
        sortID: GroupSortID(id: "com.apple.wallpaper.aerials"),
        allChoiceID: nil,
        shouldHideItemLabels: false,
        contextMenu: nil,
        thumbnail: nil,
    )

    let viewModel = SettingsViewModel(
        groups: [group],
        refreshPolicy: .default,
        isModificationDisabled: false,
    )

    // The same group and item appear in both the Wallpaper picker
    // and the Screen Saver picker. WallpaperAgent's discovery uses the
    // non-nil `screenSaver:` field as the eligibility signal — Apple's
    // own WallpaperAerialsExtension does the same (Phosphene leaves it
    // nil and is wallpaper-only by choice).
    let viewModels = SettingsViewModels(
        desktop: viewModel,
        screenSaver: viewModel,
    )

    return remapToRealXPC(viewModels)
}

/// Fallback: empty groups view model.
func makeEmptyGroupsResponse() -> AnyObject? {
    let emptyViewModel = SettingsViewModel(
        groups: [],
        refreshPolicy: .default,
        isModificationDisabled: false,
    )
    let empty = SettingsViewModels(
        desktop: emptyViewModel,
        screenSaver: emptyViewModel,
    )
    return remapToRealXPC(empty)
}

/// Archive via ShimViewModelsXPC, remap class name on unarchive to WallpaperSettingsViewModelsXPC.
private func remapToRealXPC(_ viewModels: SettingsViewModels) -> AnyObject? {
    let shim = ShimViewModelsXPC(value: viewModels)

    let data: Data
    do {
        data = try NSKeyedArchiver.archivedData(withRootObject: shim, requiringSecureCoding: false)
    } catch {
        debugLog("  [Remap] Archive failed: \(error)")
        return nil
    }

    guard let realClass = objc_getClass("WallpaperSettingsViewModelsXPC") as? AnyClass else {
        debugLog("  [Remap] WallpaperSettingsViewModelsXPC class not found")
        return nil
    }

    guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else {
        debugLog("  [Remap] Failed to create unarchiver")
        return nil
    }
    unarchiver.requiresSecureCoding = false
    unarchiver.decodingFailurePolicy = .setErrorAndReturn
    unarchiver.setClass(realClass, forClassName: "ShimViewModelsXPC")

    let result = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
    if let error = unarchiver.error {
        debugLog("  [Remap] Unarchive error: \(error)")
    }
    unarchiver.finishDecoding()

    return result as AnyObject?
}

/// Stage the bundled wallpaper thumbnail into the Caches directory and return its URL.
/// (System Settings reads this URL; staging to our Caches dir matches the location the
/// previous generated thumbnail used and is known to be readable by WallpaperAgent.)
private func bundledThumbnailURL() -> URL? {
    let fm = FileManager.default
    guard let src = Bundle.main.url(forResource: wallpaperChoice.thumbnail, withExtension: "png") else {
        debugLog("  [Settings] Bundled thumbnail not found")
        return nil
    }
    guard let cacheDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else {
        return src
    }
    try? fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    let dst = cacheDir.appendingPathComponent("\(wallpaperChoice.thumbnail)-photo.png")
    do {
        let data = try Data(contentsOf: src)
        if (try? Data(contentsOf: dst)) != data { try data.write(to: dst, options: .atomic) }
        return dst
    } catch {
        debugLog("  [Settings] Failed to stage thumbnail: \(error)")
        return src
    }
}
