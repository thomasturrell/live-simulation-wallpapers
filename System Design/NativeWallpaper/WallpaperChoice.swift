import DesignArt
import DesignEngine

private func picker(_ id: String, _ label: String, _ selected: String, _ items: [(String, String)]) -> WallpaperOption {
    .picker(MenuPickerOption(id: id, localizedLabel: label, defaultValueID: selected,
                             items: items.map { .item(MenuPickerItem(id: $0.0, localizedName: $0.1, isDownloaded: true)) }))
}

let wallpaperChoice = WallpaperChoice(
    id: "system-design", name: "System Design",
    description: "Explore the relationships that give real systems their shape",
    bundleID: "io.github.thomasturrell.live-simulation-wallpapers.design.wallpaper.Extension",
    thumbnail: "design-thumbnail",
    options: [
        picker("explore", "Explore", "all", [("all", "Entire catalogue")] + Subject.allCases.map { ($0.rawValue, $0.title) }
               + Catalogue.bundled.graphs.sorted { $0.name < $1.name }.map { ($0.id, $0.name) }),
        picker("appearance", "Appearance", Appearance.system.rawValue,
               Appearance.allCases.map { ($0.rawValue, $0 == .system ? "Automatic" : $0.rawValue) }),
        picker("colour", "Colour", Colour.green.id, Colour.allCases.map { ($0.id, $0.title) }),
        picker("tilt", "Rotation", "varied", DesignStyle.Tilt.allCases.map { ($0.rawValue, $0.rawValue.capitalized) }),
        picker("framing", "Framing", "balanced", DesignStyle.Framing.allCases.map { ($0.rawValue, $0.rawValue.capitalized) })
    ] + [("descriptions", "Node descriptions"), ("relationships", "Relationship labels"), ("groups", "Group names")].map {
        picker($0.0, $0.1, "show", [("show", "Show"), ("hide", "Hide")])
    }
)
