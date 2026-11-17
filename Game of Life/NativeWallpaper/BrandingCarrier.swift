import AppKit
import LifeArt
import SwiftUI

@main
@MainActor
enum GameOfLifeWallpaperCarrier {
    static func main() {
        runWallpaperInstaller {
            guard let store = LifeBrandingStore.shared() else { return nil }
            let model = WallpaperBrandingModel(store: store)
            let view = NSHostingView(rootView: WallpaperBrandingSettings(model: model))
            view.frame = NSRect(x: 0, y: 0, width: 400, height: 104)
            return view
        }
    }
}

@MainActor
private final class WallpaperBrandingModel: ObservableObject {
    private let store: LifeBrandingStore
    @Published private(set) var branding: LifeBranding

    init(store: LifeBrandingStore) {
        self.store = store
        branding = store.load()
    }

    func update(_ updated: LifeBranding) throws {
        try store.save(updated)
        branding = updated
        DistributedNotificationCenter.default().postNotificationName(
            LifeBranding.didChange, object: nil, userInfo: nil, deliverImmediately: true
        )
    }
}

@MainActor
private struct WallpaperBrandingSettings: View {
    @ObservedObject var model: WallpaperBrandingModel

    var body: some View {
        LifeBrandingControls(branding: model.branding, onChange: model.update)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
