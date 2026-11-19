import AppKit
import Testing
@testable import DesignArt
@testable import DesignEngine

@MainActor
private func draw(_ renderer: DesignRenderer, _ world: Exploration, size: CGSize, style: DesignStyle = DesignStyle()) {
    renderer.draw(world, size: size, scale: 1, style: style, systemDark: false)
}

@MainActor
private func pixels(_ renderer: DesignRenderer, size: CGSize) throws -> Data {
    try #require(renderer.image(size: size)?.dataProvider?.data) as Data
}

@Test @MainActor func cameraKeepsItsDisplayTiltAndFramingAcrossVisitsAndRestores() throws {
    for seed: UInt64 in [42, 123] {
        var next = Exploration(seed: seed)
        let first = next
        next.advance((next.chapter.lastBeat + 1) * (next.chapter.beatTicks + 1))
        let restored = try #require(Exploration(checkpoint: try next.checkpoint()))
        for size in [CGSize(width: 1040, height: 650), CGSize(width: 550, height: 1100)] {
            let base = max(min(size.width / 1040, size.height / 650), size.height / 920, size.width / 1770)
            for tilt in DesignStyle.Tilt.allCases {
                for framing in DesignStyle.Framing.allCases {
                    var style = DesignStyle()
                    style.tilt = tilt
                    style.framing = framing
                    let renderer = DesignRenderer()
                    for world in [first, next, restored] {
                        draw(renderer, world, size: size, style: style)
                        let canvas = try #require(renderer.artwork.sublayers?.first?.sublayers?.first)
                        let transform = canvas.affineTransform()
                        let left = tilt == .left || (tilt == .varied && seed.isMultiple(of: 2))
                        let angle: CGFloat = tilt == .level ? 0 : (left ? 17 : -17)
                        let zoom: CGFloat = framing == .wide ? 0.8 : framing == .close ? 1.35 : 1
                        #expect(abs(atan2(transform.b, transform.a) * 180 / .pi - angle) < 0.00001)
                        #expect(abs(hypot(transform.a, transform.b) - base * zoom) < 0.00001)
                    }
                }
            }
        }
    }
}

