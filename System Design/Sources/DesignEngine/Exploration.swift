import Foundation

/// Only this small, versioned cursor is persisted. Routes and layouts are derived from stable IDs.
package struct Visit: Codable, Equatable {
    package let system, entry: String
    package let seed: UInt64
    package let linkedEntry: Bool
}

private struct Cursor: Codable {
    var version = 1
    let paletteSeed: UInt64
    var scope: String
    var visit: Visit
    var recent: [String]
    var beat = 0
    var tick = 0
    var age = 0
}

struct Variation {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var value = state
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        return value ^ (value >> 31)
    }
    mutating func choose<T>(_ values: [T]) -> T { values[Int(next() % UInt64(values.count))] }
}

package struct Chapter {
    package let graph: SystemGraph
    package let visit: Visit
    package let order: [String]
    package let exit: String
    package let next: Visit
    package static let revealEnd = 0.27
    package static let pulseStart = 0.48
    package static let pulseEnd = 0.75
    package let beatTicks: Int
    package let firstCount: Int
    package var lastBeat: Int { order.count - firstCount + 4 }

    init(_ cursor: Visit, recent: [String], scope: String, catalogue: Catalogue) {
        visit = cursor
        let graph = catalogue[cursor.system]!
        self.graph = graph
        var variation = Variation(state: cursor.seed)
        var order = [cursor.entry]
        var frontier = graph.neighbours(of: cursor.entry)
        while !frontier.isEmpty {
            let node = variation.choose(frontier.sorted())
            order.append(node)
            frontier.formUnion(graph.neighbours(of: node))
            frontier.subtract(order)
        }
        self.order = order
        firstCount = min(order.count, max(4, (order.count + 1) / 2))
        beatTicks = 70 + Int(variation.next() % 26)
        let allowed = catalogue.candidates(scope)
        let permitted = Set(allowed.map(\.id))
        let bridges = graph.nodes.flatMap { node -> [(String, ConceptLocation)] in
            guard let concept = node.concept else { return [] }
            return (catalogue.concepts[concept] ?? []).filter {
                $0.system != cursor.system && permitted.contains($0.system)
            }.map { (node.id, $0) }
        }
        // Prefer unvisited neighbours. When those run out, dissolve to fresh territory.
        let fresh = bridges.filter { !recent.contains($0.1.system) }
        let unused = allowed.filter { !recent.contains($0.id) }
        let leastRecent = recent.first { id in bridges.contains { $0.1.system == id } }
        let revisits = bridges.filter { $0.1.system == leastRecent }
        let options = unused.isEmpty ? revisits : fresh
        if !options.isEmpty {
            let (source, destination) = variation.choose(options)
            exit = source
            next = Visit(system: destination.system, entry: destination.node, seed: variation.next(), linkedEntry: true)
        } else {
            let target = unused.isEmpty ? (allowed.first { $0.id == recent.first } ?? allowed[0]) : variation.choose(unused)
            exit = order.last!
            let entry = target.id == cursor.system ? exit : variation.choose(target.nodes).id
            next = Visit(system: target.id, entry: entry, seed: variation.next(), linkedEntry: target.id == cursor.system)
        }
    }

    package func focus(at beat: Int) -> String {
        if beat == 0 { return visit.entry }
        if beat >= lastBeat - 1 { return exit }
        let revealed = firstCount + beat - 1
        if revealed < order.count { return order[revealed] }
        return order[(revealed + Int(visit.seed % UInt64(order.count))) % order.count]
    }
}

