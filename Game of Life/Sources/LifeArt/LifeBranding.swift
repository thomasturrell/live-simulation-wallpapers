import AppKit
import ImageIO
import QuartzCore
import UniformTypeIdentifiers

public struct LifeBranding: Codable, Equatable {
    public var primary: LifeLogo?
    public var alternate: LifeLogo?

    public init(primary: LifeLogo? = nil, alternate: LifeLogo? = nil) {
        self.primary = primary
        self.alternate = alternate
    }

    public static let didChange = Notification.Name("io.github.thomasturrell.life.brandingChanged")
}

public struct LifeBrandingStore {
    private let file: URL

    package init(directory: URL) {
        file = directory.appendingPathComponent("Logos.plist")
    }

    public static func local() -> Self? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first.map {
            Self(directory: $0.appendingPathComponent("Game of Life/Branding", isDirectory: true))
        }
    }

    public static func shared() -> Self? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "LifeBrandingAppGroup") as? String,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            return nil
        }
        return Self(directory: container.appendingPathComponent(
            "Library/Application Support/Game of Life/Branding", isDirectory: true))
    }

    public func load() -> LifeBranding {
        guard let data = try? Data(contentsOf: file),
              data.count <= 64 * 1024 * 1024,
              let branding = try? PropertyListDecoder().decode(LifeBranding.self, from: data) else {
            return LifeBranding()
        }
        return branding
    }

    public func save(_ branding: LifeBranding) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(branding).write(to: file, options: .atomic)
    }
}

public struct LifeLogo: Codable, Equatable {
    public let name: String
    private let png: Data
    private let svg: Data?
    private let luminance: Double

    @MainActor
    public init(importing url: URL) throws {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        let format = url.pathExtension.lowercased()
        guard format == "png" || format == "svg" else { throw LogoError.unsupported }
        let limit = format == "svg" ? 2 * 1024 * 1024 : 16 * 1024 * 1024
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let data = try handle.read(upToCount: limit + 1), !data.isEmpty else { throw LogoError.invalid }
        guard data.count <= limit else { throw LogoError.tooLarge }

        let image: CGImage
        if format == "svg" {
            try StaticLogoSVG.validate(data)
            guard let vector = NSImage(data: data),
                  let bitmap = Self.rasterize(vector) else { throw LogoError.invalid }
            image = bitmap
            svg = data
        } else {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceGetType(source) == UTType.png.identifier as CFString,
                  let imageProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = imageProperties[kCGImagePropertyPixelWidth] as? Int,
                  let height = imageProperties[kCGImagePropertyPixelHeight] as? Int,
                  (1...8192).contains(width), (1...8192).contains(height),
                  let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: Self.rasterSize
                  ] as CFDictionary) else { throw LogoError.invalid }
            image = bitmap
            svg = nil
        }
        guard let luminance = Self.inkLuminance(image),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw LogoError.invalid
        }
        name = url.lastPathComponent
        png = data
        self.luminance = luminance
    }

    private static let rasterSize = 2560

    @MainActor
    private static func rasterize(_ image: NSImage) -> CGImage? {
        let size = image.size
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
        let scale = CGFloat(rasterSize) / max(size.width, size.height)
        let width = max(1, Int((size.width * scale).rounded()))
        let height = max(1, Int((size.height * scale).rounded()))
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: rect)
        return context.makeImage()
    }

    private static func inkLuminance(_ image: CGImage) -> Double? {
        // Average the visible ink in sRGB. Transparent padding has no vote.
        let width = min(image.width, 64)
        let height = min(image.height, 64)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                          CGBitmapInfo.byteOrder32Big.rawValue),
              let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var weight = 0.0
        var luminance = 0.0
        for offset in stride(from: 0, to: width * height * 4, by: 4) {
            let alpha = Double(bytes[offset + 3])
            guard alpha > 0 else { continue }
            luminance += alpha * logoLuminance(Double(bytes[offset]) / alpha,
                                               Double(bytes[offset + 1]) / alpha,
                                               Double(bytes[offset + 2]) / alpha)
            weight += alpha
        }
        return weight > 0 ? luminance / weight : nil
    }

    fileprivate var artwork: LifeBrandingArtwork.Ink? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [
                  kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return .init(image: image, luminance: luminance)
    }
}

private enum LogoError: LocalizedError {
    case unsupported, tooLarge, invalid, nonStaticSVG

    var errorDescription: String? {
        switch self {
        case .unsupported: return "Choose an SVG or PNG image."
        case .tooLarge: return "Choose an SVG under 2 MB or a PNG under 16 MB."
        case .invalid: return "This file could not be rendered as a logo."
        case .nonStaticSVG: return "Export a self-contained SVG with lettering converted to paths."
        }
    }
}

