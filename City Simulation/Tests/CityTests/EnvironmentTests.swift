@testable import CityArt
@testable import CityEngine
import CoreGraphics
import Foundation
import Testing

private func utc(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
private let utcZone = TimeZone(secondsFromGMT: 0)!

@Test func environmentHasExactlyThreeChoicesAndDefaultsToSimulation() throws {
    #expect(EnvironmentMode.allCases.map(\.title) == ["Simulation World", "Real World · Northern Hemisphere", "Real World · Southern Hemisphere"])
    #expect(Environment.frame(city: City()) == Environment.frame(city: City(), mode: .simulationWorld))
    for mode in EnvironmentMode.allCases {
        #expect(try JSONDecoder().decode(EnvironmentMode.self, from: JSONEncoder().encode(mode)) == mode)
    }
}

@Test func realCalendarUsesAllTwelveMonthStartsAndInterpolatesLeapYears() {
    for month in 1...12 {
        let date = utc(String(format: "2024-%02d-01T00:00:00Z", month))
        #expect(Environment.realMonth(at: date, timeZone: utcZone) == Double(month - 1))
    }
    #expect(abs(Environment.realMonth(at: utc("2024-02-15T12:00:00Z"), timeZone: utcZone) - 1.5) < 1e-8)
    #expect(Environment.realMonth(at: utc("2024-12-31T12:00:00Z"), timeZone: TimeZone(secondsFromGMT: 12 * 3600)!) == 0)
}

@Test func seasonalArtworkIsContinuousAtEveryMonthIncludingNewYear() {
    for month in 0...12 {
        let before = SeasonAppearance.at(month: Double(month) - 0.0001)
        let after = SeasonAppearance.at(month: Double(month) + 0.0001)
        #expect(abs(before.foliage - after.foliage) < 0.001 && abs(before.blossom - after.blossom) < 0.001)
        #expect(before.leafColor == after.leafColor && before.grassColor == after.grassColor)
    }
    #expect(SeasonAppearance.months[0].foliage < 0.05 && SeasonAppearance.months[5].foliage == 1)
    #expect(SeasonAppearance.at(month: 2.5).foliage > SeasonAppearance.months[2].foliage)
}

@Test func realHemispheresShiftTheSameSeasonalArtworkBySixMonths() {
    let city = City()
    for month in 1...12 {
        let date = utc(String(format: "2026-%02d-01T00:00:00Z", month))
        let north = Environment.frame(city: city, mode: .realWorldNorthern, date: date, timeZone: utcZone)
        let south = Environment.frame(city: city, mode: .realWorldSouthern, date: date, timeZone: utcZone)
        #expect(north.month == Double(month - 1))
        #expect(south.month == Environment.wrap(north.month + 6, length: 12))
        #expect(south.season == SeasonAppearance.at(month: north.month + 6))
    }
}

@Test func fictionalYearRetainsEightMinuteDaysAndFourTwoDaySeasons() {
    #expect(Environment.yearTicks / City.ticksPerSecond == 64 * 60)
    for day in 0..<16 {
        #expect(Environment.simulationMonth(tick: day * City.dayLength) == Double(day % 8) / 2)
        #expect(SimulatedWeather.season(at: day * City.dayLength) == Season.allCases[day % 8 / 2])
    }
    #expect(Environment.calendarLabel(tick: City.dayLength * 7).contains("Month 4 · Day 2"))
    #expect(Environment.calendarLabel(tick: Environment.yearTicks).contains("Year 2 · Month 1 · Day 1"))
    #expect(Environment.frame(city: City()).month == 2 && Environment.frame(city: City()).darkness == City().darkness)
}

@Test func realWorldUsesSystemAppearanceAndNeutralDryWeatherThroughoutTheYear() {
    for mode in [EnvironmentMode.realWorldNorthern, .realWorldSouthern] {
        for month in 1...12 {
            let city = City(seed: UInt64(month))
            let noon = utc(String(format: "2026-%02d-01T12:00:00Z", month))
            let midnight = utc(String(format: "2026-%02d-01T00:00:00Z", month))
            let dark = Environment.frame(city: city, mode: mode, date: noon, systemDark: true)
            let light = Environment.frame(city: city, mode: mode, date: midnight, systemDark: false)
            #expect(dark.darkness == 1 && light.darkness == 0)
            #expect(dark.weather == EnvironmentalWeather() && light.weather == EnvironmentalWeather())
        }
    }
}

@Test func inactiveRealWorldRecomputesSeasonWhileFictionalTimeStaysFrozen() {
    let city = City(), january = utc("2026-01-01T00:00:00Z"), july = utc("2026-07-01T00:00:00Z")
    let winter = Environment.frame(city: city, mode: .realWorldNorthern, date: january, timeZone: utcZone)
    let summer = Environment.frame(city: city, mode: .realWorldNorthern, date: july, timeZone: utcZone)
    #expect(winter.season.foliage < summer.season.foliage)
    #expect(Environment.frame(city: city, date: january) == Environment.frame(city: city, date: july))
}

@Test(arguments: Season.allCases)
func seasonalPercentagesTotalOneHundredAndSelectExactProportions(season: Season) {
    let p = season.weatherProbabilities
    #expect(p.total == 100)
    let selections = (0..<100).map { p.condition(for: $0) }
    #expect(selections.filter { $0 == .clear }.count == p.clear)
    #expect(selections.filter { $0 == .cloudy }.count == p.cloudy)
    #expect(selections.filter { $0 == .rain }.count == p.rain)
    #expect(selections.filter { $0 == .snow }.count == p.snow)
    #expect(Season.summer.weatherProbabilities.snow == 0)
    #expect(Season.winter.weatherProbabilities.snow > Season.autumn.weatherProbabilities.snow && Season.winter.weatherProbabilities.snow < 100)
    #expect(Season.autumn.weatherProbabilities.rain > Season.summer.weatherProbabilities.rain)
}

@Test(arguments: WeatherKind.allCases)
func zeroProbabilityConditionsAreNeverSelected(onlyCondition: WeatherKind) {
    let probabilities = WeatherProbabilities(clear: onlyCondition == .clear ? 100 : 0, cloudy: onlyCondition == .cloudy ? 100 : 0,
                                            rain: onlyCondition == .rain ? 100 : 0, snow: onlyCondition == .snow ? 100 : 0)
    #expect((0..<100).allSatisfy { probabilities.condition(for: $0) == onlyCondition })
}

@Test(arguments: Season.allCases)
func spellsUseSeasonalProbabilitiesAndIndependentWind(season: Season) {
    let slot = (season.rawValue * City.dayLength * 2 + SimulatedWeather.period - 1) / SimulatedWeather.period + 2
    #expect(SimulatedWeather.season(at: slot * SimulatedWeather.period) == season)
    let spells = (0..<2000).map { SimulatedWeather.target(slot: slot, seed: UInt64($0)) }
    let p = season.weatherProbabilities
    for (kind, percent) in [(WeatherKind.clear, p.clear), (.cloudy, p.cloudy), (.rain, p.rain), (.snow, p.snow)] {
        let matching = spells.filter { $0.kind == kind }
        if percent == 0 { #expect(matching.isEmpty) }
        else {
            #expect(abs(Double(matching.count) / 20 - Double(percent)) < 4)
            #expect(matching.contains { $0.wind < 0.2 } && matching.contains { $0.wind > 0.7 })
        }
    }
    #expect(spells.allSatisfy { $0.isValid })
}

@Test func weatherSpellsHoldConditionsAndBlendContinuouslyAcrossBoundaries() {
    for seed in 0..<30 {
        for slot in 1..<60 {
            let tick = slot * SimulatedWeather.period
            let before = SimulatedWeather.at(tick: tick - 1, seed: UInt64(seed))
            let start = SimulatedWeather.at(tick: tick, seed: UInt64(seed))
            #expect(abs(before.cloud - start.cloud) < 0.004 && abs(before.rain - start.rain) < 0.004)
            #expect(abs(before.snow - start.snow) < 0.004 && abs(before.snowCover - start.snowCover) < 0.004 && abs(before.wind - start.wind) < 0.004)
            let settled = SimulatedWeather.at(tick: tick + SimulatedWeather.transition, seed: UInt64(seed))
            let later = SimulatedWeather.at(tick: tick + SimulatedWeather.period - 1, seed: UInt64(seed))
            let target = SimulatedWeather.target(slot: slot, seed: UInt64(seed))
            #expect(settled.kind == target.kind && settled.wind == target.wind)
            #expect(settled.cloud == later.cloud && settled.rain == later.rain && settled.snow == later.snow && settled.wind == later.wind)
            #expect(start.isValid && settled.isValid && later.isValid)
        }
    }
}

@Test func summerHasNoSnowAndWinterSnowIsNotGuaranteed() {
    for seed in 0..<50 {
        for tick in stride(from: City.dayLength * 2, to: City.dayLength * 4, by: 101) {
            let weather = SimulatedWeather.at(tick: tick, seed: UInt64(seed))
            #expect(weather.snow == 0 && weather.snowCover == 0)
        }
    }
    let slot = City.dayLength * 6 / SimulatedWeather.period + 1
    #expect(Set((0..<100).map { SimulatedWeather.target(slot: slot, seed: UInt64($0)).kind }) == Set(WeatherKind.allCases))
}

@Test func snowCoverThawsAfterTheFlakesStop() throws {
    let slot = City.dayLength * 6 / SimulatedWeather.period + 2
    let seed = try #require((0..<1000).map { UInt64($0) }.first {
        SimulatedWeather.target(slot: slot - 1, seed: $0).snowCover > 0 && SimulatedWeather.target(slot: slot, seed: $0).snowCover == 0
    })
    let tick = slot * SimulatedWeather.period
    let start = SimulatedWeather.at(tick: tick, seed: seed)
    let afterBlend = SimulatedWeather.at(tick: tick + SimulatedWeather.transition, seed: seed)
    let middle = SimulatedWeather.at(tick: tick + SimulatedWeather.period / 2, seed: seed)
    let end = SimulatedWeather.at(tick: tick + SimulatedWeather.period - 1, seed: seed)
    #expect(afterBlend.snow == 0 && afterBlend.snowCover > 0)
    #expect(start.snowCover > afterBlend.snowCover && afterBlend.snowCover > middle.snowCover && middle.snowCover > end.snowCover)
    #expect(end.snowCover < 0.001)
}

