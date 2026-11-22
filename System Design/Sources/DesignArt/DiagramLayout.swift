import AppKit
import DesignEngine

/// Reveals share one layout at a given viewport and framing so existing nodes stay put.
struct DiagramLayout {
    let nodes: [String: CGRect]
    let cameraStops: [CGPoint]
    let groups: [String: CGRect]
    let routes: [Route]
    let labels: [CGRect?]
    let members: [String: [String]]

    init(chapter: Chapter, style: DesignStyle, camera: DiagramCamera) {
        let graph = chapter.graph
        var memberships: [String: [String]] = [:]
        let parents = Dictionary(uniqueKeysWithValues: graph.groups.map { ($0.id, $0) })
        for node in graph.nodes {
            var id = node.group
            while let group = id {
                memberships[group, default: []].append(node.id)
                id = parents[group]?.parent
            }
        }
        members = memberships
        let sizes = graph.nodes.map { node -> CGSize in
            let detail = style.descriptions && node.detail != nil
            let width = max(detail ? 228 : 134, measure(node.name, font(20, .semibold)) + 44)
            switch node.kind {
            case .decision: return CGSize(width: width + 66, height: detail ? 152 : 112)
            case .sensor:
                let diameter = width + 10
                return CGSize(width: diameter, height: detail ? 148 : min(164, diameter))
            case .store: return CGSize(width: width + 8, height: detail ? 128 : 92)
            case .hub: return CGSize(width: width + 34, height: detail ? 118 : 82)
            default: return CGSize(width: width, height: detail ? 108 : 72)
            }
        }
        let positions = Self.positions(graph, memberships, seed: chapter.visit.seed, sizes: sizes)
        var rects: [String: CGRect] = [:]
        for (index, node) in graph.nodes.enumerated() {
            let p = positions[index], s = sizes[index]
            rects[node.id] = CGRect(x: p.x - s.width / 2, y: p.y - s.height / 2, width: s.width, height: s.height)
        }
        Self.fitOpening(chapter: chapter, rects: &rects, camera: camera)
        nodes = rects
        cameraStops = camera.stops(for: chapter, nodes: rects)
        var boundaries: [String: CGRect] = [:]
        func boundary(_ group: Subsystem) -> CGRect {
            if let cached = boundaries[group.id] { return cached }
            var rect = graph.nodes.filter { $0.group == group.id }.compactMap { rects[$0.id] }
                .reduce(CGRect.null) { $0.union($1) }
            for child in graph.groups where child.parent == group.id { rect = rect.union(boundary(child)) }
            rect = rect.insetBy(dx: -22, dy: -22)
            rect.size.height += 24
            boundaries[group.id] = rect
            return rect
        }
        for group in graph.groups { _ = boundary(group) }
        groups = boundaries
        var routes: [Route] = []
        for (index, edge) in graph.edges.enumerated() {
            var obstacles = graph.nodes.filter { $0.id != edge.source && $0.id != edge.target }.map { rects[$0.id]! }
            let opposite = graph.edges.prefix(index).firstIndex { $0.source == edge.target && $0.target == edge.source }
            if let opposite {
                // Reserve the middle of the outgoing lane for its arrow and verb.
                let mid = routes[opposite].point(at: 0.5)
                obstacles.append(CGRect(x: mid.x - 6, y: mid.y - 6, width: 12, height: 12))
            }
            routes.append(Route(source: rects[edge.source]!, target: rects[edge.target]!, obstacles: obstacles,
                                layout: graph.layout, returning: edge.kind == .feedback || opposite != nil))
        }
        self.routes = routes
        var reserved = Array(rects.values)
        if style.groupNames {
            for group in graph.groups {
                let b = boundaries[group.id]!
                reserved.append(CGRect(x: b.minX, y: b.maxY - 25, width: measure(group.name.uppercased(), font(13, .medium, mono: true)) + 35, height: 25))
            }
        }
        labels = graph.edges.enumerated().map { index, edge in
            let width = measure(edge.label, font(14, .medium)) + 16
            for fraction in [0.5, 0.32, 0.68, 0.2, 0.8] {
                let p = routes[index].point(at: fraction)
                for offset in [0.0, 15, -15] {
                    let r = CGRect(x: p.x - width / 2, y: p.y + offset - 10, width: width, height: 21)
                    guard !reserved.contains(where: { $0.intersects(r.insetBy(dx: -5, dy: -4)) }),
                          !routes.enumerated().contains(where: { $0.offset != index && $0.element.intersects(r) }) else { continue }
                    reserved.append(r)
                    return r
                }
            }
            return nil
        }
    }

