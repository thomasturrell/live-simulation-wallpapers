@testable import CityArt
import CityEngine
import Foundation
import Testing

private let displayUUIDs = [
    "70F239C2-D6FC-4B58-BB3F-02FAA45FE309",
    "70F239C2-D6FC-4B58-BB3F-02FAA45FE302",
    "70F239C2-D6FC-4B58-BB3F-02FAA45FE301",
    "70F239C2-D6FC-4B58-BB3F-02FAA45FE308"
].map { UUID(uuidString: $0)! }

@Test func displayUUIDRecreatesTheStartingCityInAnyOrder() {
    let first = displayUUIDs.map { City(displayUUID: $0) }
    let reversed = displayUUIDs.reversed().map { City(displayUUID: $0) }
    #expect(first == Array(reversed.reversed()))
    #expect(City(displayUUID: nil) == City())
}

@Test func sampleDisplaysDifferWithinTheWallpaperCrop() {
    let viewport = CityViewport(pixelWidth: 2560, pixelHeight: 1440)
    let visible = CityMap.plots.filter {
        let pixel = viewport.project($0)
        return (0..<viewport.width).contains(pixel.x) && (0..<viewport.height).contains(pixel.y)
    }
    let layouts = displayUUIDs.map { uuid in
        let map = City(displayUUID: uuid).map
        return (
            river: Set(visible.filter { [.water, .bridge].contains(map[$0].ground) }),
            bridges: Set(visible.filter { map[$0].ground == .bridge }),
            streets: Set(visible.filter { map[$0].ground == .road })
        )
    }
    for (index, first) in layouts.enumerated() {
        for second in layouts.dropFirst(index + 1) {
            #expect(first.river.symmetricDifference(second.river).count >= 60)
            #expect(first.bridges.symmetricDifference(second.bridges).count >= 4)
            #expect(first.streets.symmetricDifference(second.streets).count >= 120)
        }
    }
}

@Test(arguments: displayUUIDs)
func generatedCitiesSupportCrossRiverTrafficAndConstruction(uuid: UUID) throws {
    var city = City(displayUUID: uuid)
    let map = city.map
    let roads = Set(CityMap.plots.filter(map.isRoad))
    let start = try #require(CityMap.plots.first(where: map.isRoad))
    var seen: Set<Plot> = [start]
    var queue = [start]
    while let point = queue.popLast() {
        for neighbor in point.neighbors where roads.contains(neighbor) && seen.insert(neighbor).inserted {
            queue.append(neighbor)
        }
    }
    #expect(seen == roads)

    let bridges = Dictionary(grouping: CityMap.plots.filter { map[$0].ground == .bridge }, by: \.y)
    #expect(bridges.count >= 2)
    for span in bridges.values {
        let west = try #require(span.first)
        let east = try #require(span.last)
        let route = map.route(from: Plot(west.x - 1, west.y), to: Plot(east.x + 1, east.y))
        #expect(route?.filter { map[$0].ground == .bridge } == span)
    }

    let initialIDs = Set(city.vehicles.map(\.id))
    #expect(city.vehicles.contains { $0.route.contains { map[$0].ground == .bridge } })
    for _ in 0..<600 { city.step() }
    #expect(city.revision > 0)
    #expect(city.vehicles.contains { !initialIDs.contains($0.id) })
    for vehicle in city.vehicles {
        #expect(city.map.route(from: vehicle.route[0], to: vehicle.route.last!) == vehicle.route)
        #expect(city.map[vehicle.origin].building != nil)
        #expect(city.map[vehicle.destination].building != nil)
    }
    for point in CityMap.plots {
        guard let building = city.map[point].building else { continue }
        #expect(city.map.roadAccess(at: point) != nil)
        #expect((1...city.map.capacity(at: point)).contains(building.level))
    }
}
