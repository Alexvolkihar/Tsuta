import SwiftUI

/// Design tokens. Colours adapt to light/dark through the system semantic colours; the only
/// custom hues are the accent and the deterministic palettes used by the graph and avatars.
enum Theme {
    static let accent = Color(red: 0.13, green: 0.56, blue: 0.53)

    static let graphPalette: [Color] = [
        Color(red: 0.20, green: 0.55, blue: 0.95), Color(red: 0.93, green: 0.36, blue: 0.55),
        Color(red: 0.96, green: 0.62, blue: 0.20), Color(red: 0.30, green: 0.72, blue: 0.45),
        Color(red: 0.62, green: 0.45, blue: 0.92), Color(red: 0.16, green: 0.72, blue: 0.75),
        Color(red: 0.88, green: 0.33, blue: 0.30), Color(red: 0.80, green: 0.70, blue: 0.20),
    ]

    static func lane(_ index: Int) -> Color { graphPalette[index % graphPalette.count] }

    /// Stable colour for a person, derived from their email (or name).
    static func avatarColor(for key: String) -> Color {
        var hash: UInt64 = 1469598103934665603
        for byte in key.lowercased().utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        let hue = Double(hash % 360) / 360
        return Color(hue: hue, saturation: 0.55, brightness: 0.78)
    }

    static let radius: CGFloat = 8
}

// MARK: Zoom

private struct ZoomKey: EnvironmentKey { static let defaultValue: CGFloat = 1 }

extension EnvironmentValues {
    var uiZoom: CGFloat {
        get { self[ZoomKey.self] }
        set { self[ZoomKey.self] = newValue }
    }
}

private struct UIFontModifier: ViewModifier {
    @Environment(\.uiZoom) private var zoom
    let size: CGFloat
    let weight: Font.Weight
    let mono: Bool

    func body(content: Content) -> some View {
        content.font(.system(size: size * zoom, weight: weight, design: mono ? .monospaced : .default))
    }
}

extension View {
    /// Zoom-aware font: all text in the app goes through this so ⌘+ / ⌘- scale the whole UI.
    func ui(_ size: CGFloat = 13, _ weight: Font.Weight = .regular, mono: Bool = false) -> some View {
        modifier(UIFontModifier(size: size, weight: weight, mono: mono))
    }

    func card(padding: CGFloat = 10) -> some View {
        self.padding(padding)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(Color.primary.opacity(0.08)))
    }
}
