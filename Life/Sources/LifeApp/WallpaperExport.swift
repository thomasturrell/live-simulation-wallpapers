import CoreGraphics
import Foundation
import ImageIO
import LifeArt
import UniformTypeIdentifiers

enum WallpaperExport {
    private struct Frame {
        let hour: Int
        let darkness: Double
    }

    // The noon frame is the primary picture shown by ordinary image viewers.
    private static let frames = [
        Frame(hour: 12, darkness: 0.00), Frame(hour: 16, darkness: 0.12),
        Frame(hour: 18, darkness: 0.76), Frame(hour: 21, darkness: 0.90),
        Frame(hour: 0, darkness: 1.00), Frame(hour: 5, darkness: 0.83),
        Frame(hour: 7, darkness: 0.29), Frame(hour: 9, darkness: 0.08)
    ]

    static func write(to directory: URL) throws {
        let url = directory.appendingPathComponent("Cosimmetry Life.heic")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.heic.identifier as CFString, frames.count, nil
        ) else { throw WallpaperError.imageFailed }

        let metadata = try timeOfDayMetadata()
        let options = [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary
        let viewport = CGSize(width: 1600, height: 1000)
        var scene = LifeScene(viewport: viewport, settings: LifeSettings())

        for (index, frame) in frames.enumerated() {
            try autoreleasepool {
                guard let image = scene.image(scale: 3.2, darkness: frame.darkness) else {
                    throw WallpaperError.imageFailed
                }
                CGImageDestinationAddImageAndMetadata(destination, image, index == 0 ? metadata : nil, options)
                if frame.darkness == 0 || frame.darkness == 1 {
                    let name = frame.darkness == 0 ? "Light" : "Dark"
                    try writePNG(image, to: directory.appendingPathComponent("Cosimmetry Life – \(name).png"))
                }
                for _ in 0..<5 { scene.advance(by: 1) }
            }
        }

        guard CGImageDestinationFinalize(destination) else { throw WallpaperError.imageFailed }
    }

    private static func timeOfDayMetadata() throws -> CGImageMetadata {
        // Dynamic Desktop's timing convention is documented by the wallpapper project.
        // https://github.com/mczachurski/wallpapper
        let times = frames.enumerated()
            .sorted { $0.element.hour < $1.element.hour }
            .map { ["i": $0.offset, "t": Double($0.element.hour) / 24.0] as [String: Any] }
        let darkIndex = frames.firstIndex { $0.darkness == 1 }!
        let payload: [String: Any] = ["ti": times, "ap": ["l": 0, "d": darkIndex]]
        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0)
        let namespace = "http://ns.apple.com/namespace/1.0/" as CFString
        let prefix = "apple_desktop" as CFString
        let metadata = CGImageMetadataCreateMutable()

        guard CGImageMetadataRegisterNamespaceForPrefix(metadata, namespace, prefix, nil),
              let tag = CGImageMetadataTagCreate(namespace, prefix, "h24" as CFString, .string,
                                                 data.base64EncodedString() as CFString),
              CGImageMetadataSetTagWithPath(metadata, nil, "apple_desktop:h24" as CFString, tag)
        else { throw WallpaperError.imageFailed }
        return metadata
    }
}