@Test @MainActor func linkedCardStaysCentredAndTheOpeningEdgeDrawsAwayFromIt() throws {
    let size = CGSize(width: 960, height: 600)
    // These visits cover both possible directions of the first relationship.
    for seed: UInt64 in [42, 136, 2299] {
        var world = Exploration(seed: seed)
        let outgoing = world.chapter, incoming = world.incomingChapter()
        try #require(incoming.visit.linkedEntry)
        let edgeIndex = try #require(incoming.edgeRevealBeats.firstIndex(of: 0))
        let edge = incoming.graph.edges[edgeIndex]
        let camera = DiagramCamera(size: size, style: DesignStyle(), displaySeed: seed)
        let layout = DiagramLayout(chapter: incoming, style: DesignStyle(), camera: camera)
        let renderer = DesignRenderer()
        world.advance(outgoing.lastBeat * (outgoing.beatTicks + 1) - 1)
        draw(renderer, world, size: size)
        let oldCanvas = try #require(renderer.artwork.sublayers?.first?.sublayers?.first)
        let source = try #require(oldCanvas.sublayers?.first { $0.name == outgoing.exit })
        let fixed = source.convert(source.bounds.centre, to: renderer.root)
        let oldSize = source.bounds.size
        world.advance(1)
        for tick in [0, outgoing.beatTicks / 4, outgoing.beatTicks / 2, outgoing.beatTicks] {
            world.advance(tick - world.tick)
            draw(renderer, world, size: size)
            let canvas = try #require(renderer.artwork.sublayers?.last?.sublayers?.first)
            let entry = try #require(canvas.sublayers?.first { $0.name == incoming.visit.entry })
            let neighbour = try #require(canvas.sublayers?.first { $0.name == incoming.order[1] })
            let anchor = entry.convert(entry.bounds.centre, to: renderer.root)
            #expect(hypot(anchor.x - fixed.x, anchor.y - fixed.y) < 0.00001)
            #expect(source.isHidden && !entry.isHidden && entry.opacity == 1)
            let lines = (canvas.sublayers ?? []).compactMap { $0 as? CAShapeLayer }
            let stroke = try #require(lines.first { $0.path == layout.routes[edgeIndex].path })
            if tick == 0 { #expect(entry.bounds.size == oldSize) }
            if tick == outgoing.beatTicks / 2 {
                #expect(stroke.strokeEnd > stroke.strokeStart && stroke.strokeEnd - stroke.strokeStart < 1)
                #expect(edge.target == incoming.visit.entry ? stroke.strokeEnd == 1 : stroke.strokeStart == 0)
                #expect(neighbour.opacity == 0)
            }
            if tick == outgoing.beatTicks {
                #expect(entry.bounds.size == layout.nodes[incoming.visit.entry]?.size)
                #expect(stroke.strokeStart == 0 && stroke.strokeEnd == 1)
                #expect(renderer.root.bounds.contains(neighbour.convert(neighbour.bounds, to: renderer.root)))
                let cards = (canvas.sublayers ?? []).filter { $0.name != nil && $0.opacity > 0 }
                #expect(Set(cards.compactMap(\.name)) == Set(incoming.order.prefix(2)))
                let visibleEdges = lines.filter { layer in
                    layer.strokeEnd > layer.strokeStart && layout.routes.contains { $0.path == layer.path }
                }
                #expect(visibleEdges.count == 1)
            }
        }
        let joined = try pixels(renderer, size: size)
        world.advance(1)
        draw(renderer, world, size: size)
        #expect(try pixels(renderer, size: size) == joined)
        #expect(world.chapter.visit == incoming.visit && world.beat == 0)
    }
}

@Test @MainActor func bothHandoffsKeepOneGridAndRestoreTheirFramesAndContinuation() throws {
    let size = CGSize(width: 640, height: 400)
    for seed: UInt64 in [136, 6] {
        var live = Exploration(seed: seed)
        #expect(live.chapter.next.linkedEntry == (seed == 136))
        let beatTicks = live.chapter.beatTicks
        let renderer = DesignRenderer()
        draw(renderer, live, size: size)
        let grid = try #require(renderer.root.sublayers?.first)
        let pattern = grid.backgroundColor, transform = grid.affineTransform(), position = grid.position
        live.advance(live.chapter.lastBeat * (beatTicks + 1) + beatTicks / 4)
        var restored = try #require(Exploration(checkpoint: try live.checkpoint()))
        let other = DesignRenderer()
        for ticks in [0, beatTicks / 4, beatTicks / 4, beatTicks - 3] {
            live.advance(ticks)
            restored.advance(ticks)
            draw(renderer, live, size: size)
            draw(other, restored, size: size)
            #expect(renderer.root.sublayers?.first === grid && grid.backgroundColor == pattern)
            #expect(grid.affineTransform() == transform && grid.position == position)
            #expect(try pixels(renderer, size: size) == pixels(other, size: size))
            if !live.chapter.next.linkedEntry && live.beat == live.chapter.lastBeat {
                let sheets = try #require(renderer.artwork.sublayers)
                #expect(sheets.count == 2 && sheets[0].opacity > 0 && sheets[1].opacity > 0)
                #expect(abs(sheets[0].opacity + sheets[1].opacity - 1) < 0.00001)
            }
        }
    }
}

@Test @MainActor func theOpeningPairFitsAroundTheHeldAnchorAcrossDisplayShapes() {
    for size in [CGSize(width: 1152, height: 676), CGSize(width: 550, height: 1100), CGSize(width: 2560, height: 900)] {
        var style = DesignStyle()
        style.framing = .close
        let camera = DiagramCamera(size: size, style: style, displaySeed: 42)
        let viewport = CGRect(origin: .zero, size: size)
        for graph in Catalogue.bundled.graphs {
            let chapter = Exploration(seed: 42, scope: graph.id).chapter
            let layout = DiagramLayout(chapter: chapter, style: style, camera: camera)
            let centre = layout.nodes[chapter.visit.entry]!.centre
            for id in chapter.order.prefix(2) {
                let screen = layout.nodes[id]!.offsetBy(dx: -centre.x, dy: -centre.y).applying(camera.transform)
                    .offsetBy(dx: camera.focusPoint.x, dy: camera.focusPoint.y)
                #expect(viewport.contains(screen), "\(graph.id) opening \(chapter.order.prefix(2)) on \(size), entry \(layout.nodes[chapter.visit.entry]!), neighbour \(layout.nodes[chapter.order[1]]!)")
            }
        }
    }
}
