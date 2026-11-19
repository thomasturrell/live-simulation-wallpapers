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

    var onSettingsChange: ((LifeSettings) -> Void)?
    var onDesktopChange: ((DesktopMotion) -> Void)?

    init(settings: LifeSettings, desktopMotion: DesktopMotion) {
        self.settings = settings
        self.desktopMotion = desktopMotion
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    let applyStill: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                content(compact: geometry.size.width < 620)
            }
        }
        .frame(minWidth: 360, minHeight: 320)
    }

    private func content(compact: Bool) -> some View {
        let footer = compact ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout())
        return VStack(alignment: .leading, spacing: 17) {
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
            Preview(settings: model.settings)
                .frame(height: 258)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
                }
                .accessibilityLabel("Game of Life preview")

            LifeSettingsControls(settings: $model.settings, compact: compact)
                .padding(.vertical, 1)

            Divider()

            footer {
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
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Button("Regenerate") { model.settings.seed = .random(in: .min ... .max) }
                        .help("Start with a new arrangement of cells")
                    Button("Set Still Wallpaper", action: applyStill)
                        .help("Replace the current wallpaper on connected displays")
                }
            }
        }
        .padding(26)
    }
}

private struct Preview: NSViewRepresentable {
    var settings: LifeSettings

    func makeNSView(context: Context) -> LifeView {
        LifeView(frame: .zero, settings: settings, previewScale: 0.7)
    }

    func updateNSView(_ view: LifeView, context: Context) {
        view.settings = settings
    }
}
