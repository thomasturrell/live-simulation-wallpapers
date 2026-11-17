import AppKit
import CityArt
import CityEngine
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class PreviewView: NSView {
    private var playback = Playback(city: City())
    private let renderer = CityRenderer()
    private var timer: Timer?
    private var timestamp = ProcessInfo.processInfo.systemUptime

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        timer?.invalidate()
        timer = nil
        guard window != nil else { return }
        playback.present(visible: true, animated: true)
        timestamp = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1 / 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func update() {
        let now = ProcessInfo.processInfo.systemUptime
        playback.advance(elapsed: now - timestamp)
        timestamp = now
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, let window else { return }
        let scale = window.backingScaleFactor
        let viewport = CityViewport(pixelWidth: Int((bounds.width * scale).rounded()),
                                    pixelHeight: Int((bounds.height * scale).rounded()))
        context.saveGState()
        context.scaleBy(x: 1 / scale, y: 1 / scale)
        viewport.draw(renderer.image(for: playback.city, viewport: viewport), in: context)
        context.restoreGState()
    }
}

enum PreviewError: Error { case usage, write }

@MainActor
func run() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    if args.first == "--icns", args.count == 2 {
        try writeIcon(to: URL(fileURLWithPath: args[1]))
        return
    }
    if args.first == "--png" {
        guard (2...5).contains(args.count) else { throw PreviewError.usage }
        let width = args.count > 2 ? Int(args[2]) : 1280
        let height = args.count > 3 ? Int(args[3]) : 720
        let seconds = args.count > 4 ? Int(args[4]) : 0
        guard let width, let height, let seconds, (1...5120).contains(width), (1...5120).contains(height),
              (0...900).contains(seconds) else { throw PreviewError.usage }
        var city = City()
        for _ in 0..<seconds * City.ticksPerSecond { city.step() }
        let viewport = CityViewport(pixelWidth: width, pixelHeight: height)
        let image = CityRenderer().image(for: city, viewport: viewport)
        let output = URL(fileURLWithPath: args[1])
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw PreviewError.write
        }
        viewport.draw(image, in: context)
        guard let scaledImage = context.makeImage() else { throw PreviewError.write }
        CGImageDestinationAddImage(destination, scaledImage, nil)
        guard CGImageDestinationFinalize(destination) else { throw PreviewError.write }
        return
    }

    guard args.isEmpty else { throw PreviewError.usage }
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 630),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
    window.title = "City Simulation"
    window.contentView = PreviewView()
    window.center()
    window.makeKeyAndOrderFront(nil)
    let delegate = PreviewDelegate()
    app.delegate = delegate
    app.activate(ignoringOtherApps: true)
    withExtendedLifetime((window, delegate)) { app.run() }
}

private func writeIcon(to output: URL) throws {
    let city = City()
    let viewport = CityViewport(pixelWidth: 128, pixelHeight: 128)
    let art = CityRenderer().image(for: city, viewport: viewport)
    var chunks = Data()
    func appendLength(_ length: Int, to bytes: inout Data) {
        var length = UInt32(length).bigEndian
        withUnsafeBytes(of: &length) { bytes.append(contentsOf: $0) }
    }
    for (size, type) in [(128, "ic07"), (256, "ic08"), (512, "ic09"), (1024, "ic10")] {
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw PreviewError.write
        }
        let frame = CGRect(x: size / 16, y: size / 16, width: size * 7 / 8, height: size * 7 / 8)
        context.addPath(CGPath(roundedRect: frame, cornerWidth: CGFloat(size) * 0.19,
                               cornerHeight: CGFloat(size) * 0.19, transform: nil))
        context.clip()
        context.interpolationQuality = .none
        context.draw(art, in: CGRect(x: 0, y: 0, width: size, height: size))
        let png = NSMutableData()
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else {
            throw PreviewError.write
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw PreviewError.write }
        chunks.append(contentsOf: type.utf8)
        appendLength(png.length + 8, to: &chunks)
        chunks.append(png as Data)
    }
    var icon = Data("icns".utf8)
    appendLength(chunks.count + 8, to: &icon)
    icon.append(chunks)
    try icon.write(to: output)
}

final class PreviewDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

do {
    try MainActor.assumeIsolated { try run() }
} catch {
    fputs("Usage: CityPreview [--png FILE [WIDTH HEIGHT [SIMULATED-SECONDS]]]\n\(error)\n", stderr)
    exit(1)
}
