import AppKit
import CityArt
import CityEngine
import ImageIO
import UniformTypeIdentifiers
import SwiftUI

@MainActor
final class PreviewModel: ObservableObject {
    @Published var skin: CitySkin = .original
    @Published var mode: EnvironmentMode = .simulationWorld
    @Published var inspectCalendar = false
    @Published var month = 1.0
    @Published var light = "live"
    @Published var weather = "live"
    @Published var inspectWind = false
    @Published var wind = 0.5
    @Published var trafficConvention: TrafficConvention = .default
    @Published var paused = false
    @Published var status = ""
    var preview: EnvironmentPreview {
        var value = EnvironmentPreview()
        value.month = inspectCalendar ? month : nil
        value.darkness = light == "day" ? 0 : light == "night" ? 1 : nil
        value.weather = WeatherKind(rawValue: weather)
        value.wind = inspectWind ? wind : nil
        return value
    }
}

@MainActor
struct PreviewControls: View {
    @ObservedObject var model: PreviewModel
    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 760
            let layout = compact ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
            layout {
                controls
                    .frame(width: compact ? nil : 300, height: compact ? min(280, geometry.size.height * 0.4) : nil)
                Divider()
                PreviewCanvas(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 360, minHeight: 320)
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("City preview").font(.title2.bold())
                Picker("Skin", selection: $model.skin) {
                    ForEach(CitySkin.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Environment", selection: $model.mode) {
                    ForEach(EnvironmentMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }.onChange(of: model.mode) { previous, current in
                    if previous.isSimulation != current.isSimulation { model.month = 1 }
                }
                Divider()
                Toggle("Inspect calendar", isOn: $model.inspectCalendar)
                if model.inspectCalendar {
                    Slider(value: $model.month, in: 1...(model.mode.isSimulation ? 5 : 13), step: 0.01)
                    Text(calendarDescription).font(.caption.monospacedDigit())
                    HStack {
                        Button("Previous") { model.month = max(1, ceil(model.month) - 1) }
                        Button("Next") { model.month = min(model.mode.isSimulation ? 5 : 13, floor(model.month) + 1) }
                    }
                }
                Picker("Lighting", selection: $model.light) {
                    Text("Live").tag("live"); Text("Day").tag("day"); Text("Night").tag("night")
                }
                Picker("Weather preview", selection: $model.weather) {
                    Text("Live").tag("live")
                    ForEach(WeatherKind.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                Toggle("Inspect wind", isOn: $model.inspectWind)
                if model.inspectWind {
                    Slider(value: $model.wind, in: 0...1)
                    Text("Wind · \(Int(model.wind * 100))%").font(.caption.monospacedDigit())
                }
                Picker("Traffic", selection: $model.trafficConvention) {
                    Text("Keep left").tag(TrafficConvention.uk)
                    Text("Keep Right").tag(TrafficConvention.rightHand)
                }
                Text("Changing traffic restarts the preview city.").font(.caption).foregroundStyle(.secondary)
                Toggle("Pause city", isOn: $model.paused)
                Text(model.status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text("Previews leave saved wallpaper cities untouched. Wallpaper settings are in System Settings → Wallpaper.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }
    }

    private var calendarDescription: String {
        let count = model.mode.isSimulation ? 4 : 12
        let index = (Int(model.month) - 1) % count
        let title = model.mode.isSimulation ? Season.allCases[index].title : DateFormatter().monthSymbols[index]
        return "\(title) · Month \(String(format: "%.2f", model.month))\(model.mode == .realWorldSouthern ? " · southern seasons reversed" : "")"
    }
}

@MainActor
struct PreviewCanvas: NSViewRepresentable {
    @ObservedObject var model: PreviewModel
    func makeNSView(context: Context) -> PreviewView { PreviewView(model: model) }
    func updateNSView(_ view: PreviewView, context: Context) { view.configure() }
}

@MainActor
final class PreviewView: NSView {
    private let model: PreviewModel
    private var playback: Playback
    private let renderer = CityRenderer()
    private var timer: Timer?
    private var timestamp = ProcessInfo.processInfo.systemUptime
    init(model: PreviewModel) {
        self.model = model
        playback = Playback(city: City(trafficConvention: model.trafficConvention))
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configure()
    }
    func configure() {
        if playback.city.trafficConvention != model.trafficConvention {
            playback = Playback(city: City(trafficConvention: model.trafficConvention))
            timestamp = ProcessInfo.processInfo.systemUptime
        }
        let active = window != nil && !model.paused
        playback.present(visible: active, animated: active)
        if active && timer == nil {
            timestamp = ProcessInfo.processInfo.systemUptime
            let timer = Timer(timeInterval: 1 / 20, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else if !active { timer?.invalidate(); timer = nil }
        needsDisplay = true
    }
    private func update() {
        let now = ProcessInfo.processInfo.systemUptime
        playback.advance(elapsed: now - timestamp)
        timestamp = now
        needsDisplay = true
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, let window else { return }
        let environment = Environment.frame(city: playback.city, mode: model.mode,
                                            systemDark: effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua,
                                            preview: model.preview)
        let calendar = model.mode.isSimulation ? Environment.calendarLabel(tick: playback.city.tick) : Date().formatted(date: .abbreviated, time: .omitted)
        let weather = model.preview.weather.map { "Preview · \($0.title)" } ??
            (model.mode.isSimulation ? "Simulated weather · \(environment.weather.kind.title)" : "Neutral, dry conditions")
        let status = "\(calendar)\n\(weather)"
        if model.status != status { DispatchQueue.main.async { [weak model] in model?.status = status } }
        let scale = window.backingScaleFactor
        let viewport = CityViewport(pixelWidth: Int((bounds.width * scale).rounded()),
                                    pixelHeight: Int((bounds.height * scale).rounded()))
        context.saveGState()
        context.scaleBy(x: 1 / scale, y: 1 / scale)
        viewport.draw(renderer.image(for: playback.city, viewport: viewport, environment: environment, skin: model.skin), in: context)
        context.restoreGState()
    }
}

enum PreviewError: Error { case usage, write }

@MainActor
func run() throws {
    var args = Array(CommandLine.arguments.dropFirst())
    var mode = EnvironmentMode.simulationWorld
    var preview = EnvironmentPreview()
    var skin = CitySkin.original
    var convention = TrafficConvention.default
    func option(_ name: String) throws -> String? {
        guard let index = args.firstIndex(of: name) else { return nil }
        guard index + 1 < args.count else { throw PreviewError.usage }
        let value = args[index + 1]
        args.removeSubrange(index...index + 1)
        return value
    }
    if let value = try option("--environment") {
        guard let value = ["simulation": EnvironmentMode.simulationWorld, "northern": .realWorldNorthern, "southern": .realWorldSouthern][value] else { throw PreviewError.usage }
        mode = value
    }
    if let value = try option("--month") {
        guard let month = Double(value), month.isFinite, (1...(mode.isSimulation ? 5.0 : 13.0)).contains(month) else { throw PreviewError.usage }
        preview.month = month
    }
    if let value = try option("--light") {
        guard ["day", "night"].contains(value) else { throw PreviewError.usage }
        preview.darkness = value == "night" ? 1 : 0
    }
    if let value = try option("--weather") {
        guard let kind = WeatherKind(rawValue: value) else { throw PreviewError.usage }
        preview.weather = kind
    }
    if let value = try option("--wind") {
        guard let wind = Double(value), wind.isFinite, (0...1).contains(wind) else { throw PreviewError.usage }
        preview.wind = wind
    }
    if let value = try option("--skin") {
        guard let selected = CitySkin(rawValue: value) else { throw PreviewError.usage }
        skin = selected
    }
    if let value = try option("--traffic") {
        guard let selected = TrafficConvention(rawValue: value) else { throw PreviewError.usage }
        convention = selected
    }
    if args.first == "--gallery", args.count == 2 {
        try writeGallery(to: URL(fileURLWithPath: args[1], isDirectory: true), convention: convention, skin: skin)
        return
    }
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
        var city = City(trafficConvention: convention)
        for _ in 0..<seconds * City.ticksPerSecond { city.step() }
        let viewport = CityViewport(pixelWidth: width, pixelHeight: height)
        let environment = Environment.frame(city: city, mode: mode,
                                            systemDark: UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark", preview: preview)
        let image = CityRenderer().image(for: city, viewport: viewport, environment: environment, skin: skin)
        let output = URL(fileURLWithPath: args[1])
        try writePNG(image, viewport: viewport, to: output)
        print("\(output.path) · \(mode.title) · \(environment.weather.kind.title)")
        return
    }

    guard args.isEmpty else { throw PreviewError.usage }
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let mainMenu = NSMenu()
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "Quit City Simulation", action: #selector(NSApplication.terminate(_:)),
                    keyEquivalent: "q").target = app
    mainMenu.addItem(withTitle: "City Simulation", action: nil, keyEquivalent: "").submenu = appMenu
    app.mainMenu = mainMenu
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1320, height: 780),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
    window.title = "City Simulation"
    window.collectionBehavior = [.fullScreenPrimary, .fullScreenAllowsTiling]
    let model = PreviewModel()
    model.skin = skin
    model.mode = mode
    model.trafficConvention = convention
    model.inspectWind = preview.wind != nil; model.wind = preview.wind ?? 0.5
    model.inspectCalendar = preview.month != nil; model.month = preview.month ?? 1
    model.light = preview.darkness.map { $0 > 0.5 ? "night" : "day" } ?? "live"
    model.weather = preview.weather?.rawValue ?? "live"
    window.contentView = NSHostingView(rootView: PreviewControls(model: model))
    window.center()
    window.makeKeyAndOrderFront(nil)
    let delegate = PreviewDelegate()
    app.delegate = delegate
    app.activate(ignoringOtherApps: true)
    withExtendedLifetime((window, delegate)) { app.run() }
}

private func writePNG(_ image: CGImage, viewport: CityViewport, to output: URL) throws {
    guard let context = CGContext(data: nil, width: viewport.pixelWidth, height: viewport.pixelHeight, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw PreviewError.write }
    viewport.draw(image, in: context)
    guard let image = context.makeImage() else { throw PreviewError.write }
    try savePNG(image, to: output)
}

private func savePNG(_ image: CGImage, to output: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw PreviewError.write }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw PreviewError.write }
}

/// Reproducible contact sheets use the production renderer without advancing a
/// city or touching wallpaper checkpoints, weather caches or network services.
@MainActor
private func writeGallery(to directory: URL, convention: TrafficConvention, skin: CitySkin) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let city = City(trafficConvention: convention)
    let viewport = CityViewport(pixelWidth: 640, pixelHeight: 360)
    func sheet(_ filename: String, columns: Int, examples: [(String, EnvironmentMode, EnvironmentPreview)]) throws {
        let w = columns * 320, h = ((examples.count + columns - 1) / columns) * 202
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw PreviewError.write }
        context.setFillColor(NSColor(calibratedWhite: 0.12, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        context.interpolationQuality = skin == .contemporary ? .high : .none
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for (index, example) in examples.enumerated() {
            let x = index % columns * 320, y = h - (index / columns + 1) * 202
            let frame = Environment.frame(city: city, mode: example.1, preview: example.2)
            let image = CityRenderer().image(for: city, viewport: viewport, environment: frame, skin: skin)
            context.draw(image, in: CGRect(x: x, y: y + 22, width: 320, height: 180))
            (example.0 as NSString).draw(at: NSPoint(x: x + 8, y: y + 5), withAttributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.white
            ])
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else { throw PreviewError.write }
        try savePNG(image, to: directory.appendingPathComponent(filename))
    }
    var mode = EnvironmentMode.realWorldNorthern
    try sheet("real-world-months.png", columns: 4, examples: (1...12).map { month in
        var preview = EnvironmentPreview(); preview.month = Double(month); preview.darkness = 0; preview.weather = .clear
        return ("\(DateFormatter().monthSymbols[month - 1]) 1 · Northern · Day", mode, preview)
    })
    mode = .simulationWorld
    try sheet("simulation-year.png", columns: 4, examples: (0..<8).map { stage in
        var preview = EnvironmentPreview(); preview.month = 1 + Double(stage) / 2; preview.darkness = stage < 4 ? 0 : 1; preview.weather = .clear
        return ("Month \(String(format: "%.1f", preview.month!)) · \(Season.allCases[stage / 2].title) · \(stage < 4 ? "Day" : "Night")", mode, preview)
    })
    let hemispheres: [(String, EnvironmentMode, EnvironmentPreview)] = [EnvironmentMode.realWorldNorthern, .realWorldSouthern].flatMap { mode in
        [1.0, 4, 7, 10].map { month in
            var preview = EnvironmentPreview(); preview.month = month; preview.darkness = 0
            return ("\(mode == .realWorldNorthern ? "Northern" : "Southern") · \(DateFormatter().monthSymbols[Int(month) - 1])", mode, preview)
        }
    }
    try sheet("hemispheres.png", columns: 4, examples: hemispheres)
    var examples: [(String, EnvironmentMode, EnvironmentPreview)] = []
    for wind in [0.1, 0.5, 0.9] {
        for kind in WeatherKind.allCases {
            var preview = EnvironmentPreview(); preview.month = 4; preview.weather = kind; preview.darkness = 0; preview.wind = wind
            examples.append(("\(kind.title) · Wind \(Int(wind * 100))% · Winter", .simulationWorld, preview))
        }
    }
    try sheet("weather-variations.png", columns: 4, examples: examples)
    try savePNG(CityRenderer.vegetationPreview(), to: directory.appendingPathComponent("seasonal-vegetation.png"))
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
    fputs("Usage: CityPreview [--png FILE [WIDTH HEIGHT [SIMULATED-SECONDS]]] [--skin original|contemporary] [--traffic uk|right] [--environment simulation|northern|southern] [--month NUMBER] [--light day|night] [--weather clear|cloudy|rain|snow] [--wind 0...1] | --gallery DIRECTORY\n\(error)\n", stderr)
    exit(1)
}
