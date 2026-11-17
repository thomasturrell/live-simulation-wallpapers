import CityArt
@testable import CityEngine
import Foundation
import Testing

@Test func compactAirportUsesAboutThreeQuartersOfTheOriginalLand() {
    let airport = Airport(origin: Plot(10, 10), alongY: false)
    let fraction = Double(airport.plots.count) / Double(14 * 7)
    #expect((0.72...0.78).contains(fraction))
    #expect(airport.position(-0.5, -0.5) == SIMD2(9.5, 9.5))
    #expect(airport.position(13.5, 6.5) == SIMD2(21.5, 15.5))
}

@Test func aboutOneQuarterOfGeneratedCitiesHaveAirports() {
    let count = (0..<256).filter { City(seed: UInt64($0)).map.airport != nil }.count
    #expect((51...77).contains(count), "\(count) of 256 generated cities have airports")
}

@Test(arguments: [City.defaultSeed] + Array(0..<24).map(UInt64.init))
func airportsHaveProtectedLandAndConnectedAccess(seed: UInt64) throws {
    let city = City(seed: seed)
    let map = city.map
    guard let airport = map.airport else {
        #expect(!map.lots.contains { $0.ground == .airport })
        return
    }
    #expect(map.isValid)
    #expect(airport.plot(6, 3).distance(to: map.downtown) >= 20)
    #expect(airport.perimeter.allSatisfy(map.isRoad))
    #expect(map.roadAccess(at: airport.terminal) != nil)
    #expect(map[airport.terminal].building?.style == Airport.terminalStyle)
    #expect(airport.plots.filter { map[$0].ground == .airport }.count == Airport.length * Airport.width - 1)
    for point in airport.plots + airport.perimeter {
        #expect(map.landscape(at: point).ground == .grass)
    }
    if seed != City.defaultSeed {
        var random = CityRandom(state: seed)
        let original = CityLayout(random: &random)
        for point in CityMap.plots where [.park, .water, .bridge, .promenade].contains(original.lot(at: point).ground) {
            #expect(map[point].ground == original.lot(at: point).ground)
        }
    }
    for point in CityMap.plots where airport.isApproach(point) { #expect(map[point].building == nil) }
    let roads = Set(CityMap.plots.filter(map.isRoad))
    let start = try #require(roads.first)
    var visited: Set<Plot> = [start]
    var queue = [start]
    while let point = queue.popLast() {
        for next in point.neighbors where roads.contains(next) && visited.insert(next).inserted { queue.append(next) }
    }
    #expect(visited == roads)
}

@Test func airportsAreOptionalAndDoNotDisplaceProtectedLandWhenSpaceIsTight() {
    let cities = (0..<12).map { City(seed: UInt64($0)) }
    #expect(cities.contains { $0.map.airport == nil })
    #expect(cities.contains { $0.map.airport != nil })
    var map = cities[0].map
    map.airport = nil
    for point in CityMap.plots { map[point] = Lot(ground: .park) }
    let before = map
    var random = CityRandom(state: 42)
    map.planAirport(random: &random, optional: false)
    #expect(map == before)
}

@Test(arguments: [false, true])
func flightsCompleteAContinuousCycleWithParkingAndQuietPeriods(alongY: Bool) throws {
    let airport = Airport(origin: Plot(10, 10), alongY: alongY)
    var aviation = Aviation(seed: 42)
    aviation.nextArrival = 1
    aviation.nextOverflight = 100_000
    var phases: Set<Aircraft.Phase> = []
    var previous: Aircraft.Pose?
    var speeds: [Aircraft.Phase: [Double]] = [:]
    var parkedTicks = 0
    var departureTick = 0
    for tick in 1..<9_000 {
        _ = aviation.step(tick: tick, darkness: 0, airport: airport)
        guard let flight = aviation.aircraft.first else {
            if previous != nil { departureTick = tick; break }
            continue
        }
        phases.insert(flight.phase)
        let pose = flight.pose(at: airport)
        #expect(pose.x.isFinite && pose.y.isFinite && pose.altitude.isFinite)
        #expect(abs(hypot(pose.dx, pose.dy) - 1) < 0.0001)
        if let previous {
            let distance = hypot(pose.x - previous.x, pose.y - previous.y)
            #expect(distance < 0.08)
            #expect(abs(pose.altitude - previous.altitude) < 0.3)
            #expect(pose.dx * previous.dx + pose.dy * previous.dy > 0.96, "Heading at \(flight.phase), tick \(flight.elapsed)")
            if flight.elapsed > 0 { speeds[flight.phase, default: []].append(distance) }
            if [.taxiIn, .parked, .pushback, .taxiOut, .holdingShort, .lineUp].contains(flight.phase) {
                #expect(pose.altitude == 0)
                #expect(airport.contains(Plot(Int(pose.x.rounded()), Int(pose.y.rounded()))))
            }
        }
        if flight.phase == .parked { parkedTicks += 1 }
        previous = pose
    }
    #expect(phases == Set(Aircraft.Phase.allCases.filter { $0 != .overflight }))
    #expect((45 * City.ticksPerSecond...95 * City.ticksPerSecond).contains(parkedTicks))
    #expect(departureTick > 0)
    let landing = try #require(speeds[.landing])
    let takeoff = try #require(speeds[.takeoff])
    #expect(landing.first! > landing.last! * 6)
    #expect(takeoff.last! > takeoff.first! * 12)
    for tick in departureTick + 1..<departureTick + 45 * City.ticksPerSecond {
        _ = aviation.step(tick: tick, darkness: 0, airport: airport)
        #expect(aviation.aircraft.isEmpty)
    }
    for tick in departureTick + 45 * City.ticksPerSecond...aviation.nextArrival {
        _ = aviation.step(tick: tick, darkness: 0, airport: airport)
    }
    #expect(aviation.aircraft.first?.phase == .approach)
}

@Test func airportHasLongerQuietPeriodsAtNight() throws {
    let airport = Airport(origin: Plot(10, 10), alongY: false)
    var day = Aviation(seed: 42)
    day.nextArrival = 1
    day.nextOverflight = 100_000
    _ = day.step(tick: 1, darkness: 0, airport: airport)
    day.aircraft[0].phase = .climb
    day.aircraft[0].elapsed = day.aircraft[0].duration - 1
    var night = day
    _ = day.step(tick: 2, darkness: 0, airport: airport)
    _ = night.step(tick: 2, darkness: 1, airport: airport)
    #expect(day.aircraft.isEmpty && night.aircraft.isEmpty)
    #expect(night.nextArrival - day.nextArrival == 75 * City.ticksPerSecond)
}

@Test func citiesWithoutAirportsStillHaveOccasionalOverflights() {
    var aviation = Aviation(seed: 17)
    var flights: Set<UInt64> = []
    var quietTicks = 0
    for tick in 1...12_000 {
        let events = aviation.step(tick: tick, darkness: 0, airport: nil)
        #expect(events.isEmpty)
        #expect(aviation.aircraft.count <= 1)
        if aviation.aircraft.isEmpty { quietTicks += 1 }
        for flight in aviation.aircraft {
            #expect(flight.phase == .overflight)
            #expect(flight.pose(at: nil).altitude > 60)
            flights.insert(flight.id)
        }
    }
    #expect(flights.count >= 2)
    #expect(quietTicks > 6_000)
}

@Test func airportJourneysAndEveryFlightPhaseSurviveCheckpointAndCityGrowth() throws {
    var city = City()
    let airport = try #require(city.map.airport)
    let original = airport.plots.map { city.map[$0] }
    var phases: Set<Aircraft.Phase> = []
    var inboundPassengers = false
    var outboundPassengers = false
    for _ in 0..<8_000 {
        city.step()
        inboundPassengers = inboundPassengers || city.vehicles.contains { $0.destination == airport.terminal }
        outboundPassengers = outboundPassengers || city.vehicles.contains { $0.origin == airport.terminal }
        for aircraft in city.aviation.aircraft where phases.insert(aircraft.phase).inserted {
            var restored = try #require(City(checkpoint: city.checkpoint()))
            #expect(restored == city)
            var advanced = city
            for _ in 0..<60 { restored.step(); advanced.step() }
            #expect(restored == advanced)
        }
    }
    #expect(phases == Set(Aircraft.Phase.allCases))
    #expect(inboundPassengers && outboundPassengers)
    #expect(city.revision > 5)
    #expect(city.map.airport == airport)
    #expect(airport.plots.map { city.map[$0] } == original)
    for point in CityMap.plots where airport.isApproach(point) { #expect(city.map[point].building == nil) }
}

@Test func legacyCitiesRestoreWithoutRegeneratingTheirMap() throws {
    var city = try #require((0..<12).map { City(seed: UInt64($0)) }.first { $0.map.airport == nil })
    for _ in 0..<390 { city.step() }
    var plist = try #require(PropertyListSerialization.propertyList(from: city.checkpoint(), format: nil) as? [String: Any])
    var oldCity = try #require(plist["city"] as? [String: Any])
    var oldMap = try #require(oldCity["map"] as? [String: Any])
    oldCity.removeValue(forKey: "aviation")
    oldMap.removeValue(forKey: "airport")
    oldCity["map"] = oldMap
    plist["version"] = 2
    plist["city"] = oldCity
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    let restored = try #require(City(checkpoint: data))
    #expect(restored.map == city.map)
    #expect(restored.vehicles == city.vehicles)
    #expect(restored.construction == city.construction)
    #expect(restored.tick == city.tick)
    #expect(restored.aviation.aircraft.isEmpty)
    #expect(City(checkpoint: try restored.checkpoint()) == restored)
}

@Test func originalAirportCheckpointsShrinkWithoutResettingTheCityOrTrips() throws {
    var city = City()
    for _ in 0..<90 { city.step() }
    city.vehicles = []
    for point in CityMap.plots where city.map[point].ground == .airport || city.map[point].building?.style == Airport.terminalStyle {
        var lot = city.map[point]
        lot.ground = .grass
        lot.zone = .homes
        lot.building = nil
        city.map[point] = lot
    }
    let airport = Airport(origin: Plot(7, 33), alongY: false)
    city.map.airport = airport
    let oldPlots = (0..<14).flatMap { u in (0..<7).map { airport.plot(u, $0) } }
    let oldPerimeter = (-1...14).flatMap { u in
        (-1...7).filter { u == -1 || u == 14 || $0 == -1 || $0 == 7 }.map { airport.plot(u, $0) }
    }
    for point in oldPlots + oldPerimeter {
        var lot = city.map[point]
        lot.ground = oldPlots.contains(point) ? .airport : .road
        lot.zone = .civic
        lot.building = nil
        city.map[point] = lot
    }
    city.map[airport.terminal].ground = .grass
    city.map[airport.terminal].building = Building(level: 1, style: Airport.terminalStyle)
    city.dispatchAirportTraffic(toAirport: true)
    #expect(!city.vehicles.isEmpty)
    var plist = try #require(PropertyListSerialization.propertyList(from: city.checkpoint(), format: nil) as? [String: Any])
    plist["version"] = 3
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    var restored = try #require(City(checkpoint: data))
    #expect(restored.tick == city.tick)
    #expect(restored.vehicles == city.vehicles)
    #expect(restored.aviation == city.aviation)
    #expect(restored.map.airport == airport)
    #expect(oldPerimeter.allSatisfy(restored.map.isRoad))
    for point in CityMap.plots where !oldPlots.contains(point) { #expect(restored.map[point] == city.map[point]) }
    for point in oldPlots where !airport.contains(point) {
        #expect(restored.map[point].ground == .grass)
        #expect(restored.map[point].zone == .homes)
    }
    #expect(CityMap.plots.filter { restored.map[$0].ground == .airport }.count == Airport.length * Airport.width - 1)
    for _ in 0..<120 { restored.step() }
    #expect(City(checkpoint: try restored.checkpoint()) == restored)
}

@Test func checkpointsRejectInvalidAircraftAndAirportGeometry() throws {
    var city = City()
    while city.aviation.aircraft.isEmpty { city.step() }
    let plist = try #require(PropertyListSerialization.propertyList(from: city.checkpoint(), format: nil) as? [String: Any])
    for corruptAirport in [false, true] {
        var modified = plist
        var savedCity = try #require(modified["city"] as? [String: Any])
        if corruptAirport {
            var map = try #require(savedCity["map"] as? [String: Any])
            var airport = try #require(map["airport"] as? [String: Any])
            airport["origin"] = ["x": Int.max, "y": Int.min]
            map["airport"] = airport
            savedCity["map"] = map
        } else {
            var aviation = try #require(savedCity["aviation"] as? [String: Any])
            var aircraft = try #require(aviation["aircraft"] as? [[String: Any]])
            aircraft[0]["elapsed"] = -1
            aviation["aircraft"] = aircraft
            savedCity["aviation"] = aviation
        }
        modified["city"] = savedCity
        let data = try PropertyListSerialization.data(fromPropertyList: modified, format: .binary, options: 0)
        #expect(City(checkpoint: data) == nil)
    }
}
