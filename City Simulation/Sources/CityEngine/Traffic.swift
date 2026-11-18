import Foundation

public struct Vehicle: Codable, Equatable {
    public let id: UInt64
    public let route: [Plot]
    public let color: Int
    public let pace: Int
    public let long: Bool
    public let origin: Plot
    public let destination: Plot
    public internal(set) var progress: Int

    public struct Pose {
        public let x: Double
        public let y: Double
        public let dx: Double
        public let dy: Double
        public let visibility: Double
    }

    var distance: Double { Double(progress) / Double(pace) }
    var segment: Int { min(Int(distance), route.count - 2) }

    public var pose: Pose { pose(at: distance) }

    func pose(at distance: Double) -> Pose {
        let end = Double(route.count - 1)
        let center = position(at: distance)
        let before = position(at: max(0, distance - 0.04))
        let after = position(at: min(end, distance + 0.04))
        return Pose(x: center.x, y: center.y, dx: after.x - before.x, dy: after.y - before.y,
                    visibility: min(1, distance * 4, (end - distance) * 4))
    }

    private func position(at distance: Double) -> SIMD2<Double> {
        let segment = min(Int(distance), route.count - 2)
        let from = vector(route[segment]), to = vector(route[segment + 1])
        let direction = to - from
        let lane = lateral(direction)
        let fraction = distance - Double(segment)
        let turn = 0.24
        if fraction < turn {
            let entry: SIMD2<Double>
            let control: SIMD2<Double>
            if segment == 0 {
                entry = from + (vector(origin) - from) * 0.43
                control = from + lane * 0.5
            } else {
                let previous = from - vector(route[segment - 1])
                entry = from - previous * turn + lateral(previous)
                control = from + (lane + lateral(previous)) * 0.5
            }
            let phase = segment == 0 ? fraction / turn : (fraction + turn) / (2 * turn)
            return curve(entry, control, from + direction * turn + lane, phase)
        }
        if fraction > 1 - turn {
            let exit: SIMD2<Double>
            if segment + 2 == route.count {
                exit = to + (vector(destination) - to) * 0.43
                return curve(to - direction * turn + lane, to + lane * 0.5, exit, (fraction - 1 + turn) / turn)
            }
            let next = vector(route[segment + 2]) - to
            exit = to + next * turn + lateral(next)
            return curve(to - direction * turn + lane, to + (lane + lateral(next)) * 0.5, exit,
                         (fraction - 1 + turn) / (2 * turn))
        }
        return from + direction * fraction + lane
    }

    private func vector(_ p: Plot) -> SIMD2<Double> { SIMD2(Double(p.x), Double(p.y)) }
    private func lateral(_ direction: SIMD2<Double>) -> SIMD2<Double> {
        SIMD2(-direction.y, direction.x) * 0.20
    }

    private func curve(_ a: SIMD2<Double>, _ b: SIMD2<Double>, _ c: SIMD2<Double>, _ t: Double) -> SIMD2<Double> {
        let rest = 1 - t
        return a * (rest * rest) + b * (2 * rest * t) + c * (t * t)
    }
}

extension City {
    struct Address {
        let lot: Plot
        let road: Plot
        let zone: Zone
    }

    mutating func seedTraffic() {
        let addresses = trafficAddresses()
        for _ in 0..<42 { dispatchTrip(addresses: addresses, underway: true) }
    }