@Test func environmentPersistsThroughSuspensionSettlingRestartAndModeChanges() throws {
    var city = City(seed: 99)
    for _ in 0..<(SimulatedWeather.period + SimulatedWeather.transition / 2) { city.step() }
    var playback = Playback(city: city)
    let simulated = Environment.frame(city: city)
    for mode in EnvironmentMode.allCases { _ = Environment.frame(city: city, mode: mode) }
    #expect(playback.city == city && Environment.frame(city: city) == simulated)
    let restored = try #require(City(checkpoint: city.checkpoint()))
    #expect(restored == city && Environment.frame(city: restored) == simulated)
    playback.present(visible: false, animated: true)
    playback.advance(elapsed: 86_400)
    #expect(Environment.frame(city: playback.city) == simulated && !playback.needsTimer)
    playback.present(visible: true, animated: true)
    playback.advance(elapsed: 0.1)
    #expect(playback.city.tick == city.tick + 3)
    playback.present(visible: true, animated: false)
    let moving = playback.city.tick
    for _ in 0..<16 { playback.advance(elapsed: 0.25) }
    #expect(playback.city.tick == moving + 40 && !playback.needsTimer)
    let settled = playback.city
    playback.advance(elapsed: 100)
    #expect(playback.city == settled)
    var resumed = try #require(City(checkpoint: settled.checkpoint()))
    var continuous = settled
    for _ in 0..<120 { resumed.step(); continuous.step() }
    #expect(resumed == continuous && Environment.frame(city: resumed) == Environment.frame(city: continuous))
}

