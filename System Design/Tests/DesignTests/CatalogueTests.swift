import Foundation
import Testing
@testable import DesignEngine

@Test func catalogueCoversFourSubjectsWithDistinctGraphs() throws {
    let catalogue = Catalogue.bundled
    #expect(catalogue.graphs.count >= 100)
    #expect(Subject.allCases.allSatisfy { catalogue.candidates($0.rawValue).count >= 20 })
    #expect(Set(catalogue.graphs.map(\.layout)) == Set(Arrangement.allCases))
    #expect(Set(catalogue.graphs.flatMap { $0.nodes.map(\.kind) }) == Set(NodeKind.allCases))
    #expect(Set(catalogue.graphs.map { $0.nodes.map(\.id).sorted() }).count == catalogue.graphs.count)
    #expect(catalogue.graphs.allSatisfy { $0.nodes.filter { $0.detail != nil }.count >= 2 })
    #expect(catalogue.concepts.values.contains { Set($0.map(\.system)).count > 3 })
    #expect(throws: (any Error).self) { try Catalogue([catalogue.graphs[0], catalogue.graphs[0]]) }
}

@Test func malformedReferencesAndGroupsFailValidation() throws {
    let graph = try #require(Catalogue.bundled["domestic-solar-power"])
    let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(graph)) as? [String: Any])
    for (section, field, value) in [("nodes", "id", "missing"), ("edges", "source", "missing"),
                                    ("nodes", "group", "missing"), ("groups", "parent", "generation"),
                                    ("edges", "label", " "), ("nodes", "name", "")] {
        var modified = json
        var objects = try #require(json[section] as? [[String: Any]])
        objects[0][field] = value
        modified[section] = objects
        let invalid = try JSONDecoder().decode(SystemGraph.self, from: JSONSerialization.data(withJSONObject: modified))
        #expect(throws: (any Error).self) { try Catalogue([invalid]) }
    }
}

@Test func connectedExplorationVisitsEverySystemAndFollowsSharedConcepts() {
    var world = Exploration(seed: 343)
    var visits = Set<String>()
    var linked = 0
    for _ in Catalogue.bundled.graphs.indices {
        let chapter = world.chapter
        #expect(visits.insert(chapter.graph.id).inserted)
        var revealed: Set<String> = [chapter.visit.entry]
        for id in chapter.order.dropFirst() {
            #expect(!chapter.graph.neighbours(of: id).isDisjoint(with: revealed))
            revealed.insert(id)
        }
        #expect(revealed.count == chapter.graph.nodes.count)
        let incoming = world.incomingChapter()
        if chapter.next.linkedEntry {
            let exit = chapter.graph.nodes.first { $0.id == chapter.exit }!
            let entry = incoming.graph.nodes.first { $0.id == incoming.visit.entry }!
            #expect(exit.concept != nil && exit.concept == entry.concept)
            linked += 1
        }
        world.advance((chapter.lastBeat + 1) * (chapter.beatTicks + 1))
        #expect(world.chapter.visit == incoming.visit)
        #expect(world.chapter.next == incoming.next)
    }
    #expect(visits.count == Catalogue.bundled.graphs.count)
    #expect(linked > 50)
}

@Test func scopesSeedsAndCheckpointsSurviveHandoffs() throws {
    for scope in ["society", "water-cycle"] {
        var original = Exploration(seed: 9, scope: scope)
        for _ in 0..<5 {
            let step = original.chapter.beatTicks + 1
            original.advance(original.chapter.lastBeat * step + step / 2)
            var resumed = try #require(Exploration(checkpoint: try original.checkpoint()))
            for ticks in [1, 4, step, 17] {
                original.advance(ticks)
                resumed.advance(ticks)
                #expect(try original.checkpoint() == resumed.checkpoint())
                #expect(original.chapter.order == resumed.chapter.order)
                #expect(scope == "society" ? original.chapter.graph.category == .society : original.chapter.graph.id == scope)
            }
        }
    }
    #expect(Exploration(checkpoint: Data()) == nil)
    let a = Exploration(seed: 42), b = Exploration(seed: 1000)
    #expect(a.chapter.visit != b.chapter.visit)
}

@Test func invalidCheckpointVersionsAndCursorsAreDiscarded() throws {
    let original = Exploration(seed: 20)
    let data = try original.checkpoint()
    let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    for (key, value) in [("version", 42), ("tick", -1), ("beat", 1000)] {
        var corrupt = plist
        corrupt[key] = value
        let bytes = try PropertyListSerialization.data(fromPropertyList: corrupt, format: .binary, options: 0)
        #expect(Exploration(checkpoint: bytes) == nil)
    }
}