    mutating func moveTraffic() {
        // Stable priority lets cars in junctions clear first. Each move avoids
        // both cars still waiting and positions already accepted this tick.
        var footprints = Dictionary(uniqueKeysWithValues: vehicles.map { ($0.id, $0.footprint) })
        var reservedPaths = Dictionary(uniqueKeysWithValues: vehicles.map { ($0.id, reservedPath(for: $0)) })
        let currentJunctions = Dictionary(uniqueKeysWithValues: vehicles.map { ($0.id, junctions(occupiedBy: $0)) })
        let order = vehicles.indices.sorted {
            let firstInside = !currentJunctions[vehicles[$0].id, default: []].isEmpty
            let secondInside = !currentJunctions[vehicles[$1].id, default: []].isEmpty
            return firstInside == secondInside ? vehicles[$0].id < vehicles[$1].id : firstInside
        }
        for index in order {
            let vehicle = vehicles[index]
            var next = vehicle
            next.progress += 1
            // Keep a length-aware following gap until the leader's rear has
            // cleared its previous edge, including the rear swing of a truck.
            guard vehicles.allSatisfy({ leader in
                guard leader.id != vehicle.id, let gap = vehicle.gap(to: leader), gap > 0 else { return true }
                return gap - 1 / Double(vehicle.pace) >= vehicle.halfLength + leader.halfLength + 0.06
            }) else { continue }
            let entering = junctions(occupiedBy: next).filter { !currentJunctions[vehicle.id, default: []].contains($0) }
            guard entering.allSatisfy({ junction in
                if junction.neighbors.filter(map.isRoad).count == 2 { return true }
                let phase = (tick / 18 + junction.x * 11 + junction.y * 5) % 10
                let eastWest = vehicle.route[vehicle.segment].y == vehicle.route[vehicle.segment + 1].y
                guard eastWest ? (0...3).contains(phase) : (5...8).contains(phase) else { return false }
                return true
            }) else { continue }

            let currentEnd = reservationEnd(for: vehicle) ?? vehicle.distance
            if let nextEnd = reservationEnd(for: next), nextEnd > currentEnd + 0.000001 {
                // Check a manoeuvre when claiming it. Rechecking a path already
                // reserved can make its owner yield to cars waiting at its edge.
                guard next.path(through: nextEnd).allSatisfy({ space in
                    footprints.allSatisfy { id, other in id == vehicle.id || !space.overlaps(other, clearance: 0.06) }
                        && reservedPaths.allSatisfy { id, path in id == vehicle.id || !path.contains { space.overlaps($0, clearance: 0.06) } }
                }) else { continue }
            }
            let current = vehicle.footprint
            let middle = vehicle.footprint(at: vehicle.distance + 0.5 / Double(vehicle.pace))
            let destination = next.footprint
            guard footprints.allSatisfy({ id, space in
                if id == vehicle.id { return true }
                // Old checkpoints may already contain an overlap. Allow a car
                // to move out of it, but never further into it.
                if current.overlaps(space) {
                    let oldDistance = current.separationSquared(from: space)
                    let newDistance = destination.separationSquared(from: space)
                    return newDistance >= oldDistance
                        && destination.centerDistanceSquared(from: space) > current.centerDistanceSquared(from: space) + 0.000001
                }
                return !middle.overlaps(space) && !destination.overlaps(space)
            }), reservedPaths.allSatisfy({ id, path in
                if id == vehicle.id { return true }
                // More than one car may already occupy a junction in an old
                // checkpoint. Physical checks still let those cars separate.
                if !Set(currentJunctions[vehicle.id, default: []]).isDisjoint(with: currentJunctions[id, default: []]) { return true }
                return !path.contains { middle.overlaps($0, clearance: 0.06) || destination.overlaps($0, clearance: 0.06) }
            }) else { continue }
            vehicles[index] = next
            // Later cars also avoid the positions accepted earlier this tick.
            footprints[vehicle.id] = destination
            reservedPaths[vehicle.id] = reservedPath(for: next)
        }
        vehicles.removeAll { $0.progress >= ($0.route.count - 1) * $0.pace }

        let interval = darkness > 0.65 ? 37 : 12
        if tick.isMultiple(of: interval), vehicles.count < (darkness > 0.65 ? 25 : 51) {
            dispatchTrip(addresses: trafficAddresses())
        }
    }

    func trafficAddresses() -> [Address] {
        CityMap.plots.compactMap { point in
            let lot = map[point]
            guard lot.building != nil, let road = map.roadAccess(at: point) else { return nil }
            return Address(lot: point, road: road, zone: lot.zone)
        }
    }