package struct Exploration {
    package static let ticksPerSecond = 16
    private let catalogue: Catalogue
    private var cursor: Cursor
    package private(set) var chapter: Chapter
    package var scope: String { cursor.scope }
    package var paletteSeed: UInt64 { cursor.paletteSeed }
    package var beat: Int { cursor.beat }
    package var tick: Int { cursor.tick }
    package var age: Int { cursor.age }
    package var progress: Double { Double(tick) / Double(chapter.beatTicks) }

    package init(seed: UInt64, scope: String = "all", catalogue: Catalogue = .bundled) {
        let scope = catalogue[scope] != nil || Subject(rawValue: scope) != nil ? scope : "all"
        var rng = Variation(state: seed)
        let graph = rng.choose(catalogue.candidates(scope))
        // Start on a well-connected component so even a brief first lock has context.
        let hubs = graph.nodes.filter { graph.neighbours(of: $0.id).count >= 2 }
        let entry = rng.choose(hubs.isEmpty ? graph.nodes : hubs)
        let visit = Visit(system: graph.id, entry: entry.id, seed: rng.next(), linkedEntry: false)
        self.init(cursor: Cursor(paletteSeed: seed, scope: scope, visit: visit, recent: [graph.id]), catalogue: catalogue)
    }

    private init(cursor: Cursor, catalogue: Catalogue) {
        self.cursor = cursor
        self.catalogue = catalogue
        chapter = Chapter(cursor.visit, recent: cursor.recent, scope: cursor.scope, catalogue: catalogue)
    }

    package init?(checkpoint: Data, catalogue: Catalogue = .bundled) {
        guard let cursor = try? PropertyListDecoder().decode(Cursor.self, from: checkpoint),
              cursor.version == 1, cursor.age >= 0, cursor.age < Int.max / 2,
              let graph = catalogue[cursor.visit.system], graph.nodes.contains(where: { $0.id == cursor.visit.entry }),
              cursor.scope == "all" || Subject(rawValue: cursor.scope) != nil || catalogue[cursor.scope] != nil,
              catalogue.candidates(cursor.scope).contains(where: { $0.id == graph.id }),
              cursor.recent.count <= catalogue.graphs.count, cursor.recent.last == graph.id,
              Set(cursor.recent).count == cursor.recent.count, cursor.recent.allSatisfy({ catalogue[$0] != nil })
        else { return nil }
        self.init(cursor: cursor, catalogue: catalogue)
        guard (0...chapter.lastBeat).contains(beat), (0...chapter.beatTicks).contains(tick) else { return nil }
    }

    package func checkpoint() throws -> Data { try PropertyListEncoder().encode(cursor) }

    mutating func advance(_ ticks: Int, withinBeat: Bool = false) {
        for _ in 0..<ticks {
            if cursor.tick == chapter.beatTicks {
                if withinBeat { return }
                if beat == chapter.lastBeat {
                    let next = chapter.next
                    cursor.visit = next
                    cursor.recent = history(entering: next)
                    chapter = Chapter(next, recent: cursor.recent, scope: scope, catalogue: catalogue)
                    cursor.beat = 0
                } else { cursor.beat += 1 }
                cursor.tick = 0
            } else { cursor.tick += 1 }
            cursor.age += 1
        }
    }

    package func incomingChapter() -> Chapter {
        let next = chapter.next
        return Chapter(next, recent: history(entering: next), scope: scope, catalogue: catalogue)
    }

    private func history(entering next: Visit) -> [String] {
        let history = cursor.recent.filter { $0 != next.system } + [next.system]
        // Start a fresh tour after covering the selection, keeping the last handoff out of immediate rotation.
        if history.count == catalogue.candidates(scope).count { return Array(history.suffix(2)) }
        return history
    }

    var restingTick: Int {
        let endpoint: Double
        if tick > 0, progress < Chapter.revealEnd { endpoint = Chapter.revealEnd }
        else if progress > Chapter.pulseStart, progress < Chapter.pulseEnd { endpoint = Chapter.pulseEnd }
        else { return tick }
        return Int(ceil(endpoint * Double(chapter.beatTicks)))
    }
}

package struct Playback {
    package enum Mode { case suspended, playing, settling, still }
    package static let settleDuration = 2.4
    package private(set) var exploration: Exploration
    package private(set) var mode: Mode = .suspended
    package var needsTimer: Bool { mode == .playing || mode == .settling }
    private var remainder = 0.0
    private var elapsedSettle = 0.0
    private var startTick = 0
    private var endTick = 0
    private var duration = 0.0

    package init(_ exploration: Exploration) { self.exploration = exploration }

    package mutating func present(visible: Bool, animated: Bool) {
        if !visible {
            mode = .suspended
        } else if animated {
            mode = .playing
        } else if mode == .playing {
            startTick = exploration.tick
            endTick = exploration.restingTick
            mode = startTick == endTick ? .still : .settling
            duration = min(Self.settleDuration, 2 * Double(endTick - startTick) / Double(Exploration.ticksPerSecond))
            elapsedSettle = 0
            remainder = 0
        } else if mode == .suspended {
            // A host may discard the surface in mid-dissolve. Finish that same
            // action before presenting its saved cursor as a static desktop.
            if exploration.tick > 0 {
                exploration.advance(exploration.restingTick - exploration.tick, withinBeat: true)
            }
            mode = .still
        }
    }

    package mutating func advance(elapsed: Double) {
        guard needsTimer, elapsed.isFinite, elapsed > 0 else { return }
        let interval = min(0.25, elapsed)
        if mode == .settling {
            elapsedSettle = min(duration, elapsedSettle + interval)
            let fraction = 1 - pow(1 - elapsedSettle / duration, 2)
            let ticks = endTick - startTick
            let target = startTick + Int((Double(ticks) * fraction).rounded())
            exploration.advance(max(0, target - exploration.tick), withinBeat: true)
            if elapsedSettle == duration { mode = .still }
        } else {
            remainder += interval * Double(Exploration.ticksPerSecond)
            let count = Int(remainder + 1e-9)
            remainder -= Double(count)
            exploration.advance(count)
        }
    }
}
