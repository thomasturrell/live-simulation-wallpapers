import LifeArt

let lifeAppearanceOptionID = "appearanceMode"
let lifeColourOptionID = "colorScheme"

let wallpaperChoice = WallpaperChoice(
    id: "game-of-life",
    name: "Game of Life",
    description: "Conway’s Game of Life",
    bundleID: "io.github.thomasturrell.live-simulation-wallpapers.life.wallpaper.Extension",
    thumbnail: "life-thumbnail",
    options: [
        .picker(MenuPickerOption(
            id: lifeAppearanceOptionID,
            localizedLabel: "Appearance",
            defaultValueID: LifeAppearance.system.wallpaperID,
            items: LifeAppearance.allCases.map {
                .item(MenuPickerItem(id: $0.wallpaperID, localizedName: $0 == .system ? "Automatic" : $0.rawValue,
                                     isDownloaded: true))
            }
        )),
        .picker(MenuPickerOption(
            id: lifeColourOptionID,
            localizedLabel: "Colour",
            defaultValueID: LifeColour.original.id,
            items: LifeColour.allCases.map {
                .item(MenuPickerItem(id: $0.id, localizedName: $0.title, isDownloaded: true))
            }
        ))
    ]
)

extension LifeAppearance {
    var wallpaperID: String { self == .system ? "automatic" : rawValue.lowercased() }
}

extension Presentation {
    var appearance: LifeAppearance? {
        guard let id = optionIDs[lifeAppearanceOptionID] else { return nil }
        return LifeAppearance.allCases.first { $0.wallpaperID == id }
    }

    var colour: LifeColour? { optionIDs[lifeColourOptionID].flatMap(LifeColour.init(rawValue:)) }
}