    private static func fitOpening(chapter: Chapter, rects: inout [String: CGRect], camera: DiagramCamera) {
        let entry = chapter.visit.entry, neighbour = chapter.order[1]
        let anchor = rects[entry]!, original = rects[neighbour]!
        let viewport = CGRect(origin: .zero, size: camera.size).insetBy(dx: 8, dy: 8)
        func screenRect(_ rect: CGRect) -> CGRect {
            rect.offsetBy(dx: -anchor.midX, dy: -anchor.midY).applying(camera.transform)
                .offsetBy(dx: camera.focusPoint.x, dy: camera.focusPoint.y)
        }
        guard chapter.firstCount == 2, !viewport.contains(screenRect(original)) else { return }

        // Long connections can run off the sheet. Reserve a visible position for the
        // opening neighbour before measuring the groups, routing edges or placing labels.
        let others = chapter.order.dropFirst(2)
        let dx = (anchor.width + original.width) / 2 + 48
        let dy = (anchor.height + original.height) / 2 + 48
        var best = original
        var bestCost = (CGFloat.infinity, Int.max, CGFloat.infinity)
        func consider(_ proposed: CGRect) {
            let screen = screenRect(proposed)
            let shift = CGPoint(x: max(0, viewport.minX - screen.minX) + min(0, viewport.maxX - screen.maxX),
                                y: max(0, viewport.minY - screen.minY) + min(0, viewport.maxY - screen.maxY))
                .applying(camera.transform.inverted())
            let fitted = proposed.offsetBy(dx: shift.x, dy: shift.y)
            let candidate = fitted.intersects(anchor.insetBy(dx: -12, dy: -12)) ? proposed : fitted
            let projected = screenRect(candidate)
            let visible = projected.intersection(viewport)
            let clipped = max(0, projected.width * projected.height - visible.width * visible.height)
            let collisions = others.filter { rects[$0]!.intersects(candidate.insetBy(dx: -12, dy: -12)) }.count
            let cost = (clipped.rounded(), collisions, hypot(candidate.midX - original.midX, candidate.midY - original.midY))
            if cost < bestCost {
                best = candidate
                bestCost = cost
            }
        }
        consider(original)
        for row in -1...1 {
            for column in -1...1 where row != 0 || column != 0 {
                consider(original.offsetBy(dx: anchor.midX + CGFloat(column) * dx - original.midX,
                                           dy: anchor.midY + CGFloat(row) * dy - original.midY))
            }
        }
        rects[neighbour] = best
        for id in others where rects[id]!.intersects(best.insetBy(dx: -12, dy: -12)) {
            let displaced = rects[id]!
            var slot = displaced.offsetBy(dx: original.midX - displaced.midX, dy: original.midY - displaced.midY)
            while rects.contains(where: { $0.key != id && $0.value.intersects(slot.insetBy(dx: -12, dy: -12)) }) {
                slot.origin.y -= slot.height + 48
            }
            rects[id] = slot
        }
    }

    private static func positions(_ g: SystemGraph, _ members: [String: [String]], seed: UInt64, sizes: [CGSize]) -> [CGPoint] {
        let count = g.nodes.count
        let dx = (sizes.map(\.width).max() ?? 220) + 95
        let dy = (sizes.map(\.height).max() ?? 100) + 96
        var points = Array(repeating: CGPoint.zero, count: count)
        let indices = Dictionary(uniqueKeysWithValues: g.nodes.enumerated().map { ($1.id, $0) })
        let hub = g.nodes.max { g.neighbours(of: $0.id).count < g.neighbours(of: $1.id).count }!
        let turn = CGFloat(seed % 19) * .pi / 180
        switch g.layout {
        case .cycle, .radial, .mesh:
            let radial = g.layout != .cycle
            let ring = g.nodes.filter { !radial || $0.id != hub.id }
            let radius = max(1, CGFloat(ring.count) / (2 * .pi))
            for (i, node) in ring.enumerated() {
                let a = turn + CGFloat(i) * 2 * .pi / CGFloat(ring.count)
                let r = g.layout == .mesh && i.isMultiple(of: 2) ? radius * 1.18 : radius
                points[indices[node.id]!] = CGPoint(x: cos(a) * dx * r, y: sin(a) * dy * r)
            }
        case .grouped:
            var columns: [[Component]] = []
            for group in g.groups where group.parent == nil {
                let ids = members[group.id] ?? []
                columns.append(g.nodes.filter { ids.contains($0.id) })
            }
            let standalone = g.nodes.filter { $0.group == nil }
            if !standalone.isEmpty { columns.append(standalone) }
            for (col, nodes) in columns.enumerated() {
                for (row, node) in nodes.enumerated() {
                    points[indices[node.id]!] = CGPoint(x: CGFloat(col) * (dx + 68),
                        y: (CGFloat(nodes.count - 1) * 0.5 - CGFloat(row)) * dy + CGFloat(col % 2) * 50)
                }
            }
        case .flow, .vertical, .tree:
            // Forward dependencies determine ranks. Back edges use return lanes rather than pushing a cycle apart.
            var ranks = Array(repeating: 0, count: count)
            for i in g.nodes.indices {
                let inputs = g.edges.filter { $0.target == g.nodes[i].id }.compactMap { indices[$0.source] }.filter { $0 < i }
                ranks[i] = inputs.map { ranks[$0] + 1 }.max() ?? 0
            }
            let vertical = g.layout == .vertical || g.layout == .tree
            for rank in 0...(ranks.max() ?? 0) {
                let siblings = ranks.indices.filter { ranks[$0] == rank }
                for (row, i) in siblings.enumerated() {
                    let lane = CGFloat(row) - CGFloat(siblings.count - 1) / 2
                    // A long single chain folds into terraces so adjacent stages can share the viewport.
                    let band = rank / 3, step = band.isMultiple(of: 2) ? rank % 3 : 2 - rank % 3
                    if g.layout == .tree {
                        points[i] = CGPoint(x: lane * dx, y: -CGFloat(rank) * dy)
                    } else if vertical {
                        points[i] = CGPoint(x: (CGFloat(band) * 2 + lane) * dx, y: -CGFloat(step) * dy)
                    } else {
                        points[i] = CGPoint(x: CGFloat(step) * dx, y: (lane - CGFloat(band) * 2) * dy)
                    }
                }
            }
        }
        // Split rare collisions between secondary lanes using actual text-bearing bounds.
        for i in points.indices {
            let size = sizes[i]
            func footprint(_ index: Int) -> CGRect {
                CGRect(x: points[index].x - sizes[index].width / 2, y: points[index].y - sizes[index].height / 2,
                       width: sizes[index].width, height: sizes[index].height).insetBy(dx: -25, dy: -20)
            }
            while (0..<i).contains(where: { footprint(i).intersects(footprint($0)) }) {
                points[i].y -= size.height + 64
            }
        }
        return points
    }
}
