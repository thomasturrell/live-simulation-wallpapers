@testable import CityEngine
import Foundation
import Testing

@Test func generatedCitiesUseOrdinaryTerrain() {
    for seed in [City.defaultSeed] + (0..<64).map(UInt64.init) {
        let map = City(seed: seed).map
        #expect(map.isValid)
        #expect(map.lots.allSatisfy { $0.building?.style != 121 })
    }
}

@Test func overflightsArriveCrossTheCityAndReturnAfterAQuietPeriod() throws {
    var aviation = Aviation(seed: 42)
    let firstArrival = aviation.nextOverflight
    #expect((45 * City.ticksPerSecond...74 * City.ticksPerSecond).contains(firstArrival))
    for tick in 1..<firstArrival { aviation.step(tick: tick) }
    #expect(aviation.aircraft.isEmpty)

    aviation.step(tick: firstArrival)
    let first = try #require(aviation.aircraft.first)
    #expect(first.elapsed == 0)
    let departure = firstArrival + first.duration
    for tick in (firstArrival + 1)..<departure { aviation.step(tick: tick) }
    #expect(aviation.aircraft.first?.elapsed == first.duration - 1)
    aviation.step(tick: departure)
    #expect(aviation.aircraft.isEmpty)

    let nextArrival = aviation.nextOverflight
    #expect((85 * City.ticksPerSecond...179 * City.ticksPerSecond).contains(nextArrival - departure))
    for tick in (departure + 1)...nextArrival { aviation.step(tick: tick) }
    let next = try #require(aviation.aircraft.first)
    #expect(next.id == first.id + 1)
    #expect(next.elapsed == 0)
}

@Test(arguments: [5, 6], [false, true])
func legacyCheckpointsRestoreTheAirportSiteAndKeepOverflights(version: Int, alongY: Bool) throws {
    var city = City(trafficConvention: .rightHand)
    city.aviation.nextOverflight = 1
    for _ in 0..<325 { city.step() }
    let overflight = try #require(city.aviation.aircraft.first)
    let origin = alongY ? Plot(7, 8) : Plot(6, 8)
    let terminal = alongY ? Plot(7, 14) : Plot(12, 8)
    let footprint = Set((0..<12).flatMap { u in
        (0..<6).map { v in Plot(origin.x + (alongY ? v : u), origin.y + (alongY ? u : v)) }
    })
    let road = alongY ? (11...14).reversed().map { Plot(6, $0) } : (12...15).map { Plot($0, 7) }
    #expect(road.allSatisfy(city.map.isRoad))
    let trip = Vehicle(id: city.nextVehicle, route: road, color: 0, pace: 24, long: false,
                       origin: terminal, destination: road[3].neighbors[1], progress: 1)

    var checkpoint = try #require(PropertyListSerialization.propertyList(from: city.checkpoint(), format: nil) as? [String: Any])
    var fields = try #require(checkpoint["city"] as? [String: Any])
    var map = try #require(fields["map"] as? [String: Any])
    var lots = try #require(map["lots"] as? [[String: Any]])
    var aviation = try #require(fields["aviation"] as? [String: Any])
    var aircraft = try #require(aviation["aircraft"] as? [[String: Any]])
    var vehicles = try #require(fields["vehicles"] as? [[String: Any]])

    for point in footprint {
        let index = point.y * CityMap.side + point.x
        lots[index]["ground"] = point == terminal ? 0 : 6
        lots[index]["zone"] = Zone.civic.rawValue
        lots[index]["building"] = point == terminal ? ["level": 1, "style": 121] : nil
    }
    map["lots"] = lots
    map["airport"] = ["origin": ["x": origin.x, "y": origin.y], "alongY": alongY]
    aircraft[0]["phase"] = 10
    aircraft[0]["standTime"] = 1800
    aircraft.append(["id": overflight.id + 1, "phase": 3, "standTime": 1800,
                     "livery": 0, "lane": 0, "reverse": false, "alongY": alongY, "elapsed": 300])
    aviation["aircraft"] = aircraft
    aviation["nextID"] = overflight.id + 2
    aviation["nextArrival"] = 10
    let tripData = try PropertyListEncoder().encode(trip)
    vehicles.append(try #require(PropertyListSerialization.propertyList(from: tripData, format: nil) as? [String: Any]))
    fields["nextVehicle"] = trip.id + 1
    fields["vehicles"] = vehicles
    fields["map"] = map
    fields["aviation"] = aviation
    if version == 5 { fields.removeValue(forKey: "savedTrafficConvention") }
    checkpoint["version"] = version
    checkpoint["city"] = fields

    let data = try PropertyListSerialization.data(fromPropertyList: checkpoint, format: .binary, options: 0)
    var restored = try #require(City(checkpoint: data))
    #expect(restored.tick == city.tick)
    #expect(restored.trafficConvention == .rightHand)
    #expect(restored.construction == city.construction)
    #expect(restored.vehicles == city.vehicles)
    #expect(restored.aviation.aircraft == [overflight])
    for point in CityMap.plots {
        if footprint.contains(point) {
            #expect(restored.map[point].ground == city.map[point].ground)
            #expect(restored.map[point].zone == city.map[point].zone)
            #expect(restored.map[point].detail == city.map[point].detail)
            #expect(restored.map[point].building == nil)
        } else {
            #expect(restored.map[point] == city.map[point])
        }
    }
    var roundTrip = try #require(City(checkpoint: restored.checkpoint()))
    for _ in 0..<300 {
        restored.step()
        roundTrip.step()
    }
    #expect(restored == roundTrip)

    map["airport"] = ["origin": ["x": Int.max, "y": Int.min], "alongY": alongY]
    fields["map"] = map
    checkpoint["city"] = fields
    let corrupt = try PropertyListSerialization.data(fromPropertyList: checkpoint, format: .binary, options: 0)
    #expect(City(checkpoint: corrupt) == nil)
}

@Test func checkpointRejectsAnInvalidOverflight() throws {
    var city = City()
    city.aviation.nextOverflight = 1
    city.step()
    var checkpoint = try #require(PropertyListSerialization.propertyList(from: city.checkpoint(), format: nil) as? [String: Any])
    var fields = try #require(checkpoint["city"] as? [String: Any])
    var aviation = try #require(fields["aviation"] as? [String: Any])
    var aircraft = try #require(aviation["aircraft"] as? [[String: Any]])
    aircraft[0]["elapsed"] = try #require(city.aviation.aircraft.first).duration
    aviation["aircraft"] = aircraft
    fields["aviation"] = aviation
    checkpoint["city"] = fields
    let corrupt = try PropertyListSerialization.data(fromPropertyList: checkpoint, format: .binary, options: 0)
    #expect(City(checkpoint: corrupt) == nil)
}