    mutating func dispatchTrip(addresses: [Address], underway: Bool = false) {
        guard !addresses.isEmpty else { return }
        let hour = dayFraction * 24
        let freight = random.pick(8) == 0
        let morning = (6..<13).contains(hour)
        let outgoing: Zone = freight ? .industry : (morning ? .homes : .commerce)
        let incoming: Zone = freight || morning ? .commerce : .homes
        let origins = addresses.filter { $0.zone == outgoing }
        let destinations = addresses.filter { $0.zone == incoming }
        guard !origins.isEmpty, !destinations.isEmpty else { return }
        let start = origins[random.pick(origins.count)]
        let end = destinations[random.pick(destinations.count)]
        dispatchJourney(from: start, to: end, freight: freight, underway: underway)
    }

    mutating func dispatchAirportTraffic(toAirport: Bool) {
        guard let terminal = map.airport?.terminal, let road = map.roadAccess(at: terminal) else { return }
        let airport = Address(lot: terminal, road: road, zone: .civic)
        let addresses = trafficAddresses().filter { $0.zone == .homes || $0.zone == .commerce }
        guard !addresses.isEmpty else { return }
        for _ in 0..<3 {
            let city = addresses[random.pick(addresses.count)]
            dispatchJourney(from: toAirport ? city : airport, to: toAirport ? airport : city, freight: false)
        }
    }

    private mutating func dispatchJourney(from start: Address, to end: Address, freight: Bool, underway: Bool = false) {
        guard vehicles.count < 60 else { return }
        guard let route = map.route(from: start.road, to: end.road, origin: start.lot, destination: end.lot), route.count > 3 else { return }
        let pace = 21 + random.pick(9)
        let color = random.pick(8)
        let progress = underway ? 4 + random.pick((route.count - 2) * pace) : 1
        let vehicle = Vehicle(id: nextVehicle, route: route, color: color, pace: pace, long: freight,
                              origin: start.lot, destination: end.lot, progress: progress)
        let reservation = reservedPath(for: vehicle)
        let path = reservation.isEmpty ? [vehicle.footprint] : reservation
        guard !vehicles.contains(where: { other in
            path.contains { space in
                space.overlaps(other.footprint, clearance: 0.06) || reservedPath(for: other).contains { space.overlaps($0, clearance: 0.06) }
            }
        }) else { return }
        vehicles.append(vehicle)
        nextVehicle &+= 1
    }

    private func drivewayEnd(for vehicle: Vehicle) -> Double? {
        if vehicle.distance < 0.28 { return 0.28 }
        let end = Double(vehicle.route.count - 1)
        // Include the curve and the heading sample on either side of it.
        return vehicle.distance > end - 0.28 ? end : nil
    }

    private func reservedPath(for vehicle: Vehicle) -> [TrafficFootprint] {
        reservationEnd(for: vehicle).map { vehicle.path(through: $0) } ?? []
    }

    private func reservationEnd(for vehicle: Vehicle) -> Double? {
        var end = drivewayEnd(for: vehicle)
        var node = max(0, vehicle.segment - 1)
        // Adjacent junctions share space, so reserve them together. Driveway
        // turns start only after the vehicle's rear has cleared the crossing.
        while node < vehicle.route.count {
            let entry = Double(node) - vehicle.junctionClearance
            if entry >= max(vehicle.distance, end ?? vehicle.distance) { break }
            let exit = min(Double(vehicle.route.count - 1), Double(node) + vehicle.junctionExitClearance + 0.06 + 1 / Double(vehicle.pace))
            if exit > vehicle.distance, isTrafficJunction(vehicle.route[node]) {
                end = max(end ?? exit, exit)
            }
            node += 1
        }
        return end
    }

    private func isTrafficJunction(_ plot: Plot) -> Bool {
        let roads = plot.neighbors.filter(map.isRoad)
        return roads.count > 2 || (roads.count == 2 && roads[0].x != roads[1].x && roads[0].y != roads[1].y)
    }

    private func junctions(occupiedBy vehicle: Vehicle) -> [Plot] {
        let start = max(0, vehicle.segment - 1)
        let end = min(vehicle.route.count - 1, vehicle.segment + 2)
        return (start...end).compactMap { node in
            let junction = vehicle.route[node]
            guard vehicle.distance > Double(node) - vehicle.junctionClearance,
                  vehicle.distance < Double(node) + vehicle.junctionExitClearance,
                  isTrafficJunction(junction) else { return nil }
            return junction
        }
    }
}
