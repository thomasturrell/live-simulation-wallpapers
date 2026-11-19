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
    #expect(map.isRoad(airport.entrance))
    #expect(map.roadAccess(at: airport.terminal) == airport.entrance)
    #expect(airport.plots.allSatisfy { !map.isRoad($0) })
    #expect(map[airport.terminal].building?.style == Airport.terminalStyle)
    #expect(airport.plots.filter { map[$0].ground == .airport }.count == Airport.length * Airport.width - 1)
    for point in airport.plots + [airport.entrance] {
        #expect(map.landscape(at: point).ground == .grass)
    }
    if seed != City.defaultSeed {
        var random = CityRandom(state: seed)
        let original = CityLayout(random: &random)
        for point in CityMap.plots where [.park, .water, .bridge, .promenade].contains(original.lot(at: point).ground) {
            #expect(map[point].ground == original.lot(at: point).ground)
        }
        let added = CityMap.plots.filter { map.isRoad($0) && !original.lot(at: $0).ground.carriesTraffic }
        let column = airport.local(airport.entrance).u
        #expect(added.count <= 2)
        for point in added {
            let local = airport.local(point)
            #expect(local.u == column && (-2 ... -1).contains(local.v))
            #expect(!map.isRoad(airport.plot(column - 1, local.v)))
            #expect(!map.isRoad(airport.plot(column + 1, local.v)))
        }
        #expect(City(seed: seed) == city)
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

@Test(arguments: [false, true])
func accessReusesExistingStreetsAndRejectsParallelSpurs(alongY: Bool) {
    var map = City().map
    for point in CityMap.plots { map[point] = Lot() }
    let airport = Airport(origin: Plot(7, 7), alongY: alongY)
    let column = airport.local(airport.entrance).u
    let second = airport.plot(column, -2)
    map[airport.plot(column, -3)] = Lot(ground: .road)
    #expect(map.airportAccessRoad(for: airport) == [airport.entrance, second])
    for v in [-2, -1] { map[airport.plot(column + 1, v)] = Lot(ground: .road) }
    #expect(map.airportAccessRoad(for: airport) == nil)
    map[airport.entrance] = Lot(ground: .road)
    #expect(map.airportAccessRoad(for: airport) == [])
    map[airport.entrance] = Lot(ground: .promenade)
    #expect(map.airportAccessRoad(for: airport) == nil)
}

@Test(arguments: [false, true], [false, true])
func placementTrimsLocalStreetsButRejectsSitesThatWouldSeverThem(alongY: Bool, atJunction: Bool) {
    var map = City().map
    map.airport = nil
    let airport = Airport(origin: Plot(7, 7), alongY: alongY, stage: .airfield)
    let column = airport.local(airport.entrance).u
    for point in CityMap.plots { map[point] = Lot(ground: airport.contains(point) ? .grass : .park) }
    for v in -3...3 { map[airport.plot(-2, v)] = Lot(ground: .road) }
    for u in -2...column { map[airport.plot(u, -3)] = Lot(ground: .road) }
    for v in [-2, -1] { map[airport.plot(column, v)] = Lot() }
    for u in -2...Airport.length { map[airport.plot(u, 3)] = Lot(ground: .road) }
    if atJunction { map[airport.plot(-3, 3)] = Lot(ground: .road) }
    let severed = map
    var random = CityRandom(state: 42)
    map.planAirport(random: &random, optional: false)
    #expect(map == severed)

    // If that street ends within the site, trimming it leaves every surviving road connected.
    map[airport.plot(Airport.length, 3)] = Lot(ground: .park)
    var roads = Set(CityMap.plots.filter(map.isRoad).filter { !airport.contains($0) })
    if atJunction { roads.remove(airport.plot(-1, 3)) }
    map.planAirport(random: &random, optional: false)
    #expect(map.airport == airport)
    #expect(Set(CityMap.plots.filter(map.isRoad)) == roads.union([airport.entrance, airport.plot(column, -2)]))
    #expect(map.route(from: airport.entrance, to: airport.plot(-2, 3)) != nil)
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

@Test(arguments: [false, true], Aircraft.Kind.allCases)
func flightsCompleteAContinuousCycleWithParkingAndQuietPeriods(alongY: Bool, kind: Aircraft.Kind) throws {
    let airport = Airport(origin: Plot(10, 10), alongY: alongY, stage: kind == .lightProp ? .airfield : .regional)
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
        if tick == 1, kind == .turboprop {
            aviation.aircraft[0].airframe = kind
            aviation.aircraft[0].gate = 1
        }
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
        if flight.phase == .parked {
            parkedTicks += 1
            let stop = Airport.gates[flight.standIndex].stop
            #expect(SIMD2(pose.x, pose.y) == airport.position(stop.x, stop.y))
        }
        if pose.altitude == 0 {
            #expect(aircraftClearsAirfield(pose, kind: kind, airport: airport, holding: flight.phase == .holdingShort),
                    "Clearance at \(flight.phase), tick \(flight.elapsed)")
        }
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

private func aircraftClearsAirfield(_ pose: Aircraft.Pose, kind: Aircraft.Kind, airport: Airport, holding: Bool) -> Bool {
    // Sample an envelope around the nose, wings and tailplane in sprite pixels.
    let outline: [SIMD2<Double>]
    if kind == .jet {
        outline = [SIMD2(11, 0), SIMD2(8, 1.5), SIMD2(-4, 11), SIMD2(-6, 11), SIMD2(-11, 5),
                   SIMD2(-11, -5), SIMD2(-6, -11), SIMD2(-4, -11), SIMD2(8, -1.5)]
    } else {
        let nose = kind == .turboprop ? 8.8 : 6.2
        let wing = kind == .turboprop ? 9.5 : 6.6
        outline = [SIMD2(nose, 0), SIMD2(0.4, wing), SIMD2(-1.8, wing), SIMD2(-nose, 3.1),
                   SIMD2(-nose, -3.1), SIMD2(-1.8, -wing), SIMD2(0.4, -wing)]
    }
    let obstacles = airport.structures + [Airport.forecourt, Airport.parking,
                                          Airport.Surface(1.32...2.12, 1.24...2.08)] + (holding ? [Airport.runway] : [])
    let operations = airport.operations
    let center = airport.designPosition(SIMD2(pose.x, pose.y))
    let forward = (airport.alongY ? SIMD2(pose.dy, pose.dx) : SIMD2(pose.dx, pose.dy)) / 16
    let side = SIMD2(-forward.y, forward.x)
    for (a, b) in zip(outline, outline.dropFirst() + outline.prefix(1)) {
        for step in 0...8 {
            let edge = a + (b - a) * (Double(step) / 8)
            let tip = forward * edge.x + side * edge.y
            for radius in [0.25, 0.5, 0.75, 1.0] {
                let point = center + tip * radius
                if !operations.contains(where: { $0.contains(point) }) ||
                    obstacles.contains(where: { $0.contains(point) }) { return false }
            }
        }
    }
    return true
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

@Test(arguments: [City.defaultSeed, 202], [TrafficConvention.uk, .rightHand])
func airportJourneysAndEveryFlightPhaseSurviveCheckpointAndCityGrowth(seed: UInt64, convention: TrafficConvention) throws {
    var city = City(seed: seed, trafficConvention: convention)
    let airport = try #require(city.map.airport)
    let original = airport.plots.map { city.map[$0] }
    var phases: Set<Aircraft.Phase> = []
    var inboundPassengers = false
    var outboundPassengers = false
    for _ in 0..<8_000 {
        city.step()
        inboundPassengers = inboundPassengers || city.vehicles.contains {
            $0.destination == airport.terminal && $0.route.last == airport.entrance
        }
        outboundPassengers = outboundPassengers || city.vehicles.contains {
            $0.origin == airport.terminal && $0.route.first == airport.entrance
        }
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
    #expect(city.map.airport?.origin == airport.origin)
    #expect(city.map.airport?.alongY == airport.alongY)
    #expect(airport.plots.map { city.map[$0] } == original)
    for point in CityMap.plots where airport.isApproach(point) { #expect(city.map[point].building == nil) }
}

@Test(arguments: [215, 202] as [UInt64])
func airportDevelopmentSharesTheCityClockAndSurvivesWorksiteRestores(seed: UInt64) throws {
    var city = City(seed: seed)
    let airport = try #require(city.map.airport)
    #expect(airport.stage == .airfield)
    let reserved = airport.plots.map { city.map[$0] }
    let street = try #require(airport.entrance.neighbors.first(where: city.map.isRoad))
    let access = try #require(city.map.route(from: airport.entrance, to: street))
    var projects: [Construction] = []
    var stages: [Airport.Stage] = [.airfield]
    var visits: Set<Aircraft.Kind> = []
    for _ in 0..<27_000 {
        city.step()
        let current = try #require(city.map.airport)
        if current.stage != stages.last { stages.append(current.stage) }
        for flight in city.aviation.aircraft where flight.phase == .parked {
            visits.insert(flight.kind)
        }
        if let project = city.construction, project.airportUpgrade != nil {
            #expect(city.aviation.runwayFree)
            if projects.last != project {
                projects.append(project)
                var restored = try #require(City(checkpoint: city.checkpoint()))
                var uninterrupted = city
                for _ in city.tick...project.finish { restored.step(); uninterrupted.step() }
                #expect(restored == uninterrupted)
                #expect(restored.map.airport?.stage == project.airportUpgrade)
            }
        }
        if current.stage == .regional { break }
    }
    #expect(stages == [.airfield, .local, .regional])
    #expect(visits == [.lightProp, .turboprop])
    #expect(projects.compactMap(\.airportUpgrade) == [.local, .regional])
    #expect(city.map.roadAccess(at: airport.terminal) == airport.entrance)
    #expect(city.map.route(from: airport.entrance, to: street) == access)
    #expect(airport.plots.map { city.map[$0] } == reserved)
}

@Test func serviceCartStaysInTheServiceYardAndReturnsBetweenFlights() {
    let airport = Airport(origin: Plot(10, 10), alongY: true)
    let rest = airport.serviceCart(parkedFor: nil)
    #expect(airport.serviceCart(parkedFor: 20 * City.ticksPerSecond) != rest)
    #expect(airport.serviceCart(parkedFor: 42 * City.ticksPerSecond) == rest)
    for second in 0...45 {
        let point = airport.designPosition(airport.serviceCart(parkedFor: second * City.ticksPerSecond))
        #expect(Airport.serviceYard.contains(point))
        #expect(!Airport.taxiway.contains(point))
    }
}

@Test func formatFiveAirportsWithoutDevelopmentRestoreAsMature() throws {
    let city = City(seed: 215, trafficConvention: .rightHand)
    let original = try #require(city.map.airport)
    var plist = try #require(PropertyListSerialization.propertyList(from: city.checkpoint(), format: nil) as? [String: Any])
    var savedCity = try #require(plist["city"] as? [String: Any])
    var map = try #require(savedCity["map"] as? [String: Any])
    var airport = try #require(map["airport"] as? [String: Any])
    plist["version"] = 5
    savedCity.removeValue(forKey: "savedTrafficConvention")
    airport.removeValue(forKey: "stage")
    map["airport"] = airport
    savedCity["map"] = map
    plist["city"] = savedCity
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    let restored = try #require(City(checkpoint: data))
    #expect(restored.map.airport?.stage == .regional)
    #expect(restored.trafficConvention == .rightHand)
    #expect(restored.map.airport?.entrance == original.entrance)
    #expect(restored.map.lots == city.map.lots)
    #expect(restored.vehicles == city.vehicles)
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

@Test(arguments: [City.defaultSeed, 202])
func checkpointsRequireTheTerminalEntrance(seed: UInt64) throws {
    var city = City(seed: seed)
    let airport = try #require(city.map.airport)
    let column = airport.local(airport.entrance).u
    city.map[airport.entrance] = Lot()
    // A street beside the terminal frontage is no substitute for the designated entrance.
    city.map[airport.plot(column - 1, -1)] = Lot(ground: .road)
    #expect(city.map.roadAccess(at: airport.terminal) == nil)
    #expect(City(checkpoint: try city.checkpoint()) == nil)
}
