import AppKit
import Testing
@testable import DesignArt
@testable import DesignEngine

@Test @MainActor func connectionsAppearOnlyAsTheDiagramBuilds() throws {
    let graph = try #require(Catalogue.bundled["flywheel-storage"])
    // Both directions of the initial power exchange share the same two endpoints.
    let visit = Visit(system: graph.id, entry: "grid-connection", seed: 42, linkedEntry: false)
    let chapter = Chapter(visit, recent: [graph.id], scope: graph.id, catalogue: .bundled)
    let style = DesignStyle()
    let size = CGSize(width: 960, height: 600)
    let camera = DiagramCamera(size: size, style: style, displaySeed: 42)
    let layout = DiagramLayout(chapter: chapter, style: style, camera: camera)
    let scene = DiagramScene(chapter: chapter, layout: layout, style: style,
                             ink: Ink(style: style, dark: false, generation: 0, seed: 42))
    let canvas = try #require(scene.layer.sublayers?.first)
    let strokes = (canvas.sublayers ?? []).compactMap { $0 as? CAShapeLayer }.filter { layer in
        layout.routes.contains { $0.path == layer.path }
    }
    scene.display(camera: camera, beat: 0, progress: 0)
    #expect(strokes.filter { $0.strokeEnd > 0 }.count == 1)
    scene.display(camera: camera, beat: 1, progress: Chapter.revealEnd / 2)
    #expect(strokes.filter { $0.strokeEnd == 1 }.count == 1)
    #expect(strokes.filter { $0.strokeEnd > 0 && $0.strokeEnd < 1 }.count >= 2)
    scene.display(camera: camera, beat: chapter.lastBeat - 1, progress: 1)
    #expect(strokes.filter { $0.strokeEnd == 1 }.count == graph.edges.count)
}

@Test @MainActor func systemLabelIsOptInOnBothSidesOfAHandoff() throws {
    var world = Exploration(seed: 136)
    world.advance(world.chapter.lastBeat * (world.chapter.beatTicks + 1) + world.chapter.beatTicks / 8)
    let checkpoint = try world.checkpoint()
    let graphs = [world.chapter.graph, world.incomingChapter().graph]
    let renderer = DesignRenderer()
    var style = DesignStyle()
    func text(in layer: CALayer) -> [String] {
        let string = ((layer as? CATextLayer)?.string as? NSAttributedString)?.string
        return [string].compactMap { $0 } + (layer.sublayers ?? []).flatMap(text)
    }
    func check(_ visible: Bool) throws {
        renderer.draw(world, size: CGSize(width: 960, height: 600), scale: 1, style: style, systemDark: false)
        let sheets = try #require(renderer.artwork.sublayers)
        #expect(sheets.count == graphs.count)
        for (sheet, graph) in zip(sheets, graphs) {
            let labels = text(in: sheet)
            #expect(labels.contains(graph.name) == visible)
            #expect(labels.contains(graph.category.title.uppercased()) == visible)
            #expect(graph.nodes.allSatisfy { labels.contains($0.name) })
        }
    }
    try check(false)
    style.apply(["systemLabel": "show"])
    style.apply(["colour": "blue"])
    try check(true)
    style.apply(["systemLabel": "hide"])
    try check(false)
    #expect(try world.checkpoint() == checkpoint)
}

