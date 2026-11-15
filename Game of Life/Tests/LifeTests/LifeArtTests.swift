import Foundation
import CoreGraphics
import Testing
@testable import LifeArt

@Test(arguments: [CGSize(width: 5120, height: 1440), CGSize(width: 1080, height: 1920),
                  CGSize(width: 1440, height: 900)], [-20.0, 0, 12, 20])
func rotatedGridCoversAllCorners(viewport: CGSize, angle: Double) {
    var settings = LifeSettings()
    settings.size = LifeSettings.sizeRange.lowerBound
    settings.spacing = LifeSettings.spacingRange.lowerBound
    settings.angle = angle
    let layout = LifeLayout(viewport: viewport, settings: settings)
    let corners = [CGPoint.zero, CGPoint(x: viewport.width, y: 0),
                   CGPoint(x: 0, y: viewport.height), CGPoint(x: viewport.width, y: viewport.height)]
    for corner in corners {
        let point = corner.applying(layout.transform.inverted())
        let x = Int(floor(point.x / layout.pitch))
        let y = Int(floor(point.y / layout.pitch))
        #expect(x > 0 && x < layout.columns - 1)
        #expect(y > 0 && y < layout.rows - 1)
        #expect(layout.visibleX.contains(x))
        #expect(layout.visibleY.contains(y))
    }
}

@Test func persistsSettingsAndValidatesStoredValues() {
    // An isolated suite exercises persistence without touching app preferences.
    let domain = "test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    #expect(LifeSettings(defaults: defaults).colour == .original)
    var settings = LifeSettings()
    settings.speed = 2.5
    settings.size = 9
    settings.spacing = 3
    settings.angle = -10
    settings.injection = 0
    settings.appearance = .dark
    settings.colour = .green
    settings.paused = true
    settings.seed = UInt64.max
    settings.save(to: defaults)
    defer { defaults.removePersistentDomain(forName: domain) }
    #expect(LifeSettings(defaults: defaults) == settings)
    defaults.set(-5.0, forKey: "speed")
    defaults.set("unknown", forKey: "appearance")
    defaults.set("unknown", forKey: "colour")
    let restored = LifeSettings(defaults: defaults)
    #expect(restored.speed == LifeSettings().speed)
    #expect(restored.appearance == .system)
    #expect(restored.colour == .original)
    #expect(restored.seed == UInt64.max)
}

@Test func recolouringChangesTheSnapshotWithoutReseeding() throws {
    var settings = LifeSettings()
    let size = CGSize(width: 200, height: 120)
    var scene = LifeScene(viewport: size, settings: settings)
    scene.advance(by: 1)
    let world = try PropertyListEncoder().encode(scene.checkpoint)
    let initialImage = try #require(scene.image(scale: 1, dark: true)?.dataProvider?.data)

    settings.colour = .green
    scene.configure(viewport: size, settings: settings)
    let greenImage = try #require(scene.image(scale: 1, dark: true)?.dataProvider?.data)
    let recolouredWorld = try PropertyListEncoder().encode(scene.checkpoint)
    #expect(recolouredWorld == world)
    #expect(greenImage as Data != initialImage as Data)
}

@Test func spectrumCyclesAndRandomHoldsItsColourWithinACycle() {
    func background(_ colour: LifeColour, at generation: Int) -> [CGColor] {
        LifePalette(darkness: 1, colour: colour, generation: generation, seed: 42).background
    }
    #expect(background(.spectrum, at: 0) == background(.green, at: 0))
    #expect(background(.spectrum, at: 20) != background(.green, at: 20))
    #expect(background(.spectrum, at: 40) == background(.yellow, at: 40))
    #expect(background(.spectrum, at: 240) == background(.green, at: 240))
    #expect(background(.random, at: 0) == background(.random, at: 239))
    #expect(background(.random, at: 0) != background(.random, at: 240))
}

@Test func snapshotHasRetinaDimensionsAndDoesNotAdvanceWorld() throws {
    let scene = LifeScene(viewport: CGSize(width: 393, height: 241), settings: LifeSettings())
    let generation = scene.world.generation
    let image = try #require(scene.image(scale: 2, dark: true))
    #expect(image.width == 786)
    #expect(image.height == 482)
    #expect(scene.world.generation == generation)
}

@Test func reproducibleCompositionAndIndependentRender() throws {
    let size = CGSize(width: 760, height: 410)
    var a = LifeScene(viewport: size, settings: LifeSettings())
    var b = LifeScene(viewport: size, settings: LifeSettings())
    for _ in 0..<35 {
        _ = a.image(scale: 1, dark: true)
        a.advance(by: 0.8)
        b.advance(by: 0.8)
    }
    let first = try #require(a.image(scale: 1, dark: false)?.dataProvider?.data)
    let second = try #require(b.image(scale: 1, dark: false)?.dataProvider?.data)
    #expect(first as Data == second as Data)
}

@Test func checkpointRestoresEvolutionAndPatternInjection() throws {
    let settings = LifeSettings()
    let size = CGSize(width: 720, height: 450)
    var original = LifeScene(viewport: size, settings: settings)
    for _ in 0..<19 { original.advance(by: 1) }
    let saved = try PropertyListEncoder().encode(original.checkpoint)
    let decoded = try PropertyListDecoder().decode(LifeScene.Checkpoint.self, from: saved)
    var restored = try #require(LifeScene(checkpoint: decoded, settings: settings))
    #expect(restored.world.generation == original.world.generation)

    for _ in 0..<28 {
        let originalCheckpoint = try PropertyListEncoder().encode(original.checkpoint)
        let restoredCheckpoint = try PropertyListEncoder().encode(restored.checkpoint)
        #expect(originalCheckpoint == restoredCheckpoint)
        original.advance(by: 1)
        restored.advance(by: 1)
    }
}
