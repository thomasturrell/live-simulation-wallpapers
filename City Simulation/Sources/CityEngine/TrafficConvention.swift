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
