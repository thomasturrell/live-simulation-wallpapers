@testable import CityEngine
import Foundation
import Testing

private func trafficCity(_ convention: TrafficConvention = .rightHand) -> City {
    var city = City(trafficConvention: convention)
    city.vehicles = []
    city.map.airport = nil
    for plot in CityMap.plots {
        city.map[plot] = Lot(ground: (plot.y == 19 && (20...28).contains(plot.x))
                             || (plot.x == 24 && (15...23).contains(plot.y)) ? .road : .grass)
    }
    return city
}

private func car(_ id: UInt64, route: [Plot], pace: Int = 24, long: Bool = false, distance: Double, destination: Plot? = nil, convention: TrafficConvention = .rightHand) -> Vehicle {
    let first = route[0], second = route[1], last = route.last!, previous = route[route.count - 2]
    let startLane = convention.laneNormal(x: second.x - first.x, y: second.y - first.y)
    let endLane = convention.laneNormal(x: last.x - previous.x, y: last.y - previous.y)
    return Vehicle(id: id, route: route, color: 0, pace: pace, long: long,
                   origin: Plot(first.x + startLane.x, first.y + startLane.y),
                   destination: destination ?? Plot(last.x + endLane.x, last.y + endLane.y),
                   progress: Int(distance * Double(pace)))
}

private let across = (22...27).map { Plot($0, 19) }
private let down = (17...22).map { Plot(24, $0) }

@Test(arguments: [0.0, 0.06])
func footprintBoundsPreserveExactCollisionChecks(clearance: Double) {
    let margin = TrafficFootprint.radius * 2 + clearance
    var footprints: [TrafficFootprint] = []
    for center in [SIMD2(-4.0, -3), SIMD2(0, 0), SIMD2(margin, 0), SIMD2(margin - 0.000001, 0), SIMD2(0, margin)] {
        for extent in [SIMD2(0.0, 0), SIMD2(0.22, 0), SIMD2(0, 0.34), SIMD2(0.24, -0.24)] {
            for visible in [false, true] {
                footprints.append(TrafficFootprint(front: center + extent, back: center - extent, visible: visible))
            }
        }
    }
    for first in footprints {
        for second in footprints {
            let expected = first.visible && second.visible && first.separationSquared(from: second) < margin * margin
            #expect(first.overlaps(second, clearance: clearance) == expected)
        }
    }
}

@Test(arguments: [0.0, 0.06], TrafficConvention.allCases)
func reservationBoundsPreserveEverySampledCollisionCheck(clearance: Double, convention: TrafficConvention) {
    let turning = [Plot(22, 19), Plot(23, 19), Plot(24, 19), Plot(24, 20), Plot(24, 21), Plot(24, 22)]
    let distant = across.map { Plot($0.x - 12, $0.y + 10) }
    let samples = [across, down, turning, distant].enumerated().map { index, route in
        car(UInt64(index), route: route, long: index.isMultiple(of: 2), distance: 0, convention: convention)
            .path(through: 5, in: convention)
    }
    // Empty/invisible reservations, one-sample paths and gaps inside a path's
    // bounds must agree with the exhaustive checks as well as real manoeuvres.
    let paths = samples + [[], [samples[0][0]], [samples[0][20]], [samples[0][20], samples[0][160]]]
    let reservations = paths.map(TrafficPath.init)
    for (index, path) in paths.enumerated() {
        for footprint in samples.flatMap({ $0 }) {
            let expected = path.contains { $0.overlaps(footprint, clearance: clearance) }
            #expect(reservations[index].overlaps(footprint, clearance: clearance) == expected)
        }
        for (otherIndex, other) in paths.enumerated() {
            let expected = path.contains { first in other.contains { first.overlaps($0, clearance: clearance) } }
            #expect(reservations[index].overlaps(reservations[otherIndex], clearance: clearance) == expected)
        }
    }
}

@Test(arguments: Array(21...29), [false, true])
func vehiclesStopWithTheirWholeBodyBeforeTheCrossing(pace: Int, long: Bool) {
    for convention in TrafficConvention.allCases {
        for direction in [Plot(1, 0), Plot(-1, 0), Plot(0, 1), Plot(0, -1)] {
            var city = trafficCity(convention)
            let route = (-2...2).map { Plot(24 + $0 * direction.x, 19 + $0 * direction.y) }
            var vehicle = car(0, route: route, pace: pace, long: long, distance: 0, convention: convention)
            vehicle.progress = Int((2 - vehicle.junctionClearance) * Double(pace))
            city.vehicles = [vehicle]
            for _ in 0..<17 { city.step() }
            #expect(city.vehicles.first?.progress == vehicle.progress)
            let pose = city.vehicles[0].pose(in: city.trafficConvention)
            let front = SIMD2(pose.x, pose.y) + SIMD2(Double(direction.x), Double(direction.y)) * vehicle.halfLength
            let remaining = (24 - front.x) * Double(direction.x) + (19 - front.y) * Double(direction.y)
            #expect(remaining >= RoadGeometry.stopLineDistance - 0.000001)
            #expect(remaining <= RoadGeometry.stopLineDistance + 1 / Double(pace) + 0.000001)
            for _ in 0..<220 { city.step() }
            #expect(city.vehicles.isEmpty)
        }
    }
}

