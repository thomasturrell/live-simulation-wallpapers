import Foundation

package enum Subject: String, CaseIterable, Codable {
    case technology, engineering, nature, society

    package var title: String {
        switch self {
        case .technology: "Computing and technology"
        case .engineering: "Energy and engineering"
        case .nature: "Biology and natural systems"
        case .society: "Human and organisational systems"
        }
    }
}

package enum Arrangement: String, Codable, CaseIterable { case flow, vertical, tree, radial, cycle, mesh, grouped }
package enum NodeKind: String, Codable, CaseIterable { case process, store, entity, decision, hub, event, sensor }
package enum Relation: String, Codable { case flow, signal, feedback, dependency, inhibition }

package struct Component: Codable {
    package let id, name: String
    package let kind: NodeKind
    package let detail, concept, group, symbol: String?
}

package struct Connection: Codable {
    package let source, target, label: String
    package let kind: Relation
}

package struct Subsystem: Codable {
    package let id, name: String
    package let parent: String?
}

package struct SystemGraph: Codable {
    package let id, name, description: String
    package let category: Subject
    package let layout: Arrangement
    package let nodes: [Component]
    package let edges: [Connection]
    package let groups: [Subsystem]

    package func neighbours(of id: String) -> Set<String> {
        Set(edges.compactMap { $0.source == id ? $0.target : $0.target == id ? $0.source : nil })
    }
}

package struct ConceptLocation: Equatable {
    let system, node: String
}

package struct Catalogue {
    package let graphs: [SystemGraph]
    private let index: [String: SystemGraph]
    let concepts: [String: [ConceptLocation]]

    package static let bundled: Self = {
        do {
            let graphs = try Subject.allCases.flatMap { subject -> [SystemGraph] in
                // The hand-linked extension carries flat resources. SwiftPM owns its resource bundle.
                guard let url = Bundle.main.url(forResource: subject.rawValue, withExtension: "json")
                    ?? Bundle.module.url(forResource: subject.rawValue, withExtension: "json") else {
                    throw CatalogueError("Missing \(subject.rawValue) catalogue")
                }
                let graphs = try JSONDecoder().decode([SystemGraph].self, from: Data(contentsOf: url))
                guard graphs.allSatisfy({ $0.category == subject }) else { throw CatalogueError("Wrong category in \(url.lastPathComponent)") }
                return graphs
            }
            return try Self(graphs)
        } catch { fatalError("Invalid bundled system catalogue: \(error)") }
    }()

    package init(_ graphs: [SystemGraph]) throws {
        func validID(_ id: String) -> Bool {
            !id.isEmpty && id.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
        }
        func unique(_ ids: [String]) -> Bool { Set(ids).count == ids.count && ids.allSatisfy(validID) }
        func hasText(_ text: String) -> Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !graphs.isEmpty, unique(graphs.map(\.id)), Set(graphs.map(\.name)).count == graphs.count else {
            throw CatalogueError("Missing or duplicate system identifiers or names")
        }
        var concepts: [String: [ConceptLocation]] = [:]
        for graph in graphs {
            let error = CatalogueError("Invalid content or reference in \(graph.id)")
            guard hasText(graph.name), hasText(graph.description), graph.nodes.count >= 3,
                  unique(graph.nodes.map(\.id)), unique(graph.groups.map(\.id)) else { throw error }
            let nodes = Set(graph.nodes.map(\.id))
            let groups = Dictionary(uniqueKeysWithValues: graph.groups.map { ($0.id, $0) })
            var used = Set<String>()
            for node in graph.nodes {
                guard hasText(node.name), node.detail.map(hasText) != false else { throw error }
                if let concept = node.concept {
                    guard validID(concept) else { throw error }
                    concepts[concept, default: []].append(.init(system: graph.id, node: node.id))
                }
                var next = node.group
                var ancestors = Set<String>()
                while let id = next {
                    guard let group = groups[id], hasText(group.name), ancestors.insert(id).inserted else { throw error }
                    used.insert(id)
                    next = group.parent
                }
            }
            guard used == Set(groups.keys) else { throw error }
            var pairs = Set<[String]>()
            for edge in graph.edges {
                guard nodes.contains(edge.source), nodes.contains(edge.target), edge.source != edge.target,
                      hasText(edge.label), pairs.insert([edge.source, edge.target, edge.label]).inserted else { throw error }
            }
            var reached = Set([graph.nodes[0].id])
            var frontier = Array(reached)
            while let node = frontier.popLast() {
                for id in graph.neighbours(of: node) where reached.insert(id).inserted { frontier.append(id) }
            }
            guard reached == nodes else { throw error }
        }
        self.graphs = graphs
        self.concepts = concepts
        index = Dictionary(uniqueKeysWithValues: graphs.map { ($0.id, $0) })
    }

    package subscript(_ id: String) -> SystemGraph? { index[id] }

    package func candidates(_ scope: String) -> [SystemGraph] {
        if let graph = index[scope] { return [graph] }
        if let subject = Subject(rawValue: scope) { return graphs.filter { $0.category == subject } }
        return graphs
    }
}

private struct CatalogueError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
