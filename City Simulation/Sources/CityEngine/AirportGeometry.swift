import Foundation

extension Airport {
    /// Coordinates are in the 14 × 7 airport design space used by position(_:_:).
    package struct Surface {
        package let u: ClosedRange<Double>
        package let v: ClosedRange<Double>

        package init(_ u: ClosedRange<Double>, _ v: ClosedRange<Double>) {
            self.u = u
            self.v = v
        }

        func contains(_ point: SIMD2<Double>) -> Bool { u.contains(point.x) && v.contains(point.y) }
    }

    package struct Gate {
        package let stop: SIMD2<Double>
        package let pier: Surface
        package let stand: Surface
    }

    package var openGates: ArraySlice<Gate> {
        Airport.gates.prefix(stage == .regional ? 2 : 1)
    }

    package static let runwayCenter = 5.0
    package static let taxiwayCenter = 3.0
    static let touchdown = 1.2
    package static let runwayExit = 11.6
    static let departureTurn = 2.3
    package static let holdShort = SIMD2(1.2, 3.32)
    static let takeoffStart = 2.0

    package static let runway = Surface(0.1...13.4, 4.17...5.83)
    package static let taxiway = Surface(0.35...13.0, 2.22...3.80)
    package static let runwayLinks = [
        Surface(0.35...2.8, taxiwayCenter...5.2),
        Surface(10.78...13.0, taxiwayCenter...5.2),
    ]
    package static let firstApron = Surface(5.11...7.20, 0.87...taxiwayCenter)
    package static let regionalApron = Surface(7.20...9.43, 0.87...taxiwayCenter)
    package static let gates = [
        Gate(stop: SIMD2(6, 1.65), pier: Surface(5.42...5.70, 0.83...1.24), stand: firstApron),
        Gate(stop: SIMD2(8.48, 1.65), pier: Surface(8.80...9.10, 0.86...1.26), stand: regionalApron),
    ]

    package static let forecourt = Surface(4.27...8.02, -0.5...0.12)
    package static let parking = Surface(3.05...5.04, -0.32...1.37)
    package static let canopy = Surface(6.47...7.80, -0.40...0.32)
    package static let clubhouse = Surface(6.53...7.88, 0.10...0.79)
    package static let headhouse = Surface(5.52...8.85, 0.10...0.88)
    package static let lounge = Surface(5.10...5.58, 0.40...1.18)
    package static let concourse = Surface(8.81...9.87, 0.26...0.93)
    package static let towerCenter = SIMD2(4.45, 1.79)
    package static let towerBase = Surface(4.19...4.71, 1.53...2.05)
    package static let towerCab = Surface(4.02...4.88, 1.36...2.18)
    package static let hangar = Surface(0.79...2.67, -0.03...1.19)
    package static let hangarRamp = Surface(0.86...2.65, 1.18...taxiwayCenter)
    package static let parkedProp = SIMD2(1.72, 1.66)
    package var parkedPropPlot: Plot { designPlot(Self.parkedProp.x, Self.parkedProp.y) }
    package var parkedPropPose: Aircraft.Pose {
        let position = position(Self.parkedProp.x, Self.parkedProp.y)
        return Aircraft.Pose(x: position.x, y: position.y, dx: alongY ? 0 : 1, dy: alongY ? 1 : 0,
                             altitude: 0, bank: 0, gear: true)
    }
    package static let workshop = Surface(11.22...12.68, 0.08...1.04)
    package static let serviceYard = Surface(10.94...12.87, 0.87...2.17)
    package static let windsock = SIMD2(3.49, 3.96)

    package static func worksite(for stage: Stage) -> Surface {
        stage == .local ? towerBase : concourse
    }

    package func serviceCart(parkedFor ticks: Int?) -> SIMD2<Double> {
        let seconds = Double(ticks ?? 0) / Double(City.ticksPerSecond)
        let progress = max(0, min(1, (seconds - 7) / 9, (33 - seconds) / 9))
        return position(12.63 - 1.48 * progress, 1.62)
    }

    var operations: [Surface] {
        [Self.runway, Self.taxiway, Self.hangarRamp, Self.firstApron] + Self.runwayLinks +
            (stage == .regional ? [Self.regionalApron, Self.serviceYard] : [])
    }

    var structures: [Surface] {
        switch stage {
        case .airfield: return [Self.hangar, Self.clubhouse]
        case .local: return [Self.hangar, Self.headhouse, Self.lounge, Self.towerCab, Self.gates[0].pier]
        case .regional: return [Self.hangar, Self.headhouse, Self.lounge, Self.towerCab,
                                Self.concourse, Self.workshop] + openGates.map(\.pier)
        }
    }
}
