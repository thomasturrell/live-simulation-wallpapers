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
    // Older checkpoints contain only moving trips.
    var parkedTicks: Int? = nil
    var originDriveway: Plot? = nil
    var destinationDriveway: Plot? = nil
    static let parkingDuration = 2 * City.ticksPerSecond
    fileprivate static let mergeLength = 0.52

    package var originAccess: ParkingAccess {
        ParkingAccess(road: route[0], lot: originDriveway ?? origin, isDriveway: originDriveway != nil)
    }
    package var destinationAccess: ParkingAccess {
        ParkingAccess(road: route[route.count - 1], lot: destinationDriveway ?? destination, isDriveway: destinationDriveway != nil)
    }

    public struct Pose {
        public let x: Double
        public let y: Double
        public let dx: Double
        public let dy: Double
        public let visibility: Double
    }

    var distance: Double { Double(progress) / Double(pace) }
    var segment: Int { min(Int(distance), route.count - 2) }

    package func pose(in convention: TrafficConvention) -> Pose { pose(at: distance, in: convention) }

    func pose(at distance: Double, in convention: TrafficConvention) -> Pose {
        let end = Double(route.count - 1)
        if parkedTicks != nil || distance >= end {
            let bay = destinationAccess
            let position = bay.center, heading = bay.heading(in: convention)
            return Pose(x: position.x, y: position.y, dx: heading.x, dy: heading.y,
                        visibility: parkedTicks.map { min(1, Double($0) / 12) } ?? 1)
        }
        let center = position(at: distance, in: convention)
        let before = position(at: max(0, distance - 0.04), in: convention)
        let after = position(at: min(end, distance + 0.04), in: convention)
        return Pose(x: center.x, y: center.y, dx: after.x - before.x, dy: after.y - before.y,
                    visibility: min(1, distance * Double(pace) / 5))
    }

    private func position(at distance: Double, in convention: TrafficConvention) -> SIMD2<Double> {
        func lateral(_ direction: SIMD2<Double>) -> SIMD2<Double> {
            let normal = convention.laneNormal(x: Int(direction.x), y: Int(direction.y))
            return SIMD2(Double(normal.x), Double(normal.y)) * 0.20
        }
        let segment = min(Int(distance), route.count - 2)
        let from = vector(route[segment]), to = vector(route[segment + 1])
        let direction = to - from
        let lane = lateral(direction)
        let fraction = distance - Double(segment)
        let turn = 0.24
        // Match the lane tangent at one end and the painted bay or drive at the other.
        let merge = Self.mergeLength
        if segment == 0 && fraction < merge {
            return parkingCurve(bay: originAccess, lanePoint: from + direction * merge + lane,
                                travel: direction, departing: true, phase: fraction / merge, convention: convention)
        }
        if segment + 2 == route.count && fraction > 1 - merge {
            return parkingCurve(bay: destinationAccess, lanePoint: to - direction * merge + lane,
                                travel: direction, departing: false, phase: (1 - fraction) / merge, convention: convention)
        }
        if fraction < turn {
            let previous = from - vector(route[segment - 1])
            let entry = from - previous * turn + lateral(previous)
            let control = from + (lane + lateral(previous)) * 0.5
            return curve(entry, control, from + direction * turn + lane, (fraction + turn) / (2 * turn))
        }
        if fraction > 1 - turn {
            let next = vector(route[segment + 2]) - to
            let exit = to + next * turn + lateral(next)
            return curve(to - direction * turn + lane, to + (lane + lateral(next)) * 0.5, exit,
                         (fraction - 1 + turn) / (2 * turn))
        }
        return from + direction * fraction + lane
    }

    private func parkingCurve(bay: ParkingAccess, lanePoint: SIMD2<Double>, travel: SIMD2<Double>,
                              departing: Bool, phase: Double, convention: TrafficConvention) -> SIMD2<Double> {
        let handle = departing ? 0.19 : -0.19
        let start = bay.center, first = start + bay.heading(in: convention, departing: departing) * handle
        let second = lanePoint - travel * handle
        let t = phase, r = 1 - t
        return start * (r * r * r) + first * (3 * r * r * t)
             + second * (3 * r * t * t) + lanePoint * (t * t * t)
    }

    private func vector(_ p: Plot) -> SIMD2<Double> { SIMD2(Double(p.x), Double(p.y)) }
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
        var driveway: Plot? = nil
    }

    mutating func seedTraffic() {
        let addresses = trafficAddresses()
        for _ in 0..<42 { dispatchTrip(addresses: addresses, underway: true) }
    }

    mutating func moveTraffic() {
        // Stable priority lets cars in junctions clear first. Each move avoids
        // both cars still waiting and positions already accepted this tick.
        var footprints = Dictionary(uniqueKeysWithValues: vehicles.map { ($0.id, $0.footprint(in: trafficConvention)) })
        var reservedPaths = Dictionary(uniqueKeysWithValues: vehicles.map { ($0.id, reservedPath(for: $0)) })
        let currentJunctions = Dictionary(uniqueKeysWithValues: vehicles.map { ($0.id, junctions(occupiedBy: $0)) })
        let order = vehicles.indices.sorted {
            let firstInside = !currentJunctions[vehicles[$0].id, default: []].isEmpty
            let secondInside = !currentJunctions[vehicles[$1].id, default: []].isEmpty
            return firstInside == secondInside ? vehicles[$0].id < vehicles[$1].id : firstInside
        }
        for index in order {
            let vehicle = vehicles[index]
            let occupiedJunctions = currentJunctions[vehicle.id, default: []]
            if let remaining = vehicle.parkedTicks {
                vehicles[index].parkedTicks = remaining - 1
                continue
            }
            var next = vehicle
            next.progress += 1
            // Keep a length-aware following gap until the leader's rear has
            // cleared its previous edge, including the rear swing of a truck.
            guard vehicles.allSatisfy({ leader in
                guard leader.id != vehicle.id, let gap = vehicle.gap(to: leader), gap > 0 else { return true }
                return gap - 1 / Double(vehicle.pace) >= vehicle.halfLength + leader.halfLength + 0.06
            }) else { continue }
            let entering = junctions(occupiedBy: next).filter { !occupiedJunctions.contains($0) }
            guard entering.allSatisfy({ junction in
                if !map.hasJunctionControl(at: junction) { return true }
                let phase = (tick / 18 + junction.x * 11 + junction.y * 5) % 10
                let eastWest = vehicle.route[vehicle.segment].y == vehicle.route[vehicle.segment + 1].y
                guard eastWest ? (0...3).contains(phase) : (5...8).contains(phase) else { return false }
                return true
            }) else { continue }

            let currentEnd = reservationEnd(for: vehicle) ?? vehicle.distance
            if let nextEnd = reservationEnd(for: next), nextEnd > currentEnd + 0.000001 {
                // Check a manoeuvre when claiming it. Rechecking a path already
                // reserved can make its owner yield to cars waiting at its edge.
                let claim = TrafficPath(next.path(through: nextEnd, in: trafficConvention))
                guard footprints.allSatisfy({ id, other in id == vehicle.id || !claim.overlaps(other, clearance: 0.06) }),
                      reservedPaths.allSatisfy({ id, path in id == vehicle.id || !claim.overlaps(path, clearance: 0.06) }) else { continue }
            }
            let current = footprints[vehicle.id]!
            let middle = vehicle.footprint(at: vehicle.distance + 0.5 / Double(vehicle.pace), in: trafficConvention)
            let destination = next.footprint(in: trafficConvention)
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
                if occupiedJunctions.contains(where: { currentJunctions[id, default: []].contains($0) }) { return true }
                return !path.overlaps(middle, clearance: 0.06) && !path.overlaps(destination, clearance: 0.06)
            }) else { continue }
            if next.progress == (next.route.count - 1) * next.pace {
                next.parkedTicks = Vehicle.parkingDuration
            }
            vehicles[index] = next
            // Later cars also avoid the positions accepted earlier this tick.
            footprints[vehicle.id] = destination
            reservedPaths[vehicle.id] = reservedPath(for: next)
        }
        vehicles.removeAll { $0.parkedTicks == 0 }

        let interval = darkness > 0.65 ? 37 : 12
        if tick.isMultiple(of: interval), vehicles.count < (darkness > 0.65 ? 25 : 51) {
            dispatchTrip(addresses: trafficAddresses())
        }
    }

    func trafficAddresses() -> [Address] {
        CityMap.plots.compactMap { point in
            let lot = map[point]
            guard let access = map.parkingAccess(at: point), construction?.plot != access.lot else { return nil }
            return Address(lot: point, road: access.road, zone: lot.zone, driveway: access.isDriveway ? access.lot : nil)
        }
    }

    mutating func dispatchTrip(addresses: [Address], underway: Bool = false) {
        guard !addresses.isEmpty else { return }
        let hour = dayFraction * 24
        let freight = random.pick(8) == 0
        let morning = (6..<13).contains(hour)
        let outgoing: Zone = freight ? .industry : (morning ? .homes : .commerce)
        let incoming: Zone = freight || morning ? .commerce : .homes
        // Some journeys return against the main flow of commuters and deliveries.
        let returning = random.pick(4) == 0
        let origins = addresses.filter { $0.zone == (returning ? incoming : outgoing) }
        let destinations = addresses.filter { $0.zone == (returning ? outgoing : incoming) }
        guard !origins.isEmpty, !destinations.isEmpty else { return }
        // Occasional cross-town journeys enter and leave the wallpaper crop.
        // Pick real outer neighbourhoods in map space, independent of the display.
        let crossTown = random.pick(5) == 0
        let outskirts = crossTown ? origins.filter { $0.road.distance(to: CityMap.center) >= 34 } : []
        let departures = outskirts.isEmpty ? origins : outskirts
        let start = departures[random.pick(departures.count)]
        let farSide = outskirts.isEmpty ? [] : destinations.filter {
            $0.road.distance(to: CityMap.center) >= 34 && $0.road.distance(to: start.road) >= 65
        }
        let arrivals = farSide.isEmpty ? destinations : farSide
        let end = arrivals[random.pick(arrivals.count)]
        dispatchJourney(from: start, to: end, freight: freight, underway: underway)
    }

    private mutating func dispatchJourney(from start: Address, to end: Address, freight: Bool, underway: Bool = false) {
        guard vehicles.count < 60 else { return }
        guard let route = map.route(from: start.road, to: end.road, origin: start.driveway ?? start.lot, destination: end.driveway ?? end.lot,
                                    convention: trafficConvention), route.count > 3 else { return }
        let pace = 21 + random.pick(9)
        let color = random.pick(8)
        let progress = underway ? 4 + random.pick((route.count - 2) * pace) : 1
        let vehicle = Vehicle(id: nextVehicle, route: route, color: color, pace: pace, long: freight,
                              origin: start.lot, destination: end.lot, progress: progress,
                              originDriveway: start.driveway, destinationDriveway: end.driveway)
        let reservation = reservedPath(for: vehicle)
        let path = reservation.isEmpty ? TrafficPath([vehicle.footprint(in: trafficConvention)]) : reservation
        guard !vehicles.contains(where: { other in
            path.overlaps(other.footprint(in: trafficConvention), clearance: 0.06)
                || path.overlaps(reservedPath(for: other), clearance: 0.06)
        }) else { return }
        vehicles.append(vehicle)
        nextVehicle &+= 1
    }

    private func parkingManeuverEnd(for vehicle: Vehicle) -> Double? {
        let mergeEnd = Vehicle.mergeLength + 0.04
        if vehicle.distance < mergeEnd { return mergeEnd }
        let end = Double(vehicle.route.count - 1)
        // Include the curve and the heading sample on either side of it.
        return vehicle.distance > end - mergeEnd ? end : nil
    }

    private func reservedPath(for vehicle: Vehicle) -> TrafficPath {
        TrafficPath(reservationEnd(for: vehicle).map { vehicle.path(through: $0, in: trafficConvention) } ?? [])
    }

    private func reservationEnd(for vehicle: Vehicle) -> Double? {
        guard vehicle.parkedTicks == nil else { return nil }
        var end = parkingManeuverEnd(for: vehicle)
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
