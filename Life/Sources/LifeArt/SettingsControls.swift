import SwiftUI

@MainActor
public struct LifeSettingsControls: View {
    @Binding private var settings: LifeSettings

    public init(settings: Binding<LifeSettings>) {
        _settings = settings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 26) {
                VStack(spacing: 12) {
                    slider("Generation speed", value: $settings.speed, range: LifeSettings.speedRange,
                           step: 0.25, readout: "\(settings.speed.formatted()) gen/s")
                    slider("Cell size", value: $settings.size, range: LifeSettings.sizeRange,
                           step: 0.5, readout: "\(settings.size.formatted()) pt")
                }
                VStack(spacing: 12) {
                    slider("Grid rotation", value: $settings.angle, range: LifeSettings.angleRange,
                           step: 1, readout: "\(settings.angle.formatted())°")
                    slider("Cell spacing", value: $settings.spacing, range: LifeSettings.spacingRange,
                           step: 0.5, readout: "\(settings.spacing.formatted()) pt")
                }
            }
            HStack(spacing: 26) {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(LifeAppearance.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Picker("New patterns", selection: $settings.injection) {
                    ForEach(LifeSettings.injectionOptions, id: \.self) { seconds in
                        Text(seconds > 0 ? "Every \(Int(seconds)) s" : "Off").tag(seconds)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .controlSize(.regular)
        }
    }

    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>,
                        step: Double, readout: String) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(label)
                Spacer()
                Text(readout).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step) { Text(label) }
                .labelsHidden()
                .accessibilityValue(readout)
        }
    }
}