private enum StaticLogoSVG {
    private static let elements: Set<String> = [
        "svg", "g", "defs", "title", "desc", "path", "rect", "circle", "ellipse", "line",
        "polyline", "polygon", "linearGradient", "radialGradient", "stop", "clipPath",
        "mask", "pattern", "symbol", "use", "style"
    ]

    static func validate(_ data: Data) throws {
        guard let source = String(data: data, encoding: .utf8),
              !source.contains("<!DOCTYPE"), !source.contains("\0"),
              let document = try? XMLDocument(data: data, options: .nodeLoadExternalEntitiesNever),
              document.dtd == nil,
              !(document.children ?? []).contains(where: { $0.kind == .processingInstruction }),
              let root = document.rootElement(), root.localName == "svg",
              root.uri == "http://www.w3.org/2000/svg" else { throw LogoError.nonStaticSVG }
        try validate(root, depth: 0)
    }

    private static func validate(_ node: XMLElement, depth: Int) throws {
        guard depth < 64, let name = node.localName, elements.contains(name),
              node.uri == "http://www.w3.org/2000/svg" else { throw LogoError.nonStaticSVG }
        for attribute in node.attributes ?? [] {
            let key = (attribute.localName ?? "").lowercased()
            let value = attribute.stringValue ?? ""
            guard !key.hasPrefix("on"), key != "base" else { throw LogoError.nonStaticSVG }
            if key == "href" {
                guard value.range(of: #"^#[\w.:-]+$"#, options: .regularExpression) != nil else {
                    throw LogoError.nonStaticSVG
                }
            } else if key == "style" || value.localizedCaseInsensitiveContains("url(") {
                try validateCSS(value)
            }
        }
        if name == "style" { try validateCSS(node.stringValue ?? "") }
        for child in node.children ?? [] {
            if let element = child as? XMLElement {
                try validate(element, depth: depth + 1)
            } else if child.kind == .processingInstruction {
                throw LogoError.nonStaticSVG
            }
        }
    }

    private static func validateCSS(_ value: String) throws {
        let css = value.lowercased()
        guard !css.contains("@"), !css.contains("\\"), !css.contains("/*"), !css.contains("image("),
              !css.contains("image-set(") else { throw LogoError.nonStaticSVG }
        let remaining = css.replacingOccurrences(
            of: #"url\(\s*['"]?#[\w.:-]+['"]?\s*\)"#, with: "", options: .regularExpression)
        guard !remaining.contains("url(") else { throw LogoError.nonStaticSVG }
    }
}

private func logoLuminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
    func linear(_ channel: Double) -> Double {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
}

package struct LifeBrandingArtwork {
    fileprivate struct Ink {
        let image: CGImage
        let luminance: Double
    }

    private let primary: Ink?
    private let alternate: Ink?

    package init(_ branding: LifeBranding = LifeBranding()) {
        primary = branding.primary?.artwork
        alternate = primary == nil ? nil : branding.alternate?.artwork
    }

    package func placement(in viewport: CGSize, palette: LifePalette) -> (image: CGImage, frame: CGRect)? {
        guard let primary, viewport.width > 0, viewport.height > 0 else { return nil }
        var chosen = primary
        if let alternate, let background = palette.background.last?.components, background.count >= 3 {
            let base = logoLuminance(background[0], background[1], background[2])
            func contrast(_ ink: Ink) -> Double {
                (max(ink.luminance, base) + 0.05) / (min(ink.luminance, base) + 0.05)
            }
            if contrast(alternate) > contrast(primary) { chosen = alternate }
        }
        let image = chosen.image
        let scale = min(viewport.width * 0.18 / CGFloat(image.width),
                        viewport.height * 0.12 / CGFloat(image.height))
        let inset = min(viewport.width, viewport.height) * 0.025
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        return (image, CGRect(x: viewport.width - inset - size.width, y: inset,
                              width: size.width, height: size.height))
    }

    package func draw(in context: CGContext, viewport: CGSize, palette: LifePalette) {
        if let (image, frame) = placement(in: viewport, palette: palette) {
            context.draw(image, in: frame)
        }
    }
}

@MainActor
package final class LifeBrandingLayer {
    package let layer = CALayer()
    package var artwork = LifeBrandingArtwork()
    private var currentImage: CGImage?

    package init() {
        layer.isHidden = true
        layer.contentsGravity = .resize
    }

    package func update(viewport: CGSize, palette: LifePalette) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let (image, frame) = artwork.placement(in: viewport, palette: palette) else {
            layer.isHidden = true
            layer.contents = nil
            currentImage = nil
            return
        }
        if currentImage !== image {
            currentImage = image
            layer.contents = image
        }
        if layer.frame != frame { layer.frame = frame }
        layer.isHidden = false
    }
}