@Test(arguments: TrafficConvention.allCases)
func aCarWaitsForRoomBeyondTheJunction(convention: TrafficConvention) {
    var city = trafficCity(convention)
    for _ in 0..<18 { city.step() } // East-west now has permission to enter.
    var waiting = car(0, route: across, distance: 0, convention: convention)
    waiting.progress = Int((2 - waiting.junctionClearance) * Double(waiting.pace))
    let blocking = car(1, route: across, pace: 25, distance: 2.8, convention: convention)
    city.vehicles = [waiting, blocking]
    city.step()
    #expect(city.vehicles[0].progress == waiting.progress)
    city.vehicles.removeAll { $0.id == blocking.id }
    city.step()
    #expect(city.vehicles[0].progress == waiting.progress + 1)
}

@Test func crossingAndTurningCarsWaitTheirTurnAndCompleteTheirTrips() {
    var city = trafficCity()
    let leftTurn = [Plot(24, 21), Plot(24, 20), Plot(24, 19), Plot(23, 19), Plot(22, 19), Plot(21, 19)]
    city.vehicles = [car(0, route: across, pace: 29, long: true, distance: 0.9),
                     car(1, route: down, pace: 21, distance: 0.9),
                     car(2, route: leftTurn, pace: 25, distance: 0.9)]
    var minimum = Double.infinity
    for _ in 0..<450 {
        city.step()
        for (index, first) in city.vehicles.enumerated() {
            for second in city.vehicles.dropFirst(index + 1) {
                minimum = min(minimum, hypot(first.pose(in: city.trafficConvention).x - second.pose(in: city.trafficConvention).x, first.pose(in: city.trafficConvention).y - second.pose(in: city.trafficConvention).y))
            }
        }
    }
    #expect(minimum >= 0.24)
    #expect(city.vehicles.isEmpty)
}

@Test func followingCarsStayBehindLongVehiclesThroughATurn() {
    var city = trafficCity()
    let turning = [Plot(22, 19), Plot(23, 19), Plot(24, 19), Plot(24, 20), Plot(24, 21), Plot(24, 22)]
    city.vehicles = [car(0, route: turning, pace: 29, long: true, distance: 1.8),
                     car(1, route: [Plot(21, 19)] + across, pace: 21, distance: 2.1)]
    var minimum = Double.infinity
    for _ in 0..<400 {
        city.step()
        if city.vehicles.count == 2 {
            let first = city.vehicles[0].pose(in: city.trafficConvention), second = city.vehicles[1].pose(in: city.trafficConvention)
            minimum = min(minimum, hypot(first.x - second.x, first.y - second.y))
        }
    }
    #expect(minimum >= 0.24)
    #expect(city.vehicles.isEmpty)
}

@Test func trafficPriorityDoesNotDependOnArrayOrder() {
    var city = trafficCity()
    city.vehicles = [car(0, route: across, pace: 29, distance: 0.9),
                     car(1, route: down, pace: 21, distance: 0.9)]
    var reversed = city
    for _ in 0..<300 {
        reversed.vehicles.reverse()
        city.step()
        reversed.step()
        #expect(city.vehicles.sorted { $0.id < $1.id } == reversed.vehicles.sorted { $0.id < $1.id })
    }
    #expect(city.vehicles.isEmpty)
}

@Test func carsAlreadyOverlappingInAnOlderCheckpointCanSeparate() {
    var city = trafficCity()
    let turning = [Plot(22, 19), Plot(23, 19), Plot(24, 19), Plot(24, 20), Plot(24, 21)]
    city.vehicles = [car(0, route: across, pace: 23, distance: 42.0 / 23),
                     car(1, route: turning, distance: 52.0 / 24)]
    #expect(hypot(city.vehicles[0].pose(in: city.trafficConvention).x - city.vehicles[1].pose(in: city.trafficConvention).x,
                  city.vehicles[0].pose(in: city.trafficConvention).y - city.vehicles[1].pose(in: city.trafficConvention).y) < 0.01)
    for _ in 0..<300 { city.step() }
    #expect(city.vehicles.isEmpty)
}

