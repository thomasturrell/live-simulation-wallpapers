import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
public struct LifeBrandingControls: View {
    private enum Slot {
        case primary, alternate
    }

    private let branding: LifeBranding
    private let onChange: (LifeBranding) throws -> Void

    public init(branding: LifeBranding, onChange: @escaping (LifeBranding) throws -> Void) {
        self.branding = branding
        self.onChange = onChange
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Logo", slot: .primary, file: branding.primary)
            if branding.primary != nil {
                row("Alternate logo", slot: .alternate, file: branding.alternate)
                Text("The wallpaper picks the version with better contrast.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Add a transparent SVG or PNG to the bottom right.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ title: String, slot: Slot, file: LifeLogo?) -> some View {
        HStack(spacing: 8) {
            Text(title)
            if let file {
                Text(file.name)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(file.name)
            }
            Spacer(minLength: 8)
            Button(file == nil ? "Add \(title)…" : "Replace…") { chooseLogo(slot) }
                .accessibilityLabel(file == nil ? "Add \(title)" : "Replace \(title)")
            if file != nil {
                Button("Remove", role: .destructive) { removeLogo(slot) }
                    .accessibilityLabel("Remove \(title)")
            }
        }
    }

    private func chooseLogo(_ slot: Slot) {
        let panel = NSOpenPanel()
        panel.message = "Choose a transparent SVG or PNG logo."
        panel.allowedContentTypes = [.svg, .png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let logo = try LifeLogo(importing: url)
            var updated = branding
            switch slot {
            case .primary: updated.primary = logo
            case .alternate: updated.alternate = logo
            }
            try onChange(updated)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func removeLogo(_ slot: Slot) {
        do {
            var updated = branding
            switch slot {
            case .primary: updated = LifeBranding()
            case .alternate: updated.alternate = nil
            }
            try onChange(updated)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
