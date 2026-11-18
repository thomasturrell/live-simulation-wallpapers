@testable import CityEngine
import Foundation
import Testing

private func trafficCity() -> City {
    var city = City()
    city.vehicles = []
    city.map.airport = nil
    for plot in CityMap.plots {
        city.map[plot] = Lot(ground: (plot.y == 19 && (20...28).contains(plot.x))
                             || (plot.x == 24 && (15...23).contains(plot.y)) ? .road : .grass)
    }
    return city
}

private func car(_ id: UInt64, route: [Plot], pace: Int = 24, long: Bool = false, distance: Double, destination: Plot? = nil) -> Vehicle {
    let first = route[0], second = route[1], last = route.last!, previous = route[route.count - 2]
    return Vehicle(id: id, route: route, color: 0, pace: pace, long: long,
                   origin: Plot(first.x - second.y + first.y, first.y + second.x - first.x),
                   destination: destination ?? Plot(last.x - last.y + previous.y, last.y + last.x - previous.x),
                   progress: Int(distance * Double(pace)))
}

private let across = (22...27).map { Plot($0, 19) }
private let down = (17...22).map { Plot(24, $0) }

@Test(arguments: Array(21...29), [false, true])
func vehiclesStopWithTheirWholeBodyBeforeTheCrossing(pace: Int, long: Bool) {
    for direction in [Plot(1, 0), Plot(-1, 0), Plot(0, 1), Plot(0, -1)] {
        var city = trafficCity()
        let route = (-2...2).map { Plot(24 + $0 * direction.x, 19 + $0 * direction.y) }
        var vehicle = car(0, route: route, pace: pace, long: long, distance: 0)
        vehicle.progress = Int((2 - vehicle.junctionClearance) * Double(pace))
        city.vehicles = [vehicle]
        for _ in 0..<17 { city.step() }
        #expect(city.vehicles.first?.progress == vehicle.progress)
        let pose = city.vehicles[0].pose
        let front = SIMD2(pose.x, pose.y) + SIMD2(Double(direction.x), Double(direction.y)) * vehicle.halfLength
        let remaining = (24 - front.x) * Double(direction.x) + (19 - front.y) * Double(direction.y)
        #expect(remaining >= 0.5)
        for _ in 0..<220 { city.step() }
        #expect(city.vehicles.isEmpty)
    }
}

@Test func aCarWaitsForRoomBeyondTheJunction() {
    var city = trafficCity()
    for _ in 0..<18 { city.step() } // East-west now has permission to enter.
    var waiting = car(0, route: across, distance: 0)
    waiting.progress = Int((2 - waiting.junctionClearance) * Double(waiting.pace))
    let blocking = car(1, route: across, pace: 25, distance: 2.8)
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
                minimum = min(minimum, hypot(first.pose.x - second.pose.x, first.pose.y - second.pose.y))
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
            let first = city.vehicles[0].pose, second = city.vehicles[1].pose
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
    #expect(hypot(city.vehicles[0].pose.x - city.vehicles[1].pose.x,
                  city.vehicles[0].pose.y - city.vehicles[1].pose.y) < 0.01)
    for _ in 0..<300 { city.step() }
    #expect(city.vehicles.isEmpty)
}

@Test(arguments: [City.defaultSeed, 42, 99, 0, 1, 2])
func seededTrafficRemainsSeparatedAndKeepsMoving(seed: UInt64) {
    var city = City(seed: seed)
    let original = Set(city.vehicles.map(\.id))
    var overlap: String?
    var idleTicks = 0
    var longestPause = 0
    for _ in 0..<5400 {
        for (index, first) in city.vehicles.enumerated() {
            for second in city.vehicles.dropFirst(index + 1) where first.footprint.overlaps(second.footprint) {
                overlap = overlap ?? "tick \(city.tick), cars \(first.id) and \(second.id)"
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
            let a = city.vehicles[0].pose, b = city.vehicles[1].pose
            minimum = min(minimum, hypot(a.x-b.x, a.y-b.y))
        }
    }
    #expect(minimum >= 0.24)
    #expect(city.vehicles.isEmpty)
}

@Test func newTripsWaitForSpaceToJoinTheirLane() {
    var city = trafficCity()
    let south = (16...23).map { Plot(24, $0) }
    city.vehicles = [car(1000, route: south, pace: 25, distance: 2.44)]
    let addresses = [City.Address(lot: Plot(23, 18), road: Plot(24, 18), zone: .homes),
                     City.Address(lot: Plot(23, 22), road: Plot(24, 22), zone: .commerce)]
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
        if city.vehicles.count == 2 { overlap = overlap || city.vehicles[0].footprint.overlaps(city.vehicles[1].footprint) }
    }
    #expect(!overlap)
    #expect(city.vehicles.isEmpty)
}

@Test(arguments: [City.defaultSeed, 42, 99, 0, 1, 2])
func tripsUseTheLaneOnTheSameSideAsTheirDriveways(seed: UInt64) {
    var city = City(seed: seed)
    for _ in 0..<600 { city.step() }
    for vehicle in city.vehicles {
        let first = vehicle.route[0], second = vehicle.route[1]
        let end = vehicle.route.last!, previous = vehicle.route[vehicle.route.count - 2]
        let originSide = (vehicle.origin.x - first.x) * (first.y - second.y)
            + (vehicle.origin.y - first.y) * (second.x - first.x)
        let destinationSide = (vehicle.destination.x - end.x) * (previous.y - end.y)
            + (vehicle.destination.y - end.y) * (end.x - previous.x)
        #expect(originSide >= 0)
        #expect(destinationSide >= 0)
    }
}

@Test func opposingCarsCanClearAdjacentJunctions() {
    var city = trafficCity()
    for x in [23, 25] { city.map[Plot(x, 20)] = Lot(ground: .road) }
    let south = (17...23).map { Plot(24, $0) }
    let north = (16...22).reversed().map { Plot(24, $0) }
    city.vehicles = [car(0, route: south, distance: 2.13), car(1, route: north, distance: 2.13)]
    var minimum = Double.infinity
    for _ in 0..<400 {
        city.step()
        if city.vehicles.count == 2 {
            let a = city.vehicles[0].pose, b = city.vehicles[1].pose
            minimum = min(minimum, hypot(a.x-b.x, a.y-b.y))
        }
    }
    #expect(minimum >= 0.24)
    #expect(city.vehicles.isEmpty)
}

@Test func opposingCarsYieldAtABendUntilTheirBodiesClear() {
    var city = trafficCity()
    for plot in CityMap.plots { city.map[plot] = Lot() }
    let route = (21...24).map { Plot($0, 19) } + (20...23).map { Plot(24, $0) }
    for plot in route { city.map[plot] = Lot(ground: .road) }
    city.vehicles = [car(0, route: route, pace: 29, long: true, distance: 2),
                     car(1, route: Array(route.reversed()), pace: 21, distance: 3)]
    var overlap = false
    for _ in 0..<400 {
        city.step()
        if city.vehicles.count == 2 { overlap = overlap || city.vehicles[0].footprint.overlaps(city.vehicles[1].footprint) }
    }
    #expect(!overlap)
    #expect(city.vehicles.isEmpty)
}
