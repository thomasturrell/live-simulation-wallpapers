package enum TrafficConvention: String, CaseIterable, Codable, Sendable {
    case uk
    case rightHand = "right"

    package static let `default`: Self = .uk

    package func laneNormal(x: Int, y: Int) -> SIMD2<Int> {
        switch self {
        case .uk: SIMD2(y, -x)
        case .rightHand: SIMD2(-y, x)
        }
    }
}

package enum RoadGeometry {
    package static let tileSize = 16
    // The stop line sits two ground pixels back from the crossing's tile.
    package static let stopLineOffset = 10
    static let stopLineDistance = Double(stopLineOffset) / Double(tileSize)
}

/// The road and adjoining lot orient the parking space for both traffic and artwork.
package struct ParkingAccess: Hashable {
    package let road: Plot
    package let lot: Plot
    package let isDriveway: Bool
    package var offset: Double { isDriveway ? 15 : 7.5 }

    package init(road: Plot, lot: Plot, isDriveway: Bool = false) {
        self.isDriveway = isDriveway
        self.road = road
        self.lot = lot
    }

    package var outward: SIMD2<Int> { SIMD2(lot.x - road.x, lot.y - road.y) }
    var center: SIMD2<Double> { SIMD2(Double(road.x), Double(road.y)) + SIMD2<Double>(outward) * (offset / Double(RoadGeometry.tileSize)) }

    func heading(in convention: TrafficConvention, departing: Bool = false) -> SIMD2<Double> {
        if isDriveway { return SIMD2<Double>(outward) * (departing ? -1 : 1) }
        return -SIMD2<Double>(convention.laneNormal(x: outward.x, y: outward.y))
    }
}
