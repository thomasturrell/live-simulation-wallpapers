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

    package static let runwayCenter = 5.0
    package static let taxiwayCenter = 3.0
    static let touchdown = 1.2
    package static let runwayExit = 11.6
    static let departureTurn = 2.3
    package static let holdShort = SIMD2(1.2, 4.1)
    static let takeoffStart = 2.0

    package static let runway = Surface(0.1...13.4, 4.17...5.83)
    package static let taxiway = Surface(0.35...13.0, 2.22...3.80)
    package static let runwayLinks = [
        Surface(0.35...2.8, taxiwayCenter...5.2),
        Surface(10.78...13.0, taxiwayCenter...5.2),
    ]
    package static let gates = [
        Gate(stop: SIMD2(6, 1.65), pier: Surface(5.39...5.66, 0.79...1.25),
             stand: Surface(5.17...7.06, 0.84...taxiwayCenter)),
        Gate(stop: SIMD2(8.48, 1.63), pier: Surface(8.74...9.02, 0.79...1.26),
             stand: Surface(7.70...9.26, 0.84...taxiwayCenter)),
    ]
    static let boardingGate = gates[0]

    package static let forecourt = Surface((entranceCenter - 0.98)...(entranceCenter + 0.98), -0.5...0.22)
    package static let canopy = Surface((entranceCenter - 0.65)...(entranceCenter + 0.65), -0.30...0.26)
    package static let headhouse = Surface(5.58...8.65, 0.06...0.75)
    package static let concourses = [Surface(3.70...5.84, 0.36...0.85), Surface(8.38...9.82, 0.32...0.86)]
    package static let concourseEnds = [Surface(3.70...4.96, 0.75...1.46), Surface(9.26...9.82, 0.76...1.38)]
    package static let towerCenter = SIMD2(10.45, 0.32)
    package static let towerBase = Surface(10.26...10.64, 0.13...0.51)
    package static let hangarCenters = [SIMD2(1.97, 0.53), SIMD2(12.03, 0.53)]
    package static let hangarFootprints = hangarCenters.map {
        Surface(($0.x - 0.68)...($0.x + 0.68), ($0.y - 0.43)...($0.y + 0.43))
    }
    package static let hangarPavement = hangarCenters.map {
        Surface(($0.x - 0.55)...($0.x + 0.55), 0.94...taxiwayCenter)
    }

    static let operations = [runway, taxiway] + runwayLinks + gates.map(\.stand) + hangarPavement
    static let structures = [headhouse, towerBase] + concourses + concourseEnds + gates.map(\.pier) + hangarFootprints
}
