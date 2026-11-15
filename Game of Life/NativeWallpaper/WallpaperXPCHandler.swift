import Foundation

final class WallpaperXPCHandler: NSObject, WallpaperExtensionXPCProtocol {
    func acquire(withId id: Any?, request: Any?, reply: @escaping @Sendable (Any?, Error?) -> Void) {
        let presentation = Presentation(request)
        let identifier = Presentation.identifier(id)
        DispatchQueue.main.async {
            guard let identifier else { return reply(nil, BridgeError.incompatible) }
            do { reply(try WallpaperDriver.shared.acquire(identifier, presentation), nil) }
            catch { reply(nil, error) }
        }
    }

    func update(withId id: Any?, request: Any?, reply: @escaping @Sendable (Error?) -> Void) {
        let presentation = Presentation(request)
        let identifier = Presentation.identifier(id)
        DispatchQueue.main.async {
            guard let identifier else { return reply(BridgeError.incompatible) }
            WallpaperDriver.shared.update(identifier, presentation)
            reply(nil)
        }
    }

    func invalidate(withId id: Any?, reply: @escaping @Sendable (Error?) -> Void) {
        let identifier = Presentation.identifier(id)
        DispatchQueue.main.async {
            if let identifier { WallpaperDriver.shared.invalidate(identifier) }
            reply(nil)
        }
    }

    func snapshot(withId id: Any?, reply: @escaping @Sendable (Any?, Error?) -> Void) {
        let identifier = Presentation.identifier(id)
        DispatchQueue.main.async {
            guard let identifier else { return reply(nil, BridgeError.noSurface) }
            do { reply(try WallpaperDriver.shared.snapshot(identifier), nil) }
            catch { reply(nil, error) }
        }
    }

    func handleDebugRequest(for request: Any?, reply: @escaping @Sendable (Any?, Error?) -> Void) {
        reply(nil, nil)
    }

    func handleNotification(withNamed name: Any?, reply: @escaping @Sendable (Error?) -> Void) {
        debugLog("WallpaperAgent event: \(String(describing: name))")
        reply(nil)
    }
}
