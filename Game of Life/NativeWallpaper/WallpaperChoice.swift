import LifeArt

let lifeColourOptionID = "colorScheme"

let wallpaperChoice = WallpaperChoice(
    id: "game-of-life",
    name: "Game of Life",
    description: "Conway’s Game of Life",
    bundleID: "io.github.thomasturrell.live-simulation-wallpapers.life.wallpaper.Extension",
    thumbnail: "life-thumbnail",
    options: [.picker(MenuPickerOption(
        id: lifeColourOptionID,
        localizedLabel: "Colour",
        defaultValueID: LifeColour.original.id,
        items: LifeColour.allCases.map {
            .item(MenuPickerItem(id: $0.id, localizedName: $0.title, isDownloaded: true))
        }
    ))]
)

extension Presentation {
    var colour: LifeColour? { optionIDs[lifeColourOptionID].flatMap(LifeColour.init(rawValue:)) }
}
