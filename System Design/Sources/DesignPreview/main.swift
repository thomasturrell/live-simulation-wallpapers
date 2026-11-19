import AppKit
import DesignArt
import DesignEngine

private enum PreviewError: Error { case usage, render }

@MainActor
private func run() throws {
    var args = Array(CommandLine.arguments.dropFirst())
    if args.isEmpty {
        LivePreview.run()
        return
    }
    if args.count == 2, args[0] == "--icon-png" {
        guard let data = iconPNG() else { throw PreviewError.render }
        try data.write(to: URL(fileURLWithPath: args[1]), options: .atomic)
        return
    }
    var style = DesignStyle()
    if args.last == "--show-system-label" {
        args.removeLast()
        style.systemLabel = true
    }
    guard (4...8).contains(args.count), args[0] == "--png", let width = Int(args[2]), let height = Int(args[3]),
          (64...8192).contains(width), (64...8192).contains(height) else { throw PreviewError.usage }
    let selection = args.count > 4 ? args[4] : "domestic-solar-power"
    guard selection == "all" || Catalogue.bundled[selection] != nil || Subject(rawValue: selection) != nil else { throw PreviewError.usage }
    let seconds = args.count > 5 ? Double(args[5]) : 12
    guard let seconds, seconds.isFinite, (0...3600).contains(seconds) else { throw PreviewError.usage }
    if args.count > 6 {
        guard let colour = Colour(rawValue: args[6]) else { throw PreviewError.usage }
        style.colour = colour
    }
    if args.count > 7 {
        guard let appearance = Appearance(rawValue: args[7]) else { throw PreviewError.usage }
        style.appearance = appearance
    }
    var playback = Playback(Exploration(seed: 42, scope: selection))
    playback.present(visible: true, animated: true)
    for _ in 0..<Int(seconds * 16) { playback.advance(elapsed: 1.0 / 16) }
    let renderer = DesignRenderer()
    let size = CGSize(width: width, height: height)
    renderer.draw(playback.exploration, size: size, scale: 1, style: style, systemDark: false)
    guard let image = renderer.image(size: size),
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw PreviewError.render }
    try png.write(to: URL(fileURLWithPath: args[1]), options: .atomic)
}

do { try MainActor.assumeIsolated { try run() } } catch {
    fputs("Usage: DesignPreview\n       DesignPreview --png FILE WIDTH HEIGHT [SYSTEM-OR-CATEGORY [SECONDS [COLOUR [System|Light|Dark]]]] [--show-system-label]\n\(error)\n", stderr)
    exit(1)
}