@Test(arguments: [City.defaultSeed, 42, 99, 0, 1, 2], TrafficConvention.allCases)
func seededTrafficRemainsSeparatedAndKeepsMoving(seed: UInt64, convention: TrafficConvention) {
    var city = City(seed: seed, trafficConvention: convention)
    let original = Set(city.vehicles.map(\.id))
    var overlap: String?
    var idleTicks = 0
    var longestPause = 0
    for _ in 0..<5400 {
        // Every pair is still checked on every tick; each body's geometry only
        // needs to be sampled once while the city is unchanged.
        let footprints = city.vehicles.map { $0.footprint(in: city.trafficConvention) }
        for first in footprints.indices {
            for second in footprints.indices.dropFirst(first + 1) where footprints[first].overlaps(footprints[second]) {
                overlap = overlap ?? "tick \(city.tick), cars \(city.vehicles[first].id) and \(city.vehicles[second].id)"
            }
        }
        let previous = city.vehicles.map { ($0.id, $0.progress) }
        city.step()
        let current = city.vehicles.map { ($0.id, $0.progress) }
        let moved = !previous.elementsEqual(current, by: { $0 == $1 })
        idleTicks = moved ? 0 : idleTicks + 1
        longestPause = max(longestPause, idleTicks)
    }
    #expect(overlap == nil)
    #expect(longestPause < 240)
    #expect(original.subtracting(city.vehicles.map(\.id)).count >= min(16, original.count))
}

@Test(arguments: [false, true])
func parkingAfterAJunctionLetsOpposingTrafficClear(long: Bool) {
    var city = trafficCity()
    city.vehicles = [car(0, route: Array(across.prefix(4)), pace: 29, long: long, distance: 0.9,
                         destination: Plot(25, 18)),
                     car(1, route: Array((22...26).reversed()).map { Plot($0, 19) }, pace: 21, distance: 0.98)]
    var minimum = Double.infinity
    for _ in 0..<450 {
        city.step()
        if city.vehicles.count == 2 {
            let a = city.vehicles[0].pose(in: city.trafficConvention), b = city.vehicles[1].pose(in: city.trafficConvention)
            minimum = min(minimum, hypot(a.x-b.x, a.y-b.y))
        }
    }
    #expect(minimum >= 0.24)
    #expect(city.vehicles.isEmpty)
}

@Test(arguments: TrafficConvention.allCases)
func newTripsWaitForSpaceToJoinTheirLane(convention: TrafficConvention) {
    var city = trafficCity(convention)
    let south = (16...23).map { Plot(24, $0) }
    let drivewayX = convention == .uk ? 25 : 23
    city.vehicles = [car(1000, route: south, pace: 25, distance: 2.44, convention: convention)]
    let addresses = [City.Address(lot: Plot(drivewayX, 18), road: Plot(24, 18), zone: .homes),
                     City.Address(lot: Plot(drivewayX, 22), road: Plot(24, 22), zone: .commerce)]
    for _ in 0..<50 { city.dispatchTrip(addresses: addresses) }
    #expect(city.vehicles.count == 1)
    #expect(city.vehicles[0].id == 1000)
    city.vehicles = []
    for _ in 0..<50 { city.dispatchTrip(addresses: addresses) }
    #expect(city.vehicles.count == 1)
    #expect(city.vehicles[0].id != 1000)
}

@Test(arguments: [false, true], [false, true])
func opposingParkingArrivalsLeaveRoomForEachOther(firstLong: Bool, secondLong: Bool) {
    var city = trafficCity()
    for x in 29...31 { city.map[Plot(x, 19)] = Lot(ground: .road) }
    city.vehicles = [car(0, route: (23...27).map { Plot($0, 19) }, pace: 29, long: firstLong,
                         distance: 2.2, destination: Plot(27, 20)),
                     car(1, route: (26...31).reversed().map { Plot($0, 19) }, pace: 21, long: secondLong,
                         distance: 3.2, destination: Plot(26, 18))]
    var overlap = false
    for _ in 0..<600 {
        city.step()
        if city.vehicles.count == 2 { overlap = overlap || city.vehicles[0].footprint(in: city.trafficConvention).overlaps(city.vehicles[1].footprint(in: city.trafficConvention)) }
    }
    #expect(!overlap)
    #expect(city.vehicles.isEmpty)
}

@Test(arguments: [City.defaultSeed, 42, 99, 0, 1, 2], TrafficConvention.allCases)
func tripsUseTheLaneOnTheSameSideAsTheirDriveways(seed: UInt64, convention: TrafficConvention) {
    var city = City(seed: seed, trafficConvention: convention)
    for _ in 0..<600 { city.step() }
    for vehicle in city.vehicles {
        let first = vehicle.route[0], second = vehicle.route[1]
        let end = vehicle.route.last!, previous = vehicle.route[vehicle.route.count - 2]
        let originSide = (vehicle.origin.x - first.x) * (first.y - second.y)
            + (vehicle.origin.y - first.y) * (second.x - first.x)
        let destinationSide = (vehicle.destination.x - end.x) * (previous.y - end.y)
            + (vehicle.destination.y - end.y) * (end.x - previous.x)
        let expectedSign = convention == .uk ? -1 : 1
        #expect(expectedSign * originSide >= 0)
        #expect(expectedSign * destinationSide >= 0)
    }
}