@Test @MainActor func boundsRoutesAndLabelsRespectComponentGeometry() {
    for graph in Catalogue.bundled.graphs {
        let chapter = Exploration(seed: 42, scope: graph.id).chapter
        let camera = DiagramCamera(size: CGSize(width: 960, height: 600), style: DesignStyle(), displaySeed: 42)
        let layout = DiagramLayout(chapter: chapter, style: DesignStyle(), camera: camera)
        let nodeBounds = Array(layout.nodes.values)
        for (i, rect) in nodeBounds.enumerated() {
            #expect(!nodeBounds.dropFirst(i + 1).contains { $0.intersects(rect) }, "\(graph.id) node collision")
        }
        for (i, edge) in graph.edges.enumerated() {
            let route = layout.routes[i]
            let a = route.point(at: 0), b = route.point(at: 1)
            #expect(layout.nodes[edge.source]!.insetBy(dx: -1, dy: -1).contains(a))
            #expect(layout.nodes[edge.target]!.insetBy(dx: -1, dy: -1).contains(b))
            for node in graph.nodes where node.id != edge.source && node.id != edge.target {
                #expect(!route.intersects(layout.nodes[node.id]!.insetBy(dx: 1, dy: 1)), "\(graph.id) \(edge.label) crosses \(node.id)")
            }
        }
        let labels = layout.labels.compactMap { $0 }
        #expect(!labels.isEmpty)
        for (i, label) in labels.enumerated() {
            #expect(!nodeBounds.contains { $0.intersects(label) })
            #expect(!labels.dropFirst(i + 1).contains { $0.intersects(label) })
        }
        for group in graph.groups {
            let bounds = layout.groups[group.id]!
            #expect(layout.members[group.id]!.allSatisfy { bounds.contains(layout.nodes[$0]!) })
            if let parent = group.parent { #expect(layout.groups[parent]!.contains(bounds)) }
        }
    }
}

@Test @MainActor func stationaryFramesReuseLayersAndAppearanceChangesOnlyTheArtwork() throws {
    let renderer = DesignRenderer()
    let world = Exploration(seed: 42, scope: "domestic-solar-power")
    let state = try world.checkpoint()
    var style = DesignStyle()
    let size = CGSize(width: 720, height: 480)
    renderer.draw(world, size: size, scale: 1, style: style, systemDark: false)
    let sheet = try #require(renderer.artwork.sublayers?.first)
    let light = try #require(renderer.image(size: size))
    renderer.draw(world, size: size, scale: 1, style: style, systemDark: false)
    #expect(renderer.artwork.sublayers?.first === sheet)
    style.apply(["colour": "original", "descriptions": "hide", "tilt": "right", "relationships": "hide", "groups": "hide"])
    #expect(!style.descriptions && !style.relationships && !style.groupNames && style.tilt == .right)
    renderer.draw(world, size: size, scale: 2, style: style, systemDark: true)
    let dark = try #require(renderer.image(size: size, scale: 2))
    #expect(dark.width == 1440 && dark.height == 960)
    #expect(renderer.artwork.sublayers?.first !== sheet)
    #expect(light.dataProvider!.data! as Data != dark.dataProvider!.data! as Data)
    #expect(try world.checkpoint() == state)
}

@Test @MainActor func clippingAndTiltLeaveTheFocusVisibleAcrossDisplayShapes() throws {
    let graph = try #require(Catalogue.bundled["water-cycle"])
    let world = Exploration(seed: 42, scope: graph.id)
    let style = DesignStyle()
    for size in [CGSize(width: 1440, height: 900), CGSize(width: 550, height: 1100), CGSize(width: 2560, height: 900)] {
        let camera = DiagramCamera(size: size, style: style, displaySeed: 42)
        let layout = DiagramLayout(chapter: world.chapter, style: style, camera: camera)
        let scene = DiagramScene(chapter: world.chapter, layout: layout, style: style,
                                 ink: Ink(style: style, dark: false, generation: 0, seed: 42))
        scene.display(camera: camera, beat: 0, progress: 0)
        let canvas = try #require(scene.layer.sublayers?.first)
        let angle = abs(atan2(canvas.affineTransform().b, canvas.affineTransform().a)) * 180 / .pi
        #expect((14.9...20.1).contains(angle))
        #expect(scene.layer.masksToBounds)
        #expect(scene.layer.bounds.contains(canvas.convert(layout.nodes[world.chapter.visit.entry]!.centre, to: scene.layer)))
        #expect(layout.nodes.values.contains { !scene.layer.bounds.contains(canvas.convert($0, to: scene.layer)) })
    }
}

@Test @MainActor func palettesKeepTitlesLegibleInBothAppearances() {
    func luminance(_ colour: CGColor) -> Double {
        let channels = colour.components!.prefix(3).map { c in
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }
    func contrast(_ a: CGColor, _ b: CGColor) -> Double {
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
    for colour in Colour.allCases {
        var style = DesignStyle()
        style.colour = colour
        for dark in [false, true] {
            let ink = Ink(style: style, dark: dark, generation: 83, seed: 42)
            #expect(contrast(ink.text, ink.wash) >= 4.5, "\(colour) component")
            #expect(contrast(ink.reverse, ink.accent) >= 4.5, "\(colour) focal component")
            #expect(contrast(ink.muted, ink.paper) >= 4.5, "\(colour), dark \(dark), contrast \(contrast(ink.muted, ink.paper))")
        }
    }
}

@Test @MainActor func checkpointReproducesBothSheetsMidTransition() throws {
    var world = Exploration(seed: 123)
    world.advance(world.chapter.lastBeat * (world.chapter.beatTicks + 1) + world.chapter.beatTicks / 8)
    let resumed = try #require(Exploration(checkpoint: try world.checkpoint()))
    let size = CGSize(width: 640, height: 400)
    func pixels(_ sample: Exploration) throws -> Data {
        let renderer = DesignRenderer()
        renderer.draw(sample, size: size, scale: 1, style: DesignStyle(), systemDark: false)
        #expect(renderer.artwork.sublayers?.count == 2)
        return try #require(renderer.image(size: size)?.dataProvider?.data) as Data
    }
    #expect(try pixels(resumed) == pixels(world))
}
