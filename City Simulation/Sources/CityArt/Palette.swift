import Foundation
import CityEngine

struct Palette {
    let night: Double
    var environment: EnvironmentFrame? = nil
    var skin: CitySkin = .original
    var weather: EnvironmentalWeather { environment?.weather ?? .init() }
    var season: SeasonAppearance { environment?.season ?? SeasonAppearance.months[5] }
    var snow: Ink { color(0xDFE5DC, 0x7D8B9F) }

    func color(_ day: UInt32, _ dark: UInt32? = nil) -> Ink {
        Ink(day).mix(Ink(dark ?? 0x202944), night * (dark == nil ? 0.70 : 1))
            .mix(Ink(night > 0.5 ? 0x384458 : 0x7B8C96), weather.cloud * 0.10)
    }

    func grass(_ style: Int) -> Ink {
        let variation = Double(style % 6) / 45
        let lawn = color(season.grassColor, 0x34494A)
        let turf = skin == .contemporary ? lawn.mix(color(0x426B58, 0x2B4046), 0.43) : lawn
        return turf.mix(color(0xB4B183, 0x50605B), variation)
            .mix(color(0x4D715C, 0x2E424B), weather.rain * 0.15).mix(snow, weather.snowCover * 0.84)
    }

    func roof(_ rgb: UInt32) -> Ink { color(rgb).mix(snow, weather.snowCover * 0.85) }

    var asphalt: Ink { color(skin == .contemporary ? 0x485464 : 0x555963, 0x262C41).mix(color(0x3F505F, 0x202B40), weather.rain * 0.55) }
    var roadEdge: Ink { color(0x40474F, 0x1D2536) }
    var whiteRoadPaint: Ink { color(0xE9E8E2, 0xA7ADB9) }
    var yellowRoadPaint: Ink { color(0xC6B58A, 0x81775E) }
    var curb: Ink { color(0xB7AA94, 0x535468) }
    var sidewalk: Ink { color(skin == .contemporary ? 0x9DA5A5 : 0x9A9487, 0x414659) }
    var water: Ink { color(skin == .contemporary ? 0x296780 : 0x427982, 0x21394F) }
    var waterDark: Ink { color(skin == .contemporary ? 0x255970 : 0x376D78, 0x192F45) }
    var waterLight: Ink { color(skin == .contemporary ? 0x54879A : 0x609294, 0x2F4558) }
    var shore: Ink { color(0xCAC2A0, 0x666574) }
    var shadow: Ink { color(skin == .contemporary ? 0x526A52 : 0x65784D, 0x26353C) }
    var paths: Ink { color(0xBCAB7E, 0x525161) }
    var foliage: Ink { color(0x496F50, 0x263A43) }
    var leafShade: Ink { color(0x355247, 0x202E3B) }
    var clay: Ink { color(0xA45E4C, 0x513848) }
    var gold: Ink { color(0xF3D287, 0xFFD88C) }
    var outline: Ink { color(0x434B50, 0x202536) }
}
