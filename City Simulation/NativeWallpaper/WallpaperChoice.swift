import CityEngine

let wallpaperChoice = WallpaperChoice(
    id: "city-simulation",
    name: "City Simulation",
    description: "An isometric pixel-art city that grows over time",
    bundleID: "io.github.thomasturrell.live-simulation-wallpapers.city.wallpaper.Extension",
    thumbnail: "city-thumbnail",
    options: [
        .picker(MenuPickerOption(
            id: "environment",
            localizedLabel: "Environment",
            defaultValueID: EnvironmentMode.simulationWorld.rawValue,
            items: EnvironmentMode.allCases.map {
                .item(MenuPickerItem(id: $0.rawValue, localizedName: $0.title, isDownloaded: true))
            }
        ))
    ]
)
