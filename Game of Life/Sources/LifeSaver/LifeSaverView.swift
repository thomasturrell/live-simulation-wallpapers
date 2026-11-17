import ScreenSaver
import SwiftUI
import LifeArt

@MainActor
@objc(LifeSaverView)
public final class LifeSaverView: ScreenSaverView {
    private let defaults = LifeSettings.moduleDefaults()
    private let brandingStore = LifeBrandingStore.local()
    private var art: LifeView?
    private var options: NSWindow?
    private var signalledStart = false

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        let view = LifeView(frame: bounds, settings: LifeSettings(defaults: defaults),
                            branding: brandingStore?.load() ?? LifeBranding(),
                            previewScale: isPreview ? 0.55 : 1, tracksWindowOcclusion: false)
        view.playbackEnabled = false
        view.autoresizingMask = [.width, .height]
        addSubview(view)
        art = view
        // LifeView owns the simulation timer. The host calls start and stop.
        animationTimeInterval = 2
    }

    public required init?(coder: NSCoder) { nil }

    public override func startAnimation() {
        art?.settings = LifeSettings(defaults: defaults)
        art?.branding = brandingStore?.load() ?? LifeBranding()
        super.startAnimation()
        art?.playbackEnabled = true
        if !isPreview, !signalledStart {
            signalledStart = true
            SaverPlaybackSignal.post(SaverPlaybackSignal.started)
        }
    }

    public override func stopAnimation() {
        art?.playbackEnabled = false
        super.stopAnimation()
        signalEnd()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { signalEnd() }
    }

    private func signalEnd() {
        guard signalledStart else { return }
        signalledStart = false
        SaverPlaybackSignal.post(SaverPlaybackSignal.stopped)
    }

    public override var hasConfigureSheet: Bool { true }

    public override var configureSheet: NSWindow? {
        if let options { return options }
        let startingBranding = brandingStore?.load() ?? LifeBranding()
        let model = SaverOptions(settings: LifeSettings(defaults: defaults), branding: startingBranding)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 335),
                            styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Conway’s Game of Life"
        panel.contentView = NSHostingView(rootView: SaverSettingsView(model: model) { [weak self, weak panel] save in
            guard let self, let panel else { return }
            if save {
                if model.branding != startingBranding {
                    do {
                        guard let store = self.brandingStore else { throw CocoaError(.fileNoSuchFile) }
                        try store.save(model.branding)
                    } catch {
                        let alert = NSAlert(error: error)
                        alert.beginSheetModal(for: panel)
                        return
                    }
                }
                model.settings.save(to: self.defaults)
                self.art?.settings = model.settings
                self.art?.branding = model.branding
            }
            if let parent = panel.sheetParent { parent.endSheet(panel) } else { panel.orderOut(nil) }
            panel.contentView = nil
            self.options = nil
        })
        options = panel
        return panel
    }
}

@MainActor
private final class SaverOptions: ObservableObject {
    @Published var settings: LifeSettings
    @Published var branding: LifeBranding

    init(settings: LifeSettings, branding: LifeBranding) {
        self.settings = settings
        self.branding = branding
    }
}

private struct SaverSettingsView: View {
    @ObservedObject var model: SaverOptions
    let finish: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LifeSettingsControls(settings: $model.settings)
            Divider()
            LifeBrandingControls(branding: model.branding) { model.branding = $0 }
            HStack {
                Toggle("Pause animation", isOn: $model.settings.paused)
                Spacer()
                Button("Regenerate") { model.settings.seed = .random(in: .min ... .max) }
            }
            HStack {
                Spacer()
                Button("Cancel") { finish(false) }.keyboardShortcut(.cancelAction)
                Button("Done") { finish(true) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 540)
    }
}
