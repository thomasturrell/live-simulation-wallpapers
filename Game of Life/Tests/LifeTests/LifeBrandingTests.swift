import AppKit
import Testing
@testable import LifeArt

@Test @MainActor func importedLogosSurviveSourceRemovalAndRenderWithContrast() throws {
    let directory = try brandingTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("source.svg")
    let store = LifeBrandingStore(directory: directory.appendingPathComponent("Branding"))
    #expect(store.load() == LifeBranding())

    try writeLogo(to: source, ink: "#000")
    let black = try LifeLogo(importing: source)
    try writeLogo(to: source, ink: "#fff")
    let white = try LifeLogo(importing: source)
    let branding = LifeBranding(primary: black, alternate: white)
    try store.save(branding)
    try FileManager.default.removeItem(at: source)
    #expect(store.load() == branding)

    let artwork = LifeBrandingArtwork(store.load())
    let viewport = CGSize(width: 640, height: 400)
    let scene = LifeScene(viewport: viewport, settings: LifeSettings())
    for dark in [false, true] {
        let darkness: Double = dark ? 1 : 0
        let palette = scene.palette(darkness: darkness)
        let placement = try #require(artwork.placement(in: viewport, palette: palette))
        #expect(placement.frame.midX > viewport.width * 0.8)
        #expect(placement.frame.midY < viewport.height * 0.2)
        #expect(abs(placement.frame.width / placement.frame.height - 2) < 0.01)

        let unbranded = try #require(scene.image(scale: 2, dark: dark))
        let branded = try #require(scene.image(scale: 2, darkness: darkness, branding: artwork))
        let center = CGPoint(x: placement.frame.midX * 2, y: placement.frame.midY * 2)
        let expected: UInt8 = dark ? 255 : 0
        #expect(try pixel(branded, at: center) == [expected, expected, expected, 255])
        #expect(try pixel(unbranded, at: center) != pixel(branded, at: center))
        let transparentPadding = CGPoint(x: placement.frame.minX * 2 + 2, y: center.y)
        #expect(try pixel(unbranded, at: transparentPadding) == pixel(branded, at: transparentPadding))
    }
    let dynamicPalette = scene.palette(darkness: 1, colour: .yellow)
    let yellow = try #require(artwork.placement(in: viewport, palette: dynamicPalette))
    #expect(try pixel(yellow.image, at: CGPoint(x: 1280, y: 640)) == [0, 0, 0, 255])

    try store.save(LifeBranding())
    #expect(LifeBrandingArtwork(store.load()).placement(in: viewport, palette: scene.palette(darkness: 0)) == nil)
}

@Test @MainActor func logoImportAcceptsTransparentPNGAndRejectsNonStaticSVG() throws {
    let directory = try brandingTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let svg = directory.appendingPathComponent("wordmark.svg")
    let png = directory.appendingPathComponent("wordmark.png")
    try writeLogo(to: svg, ink: "#fff")
    let original = try LifeLogo(importing: svg)
    let palette = LifePalette(darkness: 0, colour: .original, generation: 0, seed: 0)
    let viewport = CGSize(width: 640, height: 400)
    let placement = try #require(LifeBrandingArtwork(LifeBranding(primary: original))
        .placement(in: viewport, palette: palette))
    let bytes = try #require(NSBitmapImageRep(cgImage: placement.image).representation(using: .png, properties: [:]))
    try bytes.write(to: png)
    let bitmap = try LifeLogo(importing: png)
    let reimported = try #require(LifeBrandingArtwork(LifeBranding(primary: bitmap))
        .placement(in: viewport, palette: palette))
    #expect(try pixel(reimported.image, at: .zero)[3] == 0)
    #expect(try pixel(reimported.image, at: CGPoint(x: 1280, y: 640)) == [255, 255, 255, 255])

    for content in [
        #"<script>alert(1)</script>"#,
        #"<use href="https://example.com/art.svg#wordmark"/>"#,
        #"<style>@import url(https://example.com/branding.css);</style>"#
    ] {
        try Data((#"<svg xmlns="http://www.w3.org/2000/svg" width="100" height="50">"# + content + "</svg>").utf8)
            .write(to: svg)
        #expect(throws: (any Error).self) { try LifeLogo(importing: svg) }
    }
}

private func brandingTestDirectory() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

private func writeLogo(to url: URL, ink: String) throws {
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="100" height="50">
      <rect x="15" y="10" width="70" height="30" fill="\(ink)"/>
    </svg>
    """
    try Data(svg.utf8).write(to: url)
}

private func pixel(_ image: CGImage, at point: CGPoint) throws -> [UInt8] {
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                                         bytesPerRow: 4, space: space,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                             CGBitmapInfo.byteOrder32Big.rawValue))
    context.translateBy(x: -point.x.rounded(.down), y: -point.y.rounded(.down))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let bytes = try #require(context.data?.assumingMemoryBound(to: UInt8.self))
    return (0..<4).map { bytes[$0] }
}
