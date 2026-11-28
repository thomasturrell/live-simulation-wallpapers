import Foundation

extension Pixels {
    /// Small deterministic pixel effects at virtual-canvas resolution. Their phase
    /// is the city clock, so a still frame is stable and suspended playback is free.
    mutating func weatherEffects(tick: Int, palette c: Palette) {
        overlay = false
        depth = 0
        let weather = c.weather
        // Broad, very faint cloud shadows preserve the detail and silhouette of
        // buildings, traffic, aircraft and water beneath them.
        if weather.cloud > 0.15 {
            let drift = tick / 24
            for band in 0..<4 {
                let centre = (band * 137 + drift) % (width + 160) - 80
                let top = (band * 89 + 31) % max(1, height)
                for y in max(0, top - 20)..<min(height, top + 20) {
                    let half = 50 - abs(y - top)
                    let left = max(0, centre - half), right = min(width, centre + half)
                    guard left < right else { continue }
                    for x in left..<right {
                        shadePixel(x: x, y: y, strength: weather.cloud * 0.055)
                    }
                }
            }
        }
        let count = min(220, max(12, width * height / 1900))
        if weather.rain > 0.05 || weather.snow > 0.05 {
            for i in 0..<count {
                let phase = (i * 73 + 19) % 101
                let x = (i * 193 + tick / 3 + Int(weather.wind * Double(tick % 600) / 4)) % width
                if Double(phase) / 100 < weather.rain {
                    let y = (i * 97 + (tick % height) * 3) % height
                    let slant = 1 + Int(weather.wind * 3)
                    line(Dot(x, y), Dot(x - slant, y + 3), c.color(0x92ACB4, 0x65798F))
                    if i % 5 == 0 {
                        let splash = Dot((i * 131) % width, (i * 89 + tick / 6) % height)
                        span(splash.x - 1, splash.x + 1, splash.y, c.waterLight)
                    }
                } else if Double(phase) / 100 < weather.rain + weather.snow {
                    let y = (i * 97 + tick / 4) % height
                    let sway = Int(sin(Double(tick) / 36 + Double(i)) * 2)
                    span(x + sway, x + sway + (i % 4 == 0 ? 1 : 0), y, c.snow)
                }
            }
        }
        // A few tiny wind-blown leaves or seeds, well below precipitation density.
        if weather.wind > 0.55 {
            for i in 0..<min(14, count / 5) {
                let x = (i * 137 + tick / 2) % width
                let y = (i * 83 + tick / 18) % height
                span(x, x + 1, y, c.color(c.season.foliage < 0.7 ? 0xB39361 : 0x92A175))
            }
        }
    }

    private mutating func shadePixel(x: Int, y: Int, strength: Double) {
        for row in y * rasterScale..<(y + 1) * rasterScale {
            let start = row * rasterWidth + x * rasterScale
            for index in start..<start + rasterScale {
                let pixel = storage[index]
                var result = pixel & 0xFF00_0000
                for shift in [0, 8, 16] {
                    result |= UInt32(Double((pixel >> shift) & 255) * (1 - strength)) << shift
                }
                storage[index] = result
            }
        }
    }
}
