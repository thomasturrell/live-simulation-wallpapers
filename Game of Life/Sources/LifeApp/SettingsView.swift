import SwiftUI
import LifeArt

@MainActor
final class SettingsModel: ObservableObject {
    @Published var settings: LifeSettings {
        didSet { if settings != oldValue { onSettingsChange?(settings) } }
    }
    @Published var desktopMotion: DesktopMotion {
        didSet { if desktopMotion != oldValue { onDesktopChange?(desktopMotion) } }
    }
    @Published private(set) var branding: LifeBranding
    private let brandingStore = LifeBrandingStore.local()

    var onSettingsChange: ((LifeSettings) -> Void)?
    var onDesktopChange: ((DesktopMotion) -> Void)?
    var onBrandingChange: ((LifeBranding) -> Void)?

    init(settings: LifeSettings, desktopMotion: DesktopMotion) {
        self.settings = settings
        self.desktopMotion = desktopMotion
        branding = brandingStore?.load() ?? LifeBranding()
    }

    func setBranding(_ branding: LifeBranding) throws {
        guard let brandingStore else { throw CocoaError(.fileNoSuchFile) }
        try brandingStore.save(branding)
        self.branding = branding
        onBrandingChange?(branding)
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    let applyStill: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Conway’s Game of Life")
                        .font(.system(size: 26, weight: .semibold))
                    Text("Animated wallpaper and screen saver")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.settings.paused.toggle()
                } label: {
                    Label(model.settings.paused ? "Resume" : "Pause",
                          systemImage: model.settings.paused ? "play.fill" : "pause.fill")
                }
                .help(model.settings.paused ? "Resume animation" : "Pause on the current generation")
            }
            Preview(settings: model.settings, branding: model.branding)
                .frame(height: 258)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
                }
                .accessibilityLabel("Game of Life preview")

            LifeSettingsControls(settings: $model.settings)
                .padding(.vertical, 1)

            Divider()
            LifeBrandingControls(branding: model.branding, onChange: model.setBranding)
            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Picker("Desktop motion", selection: $model.desktopMotion) {
                        ForEach(DesktopMotion.allCases) { motion in
                            Text(motion.title).tag(motion)
                        }
                    }
                    .fixedSize()
                    Text(model.desktopMotion.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Regenerate") { model.settings.seed = .random(in: .min ... .max) }
                    .help("Start with a new arrangement of cells")
                Button("Set Still Wallpaper", action: applyStill)
                    .help("Replace the current wallpaper on connected displays")
            }
        }
        .padding(26)
        .frame(width: 728)
        .frame(minHeight: 610)
    }
}

private struct Preview: NSViewRepresentable {
    var settings: LifeSettings
    var branding: LifeBranding

    func makeNSView(context: Context) -> LifeView {
        LifeView(frame: CGRect(x: 0, y: 0, width: 676, height: 258),
                 settings: settings, branding: branding, previewScale: 0.7)
    }

    func updateNSView(_ view: LifeView, context: Context) {
        view.settings = settings
        view.branding = branding
    }
}
