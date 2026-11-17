import Foundation

final class WallpaperXPCHandler: NSObject, WallpaperExtensionXPCProtocol {
    private let connectionID = UUID()
    @MainActor private static var acquisitions: [UUID: UUID] = [:]

    func disconnect() {
        DispatchQueue.main.async {
            let released = Self.acquisitions.filter { $0.value == self.connectionID }
            for id in released.keys {
                Self.acquisitions.removeValue(forKey: id)
                WallpaperDriver.shared.invalidate(id)
            }
        }
    }

    func acquire(withId id: Any?, request: Any?, reply: @escaping @Sendable (Any?, Error?) -> Void) {
        let presentation = Presentation(request)
        let identifier = Presentation.identifier(id)
        DispatchQueue.main.async {
            guard let identifier else { return reply(nil, BridgeError.incompatible) }
            do {
                let context = try WallpaperDriver.shared.acquire(identifier, presentation)
                Self.acquisitions[identifier] = self.connectionID
                reply(context, nil)
            } catch {
                reply(nil, error)
            }
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
            if let identifier {
                Self.acquisitions.removeValue(forKey: identifier)
                WallpaperDriver.shared.invalidate(identifier)
            }
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
