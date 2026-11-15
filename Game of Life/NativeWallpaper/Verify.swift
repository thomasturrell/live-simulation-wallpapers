import AppKit
import CoreGraphics
import LifeArt
import QuartzCore

@main
@MainActor
enum VerifyWallpaper {
    static func main() async throws {
        let thumbnail = URL(fileURLWithPath: CommandLine.arguments[1])
        let state = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        guard LifeLoadWallpaperABI() else { throw BridgeError.incompatible }
        guard let settings = buildSettingsViewModelsXPC(thumbnail: thumbnail),
              String(describing: type(of: settings)).contains("WallpaperSettingsViewModelsXPC"),
              Mirror(reflecting: settings).children.count > 0 else { throw BridgeError.incompatible }
        print("WallpaperExtensionKit classes and real settings model decode passed.")

        var locked = Presentation(nil)
        locked.mode = "locked"
        locked.scale = 2
        let landscape = CGSize(width: 780, height: 440)
        let portrait = CGSize(width: 442, height: 780)
        let left = RemoteView(size: landscape, request: locked)
        let right = RemoteView(size: portrait, request: locked)

        verifyFullFrame(left, size: landscape, scale: 2)
        verifyFullFrame(right, size: portrait, scale: 1)
        verifyFullFrame(left, size: portrait, scale: 1)
        verifyFullFrame(left, size: landscape, scale: 2)
        print("All four corners covered at 1× and 2×, including after a resize.")

        guard left.makeContext(display: nil) != nil, right.makeContext(display: nil) != nil else {
            throw BridgeError.noSurface
        }

        let first = DisplayPlayback(logicalSize: landscape, checkpointKey: "landscape", storage: state)
        let second = DisplayPlayback(logicalSize: portrait, checkpointKey: "portrait", storage: state)
        first.views[UUID()] = left
        second.views[UUID()] = right
        first.refresh(hint: nil)
        second.refresh(hint: nil)
        try await Task.sleep(for: .seconds(1.3))
        precondition(first.phase > 0 && second.phase > 0)
        let before = first.phase
        first.refresh(hint: false)
        second.refresh(hint: false)
        try await Task.sleep(for: .seconds(3.8))
        let frozen = first.phase
        precondition(frozen == before + 3)
        try await Task.sleep(for: .seconds(1.2))
        precondition(first.phase == frozen && second.phase == frozen)
        precondition(left.snapshot(first.scene, phase: frozen) != nil)
        precondition(right.snapshot(second.scene, phase: frozen) != nil)
        let recreated = DisplayPlayback(logicalSize: landscape, checkpointKey: "landscape", storage: state)
        precondition(recreated.phase == frozen)
        let originalState = try PropertyListEncoder().encode(first.scene.checkpoint)
        let restoredState = try PropertyListEncoder().encode(recreated.scene.checkpoint)
        precondition(originalState == restoredState)
        recreated.views[UUID()] = left
        recreated.refresh(hint: true)
        try await Task.sleep(for: .seconds(1.3))
        precondition(recreated.phase == frozen + 1)
        recreated.views.removeAll()
        recreated.refresh(hint: false)
        print("Two remote layers, two IOSurface snapshots, slowdown, stopped timer and checkpoint resume passed.")
    }

    private static func verifyFullFrame(_ view: RemoteView, size: CGSize, scale: CGFloat) {
        var request = Presentation(nil)
        request.size = size
        request.scale = scale
        _ = view.apply(request)
        let scene = LifeScene(viewport: size, settings: LifeSettings())
        view.draw(scene, phase: 0, animate: false, duration: 0)
        let frame = CGRect(origin: .zero, size: size)
        precondition(view.root.frame == frame && view.root.contentsScale == scale)

        let parent = CALayer()
        parent.frame = frame
        parent.masksToBounds = true
        parent.addSublayer(view.root)
        defer { view.root.removeFromSuperlayer() }

        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                               bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        bitmap.scaleBy(x: scale, y: scale)
        parent.render(in: bitmap)
        let bytes = bitmap.data!.assumingMemoryBound(to: UInt8.self)
        for (x, y) in [(1, 1), (width - 2, 1), (1, height - 2), (width - 2, height - 2)] {
            precondition(bytes[y * bitmap.bytesPerRow + x * 4 + 3] == 255,
                         "Wallpaper did not cover pixel (\(x), \(y)) at \(scale)×")
        }
    }
}