@Test(arguments: TrafficConvention.allCases)
func opposingCarsCanClearAdjacentJunctions(convention: TrafficConvention) {
    var city = trafficCity(convention)
    for x in [23, 25] { city.map[Plot(x, 20)] = Lot(ground: .road) }
    let south = (17...23).map { Plot(24, $0) }
    let north = (16...22).reversed().map { Plot(24, $0) }
    city.vehicles = [car(0, route: south, distance: 2.13, convention: convention),
                     car(1, route: north, distance: 2.13, convention: convention)]
    var minimum = Double.infinity
    for _ in 0..<400 {
        city.step()
        if city.vehicles.count == 2 {
            let a = city.vehicles[0].pose(in: city.trafficConvention), b = city.vehicles[1].pose(in: city.trafficConvention)
            minimum = min(minimum, hypot(a.x-b.x, a.y-b.y))
        }
    }
    #expect(minimum >= 0.24)
    #expect(city.vehicles.isEmpty)
}

@Test(arguments: TrafficConvention.allCases)
func opposingCarsYieldAtABendUntilTheirBodiesClear(convention: TrafficConvention) {
    var city = trafficCity(convention)
    for plot in CityMap.plots { city.map[plot] = Lot() }
    let route = (21...24).map { Plot($0, 19) } + (20...23).map { Plot(24, $0) }
    for plot in route { city.map[plot] = Lot(ground: .road) }
    city.vehicles = [car(0, route: route, pace: 29, long: true, distance: 2, convention: convention),
                     car(1, route: Array(route.reversed()), pace: 21, distance: 3, convention: convention)]
    var overlap = false
    for _ in 0..<400 {
        city.step()
        if city.vehicles.count == 2 { overlap = overlap || city.vehicles[0].footprint(in: city.trafficConvention).overlaps(city.vehicles[1].footprint(in: city.trafficConvention)) }
    }
    #expect(!overlap)
    #expect(city.vehicles.isEmpty)
}

@Test(arguments: TrafficConvention.allCases)
func vehiclesKeepToTheCorrectLaneInAllFourDirections(convention: TrafficConvention) {
    let journeys: [([Plot], Double, Double)] = [
        (across, 0, -0.20), (across.reversed(), 0, 0.20),
        (down, 0.20, 0), (down.reversed(), -0.20, 0)
    ]
    let sign = convention == .uk ? 1.0 : -1.0
    for (route, offsetX, offsetY) in journeys {
        let vehicle = car(0, route: route, distance: 1.5, convention: convention)
        let pose = vehicle.pose(in: convention)
        let midX = Double(route[1].x + route[2].x) / 2
        let midY = Double(route[1].y + route[2].y) / 2
        #expect(abs(pose.x - midX - sign * offsetX) < 0.000001)
        #expect(abs(pose.y - midY - sign * offsetY) < 0.000001)
    }
}

@Test(arguments: TrafficConvention.allCases, [-1, 1])
func opposingVehiclesCompleteLeftAndRightTurnsWithoutOverlapping(convention: TrafficConvention, turn: Int) {
    var city = trafficCity(convention)
    let eastbound = [Plot(21, 19), Plot(22, 19), Plot(23, 19), Plot(24, 19)]
        + (1...3).map { Plot(24, 19 + $0 * turn) }
    let westbound = [Plot(27, 19), Plot(26, 19), Plot(25, 19), Plot(24, 19)]
        + (1...3).map { Plot(24, 19 - $0 * turn) }
    let first = car(0, route: eastbound, pace: 29, long: true, distance: 2, convention: convention)
    let second = car(1, route: westbound, pace: 21, distance: 2, convention: convention)
    let sign = convention == .uk ? 1.0 : -1.0
    let entry = first.pose(at: 2.75, in: convention)
    let exit = first.pose(at: 3.25, in: convention)
    #expect(abs(entry.y - (19 - sign * 0.20)) < 0.000001)
    #expect(abs(exit.x - (24 + Double(turn) * sign * 0.20)) < 0.000001)
    city.vehicles = [first, second]
    var overlap = false
    for _ in 0..<450 {
        city.step()
        if city.vehicles.count == 2 {
            overlap = overlap || city.vehicles[0].footprint(in: convention).overlaps(city.vehicles[1].footprint(in: convention))
        }
    }
    #expect(!overlap)
    #expect(city.vehicles.isEmpty)
}
