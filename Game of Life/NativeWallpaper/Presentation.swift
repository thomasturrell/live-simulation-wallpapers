import AppKit
import CoreGraphics
import LifeArt

struct Presentation {
    var size: CGSize?
    var scale: CGFloat?
    var displayID: UInt32?
    var mode: String?
    var activity: String?
    var dark: Bool?
    var colour: LifeColour?
    var preview = false
    var hasPlacement = false

    init(_ request: Any?) {
        guard let request, let value = Mirror(reflecting: request).children.first?.value else { return }
        let data = Mirror(reflecting: value)
        // WallpaperAgent supplies option values in the creation descriptor.
        if let options = data.descendant("descriptor", "optionValues", "some", "values") as? [String: Any],
           let option = options[lifeColourOptionID],
           let id = Mirror(reflecting: option).descendant("picker", "id") as? String {
            colour = LifeColour(rawValue: id)
        }
        let description = String(describing: value)
        func enumCase(_ label: String) -> String? {
            guard let range = description.range(of: "\(label): ") else { return nil }
            return description[range.upperBound...].prefix { $0.isLetter }.lowercased()
        }
        mode = enumCase("presentationMode")
        activity = enumCase("activityState")
        if let appearance = enumCase("systemAppearance") {
            if appearance.contains("dark") { dark = true }
            if appearance.contains("light") { dark = false }
        }
        hasPlacement = description.contains("\"placement\":")
        preview = data.children.first { $0.label == "isPreview" }?.value as? Bool ?? false
        if let destination = data.children.first(where: { $0.label == "destination" })?.value {
            for (label, value) in Mirror(reflecting: destination).children {
                switch label {
                case "size":
                    if let geometry = value as? CGSize,
                       (1...8192).contains(geometry.width), (1...8192).contains(geometry.height) {
                        size = geometry
                    }
                case "scaleFactor":
                    if let factor = value as? CGFloat, (0.5...4).contains(factor) { scale = factor }
                case "directDisplayID":
                    displayID = value as? UInt32
                default: break
                }
            }
        }
    }

    var displayKey: String? {
        guard let id = displayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    static func identifier(_ object: Any?) -> UUID? {
        guard let object else { return nil }
        let value = Mirror(reflecting: object).children.first?.value
        if let uuid = value as? UUID { return uuid }
        let description = String(describing: value ?? object)
        guard let match = description.range(of: "[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}",
                                            options: [.regularExpression, .caseInsensitive]) else { return nil }
        return UUID(uuidString: String(description[match]))
    }
}
