import CityEngine
import Foundation

extension Pixels {
    mutating func car(at p: Dot, pose: Vehicle.Pose, color: Int, long: Bool, palette c: Palette) {
        let hue: UInt32 = [0xD67C56, 0xE4BB77, 0xC5BBA8, 0x739A98, 0xA85C55, 0x8B8CA2, 0xCFD1BB, 0x72939D][color]
        let body = c.color(hue)
        if c.skin == .contemporary {
            contemporaryVehicle(at: p, pose: pose, long: long, body: body, palette: c)
            return
        }
        let alongX = abs(pose.dx) >= abs(pose.dy)
        let rightward = alongX ? pose.dx >= 0 : pose.dy < 0
        let slope = alongX ? 1 : -1
        let half = pose.visibility < 0.65 ? 2 : long ? 5 : 3
        let windshield = c.color(0x44646D, 0x4B6070)
        let left = p.offset(-half, -(half * slope) / 2)
        let right = p.offset(half, (half * slope) / 2)
        line(left.offset(0, 1), right.offset(0, 1), c.roadEdge)
        line(left.offset(0, -1), right.offset(0, -1), body)
        line(left.offset(0, -2), right.offset(0, -2), body.mix(c.curb, 0.33))
        let cab = p.offset((rightward ? 1 : -1) * (long ? 2 : 1), -2)
        line(cab, cab.offset(1, slope > 0 ? 1 : 0), windshield)
        if c.night > 0.4 {
            let head = rightward ? right : left
            let tail = rightward ? left : right
            span(head.x, head.x + 1, head.y, c.gold)
            span(tail.x, tail.x, tail.y, c.color(0xC56D59, 0xBC654D))
        }
    }

    private mutating func contemporaryVehicle(at p: Dot, pose: Vehicle.Pose, long: Bool, body: Ink, palette c: Palette) {
        let magnitude = hypot(pose.dx, pose.dy)
        let dx = magnitude > 0 ? pose.dx / magnitude : 1
        let dy = magnitude > 0 ? pose.dy / magnitude : 0
        let length = pose.visibility < 0.65 ? 1.75 : long ? 4.9 : 3.0
        let width = pose.visibility < 0.65 ? 0.85 : long ? 1.35 : 1.25
        let side = dx >= dy ? 1.0 : -1.0
        let facesFront = dx + dy >= 0

        // Longitudinal coordinates run from -1 at the tail to +1 at the nose.
        // Project every face from the same footprint, including on curved driveways.
        func point(_ along: Double, _ across: Double, _ height: Double) -> Dot {
            let u = dx * along * length - dy * across * width
            let v = dy * along * length + dx * across * width
            return p.projectedOffset(u - v, (u + v) * 0.5 - height)
        }
        func deck(_ back: Double, _ front: Double, _ breadth: Double, _ z: Double) -> [Dot] {
            [point(back, side * breadth, z), point(front, side * breadth, z),
             point(front, -side * breadth, z), point(back, -side * breadth, z)]
        }
        let end = facesFront ? 1 : 0
        let farEnd = facesFront ? 2 : 3
        func shell(_ pixels: inout Pixels, base: [Dot], roof: [Dot], sideTone: Ink, endTone: Ink, roofTone: Ink) {
            pixels.polygon([base[0], base[1], roof[1], roof[0]], sideTone)
            pixels.polygon([base[end], base[farEnd], roof[farEnd], roof[end]], endTone)
            pixels.polygon(roof, roofTone)
        }
        shell(&self, base: deck(-1, 1, 1, 0.25), roof: deck(-1, 1, 1, 1.1),
              sideTone: body.mix(c.outline, 0.35), endTone: body.mix(c.outline, 0.5), roofTone: body)
        let tyre = c.color(0x333D48)
        if abs(dx - dy) > 0.20 {
            for axle in [-0.65, 0.65] {
                oval(at: point(axle, side, 0.48), radiusX: 0.52, radiusY: 0.52, top: tyre, bottom: c.roadEdge)
            }
        }

        func cabin(_ pixels: inout Pixels) {
            let back = long ? 0.35 : -0.78, front = long ? 0.95 : 0.62
            let glass = c.color(0x365B70, 0x35495F)
            shell(&pixels, base: deck(back, front, 0.91, 1.1),
                  roof: deck(back + 0.12, front - 0.19, 0.75, long ? 2.55 : 2.15),
                  sideTone: glass, endTone: glass.mix(c.curb, 0.27), roofTone: body.mix(c.shore, 0.42))
            if !long {
                pixels.line(point(-0.18, side * 0.91, 1.1), point(-0.18, side * 0.75, 2.15),
                            body.mix(c.outline, 0.25), width: 0.27)
            }
        }
        // Cab and cargo box overlap in projection. Paint the nearer one last.
        if !facesFront { cabin(&self) }
        if long {
            let metal = c.color(0xB7C4C5, 0x718093)
            shell(&self, base: deck(-0.97, 0.28, 0.98, 1.1), roof: deck(-0.97, 0.28, 0.98, 2.9),
                  sideTone: metal.mix(body, 0.32), endTone: metal.mix(c.outline, 0.35), roofTone: metal)
        }
        if facesFront { cabin(&self) }
        if c.night > 0.3 {
            let bumper = facesFront ? 1.0 : -1.0
            let tailLight = c.color(0xA54F46, 0xE95D47)
            let lamp = facesFront ? c.gold : tailLight
            for edge in [-1.0, 1.0] {
                line(point(bumper, edge * 0.51, 0.77), point(bumper, edge * 0.89, 0.77), lamp, width: 0.52)
            }
            if abs(dx - dy) > 0.35 {
                let marker = facesFront ? tailLight : c.gold
                line(point(-bumper, side, 0.77), point(-bumper * 0.87, side, 0.77), marker, width: 0.48)
            }
        }
    }
}
