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

    public var pose: Pose {
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

struct RoadEdge: Hashable {
    let from: Plot
    let to: Plot
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
        // Use previous positions so array ordering does not affect car following.
        var traffic: [RoadEdge: [Double]] = [:]
        for vehicle in vehicles {
            let i = vehicle.segment
            if vehicle.distance < Double(i) + 0.25, i > 0 {
                let edge = RoadEdge(from: vehicle.route[i - 1], to: vehicle.route[i])
                traffic[edge, default: []].append(vehicle.distance - Double(i) + 1)
            }
            let edge = RoadEdge(from: vehicle.route[i], to: vehicle.route[i + 1])
            traffic[edge, default: []].append(vehicle.distance - Double(i))
        }

        for index in vehicles.indices {
            let vehicle = vehicles[index]
            let i = vehicle.segment
            let edge = RoadEdge(from: vehicle.route[i], to: vehicle.route[i + 1])
            let offset = vehicle.distance - Double(i)
            if traffic[edge, default: []].contains(where: { $0 > offset && $0 - offset < 0.30 }) { continue }
            let next = edge.to
            // Stagger the two axes at larger junctions. Cars already in the
            // turning area clear it before the next direction is admitted.
            let previous = offset + 1 / Double(vehicle.pace)
            if i + 2 < vehicle.route.count && offset < 0.72 && previous >= 0.72,
               next.neighbors.filter(map.isRoad).count > 2 {
                let phase = (tick / 18 + next.x * 11 + next.y * 5) % 10
                let eastWest = edge.from.y == edge.to.y
                let permitted = eastWest ? (0...3).contains(phase) : (5...8).contains(phase)
                if !permitted { continue }
            }
            vehicles[index].progress += 1
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
        guard let route = map.route(from: start.road, to: end.road), route.count > 3 else { return }
        let pace = 21 + random.pick(9)
        let color = random.pick(8)
        let progress = underway ? 4 + random.pick((route.count - 2) * pace) : 1
        let segment = progress / pace
        let offset = Double(progress) / Double(pace) - Double(segment)
        guard !vehicles.contains(where: {
            $0.route[$0.segment] == route[segment] && $0.route[$0.segment + 1] == route[segment + 1]
                && abs($0.distance - Double($0.segment) - offset) < 0.38
        }) else { return }
        vehicles.append(Vehicle(id: nextVehicle, route: route, color: color, pace: pace, long: freight,
                                origin: start.lot, destination: end.lot, progress: progress))
        nextVehicle &+= 1
    }
}