@Test func checkpointsRequireTheCurrentCompleteSchema() throws {
    var plist = try #require(PropertyListSerialization.propertyList(from: City().checkpoint(), format: nil) as? [String: Any])
    var fields = try #require(plist["city"] as? [String: Any])
    fields.removeValue(forKey: "environmentSeed"); plist["city"] = fields
    #expect(City(checkpoint: try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)) == nil)
}

@Test func cityPreviewOverridesMonthLightingWeatherAndWindWithoutStepping() throws {
    let city = City(), data = try city.checkpoint()
    var preview = EnvironmentPreview()
    preview.month = 2.5; preview.darkness = 1; preview.weather = .snow; preview.wind = 0.9
    let frame = Environment.frame(city: city, preview: preview)
    #expect(frame.month == 6.5 && frame.darkness == 1 && frame.weather.kind == .snow && frame.weather.wind == 0.9)
    #expect(Environment.frame(city: city, mode: .realWorldNorthern, preview: preview).month == 1.5)
    #expect(Environment.frame(city: city, mode: .realWorldSouthern, preview: preview).month == 7.5)
    #expect(try city.checkpoint() == data)
}

@Test func vegetationLosesFoliageWhileEvergreensKeepTheirSilhouette() {
    func sprite(month: Double, style: Int) -> [UInt32] {
        var preview = EnvironmentPreview(); preview.month = month; preview.weather = .clear; preview.darkness = 0
        let frame = Environment.frame(city: City(), mode: .realWorldNorthern, preview: preview)
        var pixels = Pixels(width: 32, height: 32, background: Ink(0))
        pixels.tree(at: Dot(16, 25), style: style, palette: Palette(night: 0, environment: frame))
        return pixels.storage
    }
    let winter = sprite(month: 1, style: 22), summer = sprite(month: 7, style: 22), empty = Ink(0).pixel
    #expect(summer.filter { $0 != empty }.count > winter.filter { $0 != empty }.count * 2)
    #expect(sprite(month: 1, style: 5) == sprite(month: 7, style: 5))
    #expect(sprite(month: 4, style: 16) != sprite(month: 7, style: 16))
}

@Test func allModesAndWeatherVariationsRenderAndInvalidateCachedFrames() throws {
    let city = City(), renderer = CityRenderer(), viewport = CityViewport(pixelWidth: 320, pixelHeight: 180)
    let checkpoint = try city.checkpoint()
    var images: Set<Data> = []
    for mode in EnvironmentMode.allCases {
        for month in mode.isSimulation ? [1.0, 2, 3, 4] : [1.0, 4, 7, 10] {
            for kind in WeatherKind.allCases {
                for darkness in [0.0, 1.0] {
                    for wind in [0.0, 0.9] {
                        var preview = EnvironmentPreview(); preview.month = month; preview.weather = kind; preview.darkness = darkness; preview.wind = wind
                        let frame = Environment.frame(city: city, mode: mode, preview: preview)
                        let image = renderer.image(for: city, viewport: viewport, environment: frame)
                        #expect(renderer.image(for: city, viewport: viewport, environment: frame) === image)
                        images.insert(try #require(image.dataProvider?.data) as Data)
                    }
                }
            }
        }
    }
    #expect(images.count > 80)
    #expect(try city.checkpoint() == checkpoint)
}

@Test func tinyWeatherCanvasesAndCloudEdgesAreClippedSafely() {
    let city = City()
    for kind in WeatherKind.allCases {
        for tick in [0, 1, 200, 10000] {
            for width in [1, 2, 47] {
                var pixels = Pixels(width: width, height: 1, background: Ink(0x777777))
                var preview = EnvironmentPreview(); preview.weather = kind; preview.wind = 0.9
                pixels.weatherEffects(tick: tick, palette: Palette(night: 0, environment: Environment.frame(city: city, preview: preview)))
                #expect(pixels.storage.count == width)
            }
        }
    }
}
