import SwiftUI

// CURRIMUS design language — near-black ink, one signal hue, tabular numerals.
enum Theme {
    static let bg = Color(hex: 0x0A0A0A)
    static let ink = Color(hex: 0xF5F4F2)
    static let signal = Color(hex: 0xFF4D00)
    static let muted = Color(hex: 0x6B6B6B)
    static let faint = Color(hex: 0x5A5A5A)
    static let dim = Color(hex: 0x8F8F8F)
    static let track = Color(hex: 0x2E2E2E)
    static let trackIdle = Color(hex: 0x1C1C1C)
    static let hairline = Color(hex: 0x1E1E1E)
    static let card = Color(hex: 0x141414)
    static let cardBorder = Color(hex: 0x242424)
    static let button = Color(hex: 0x1D1D1D)
    static let buttonBorder = Color(hex: 0x2A2A2A)
    static let ghost = Color(hex: 0x3D3D3D)

    /// Heat ramp used for time-in-zone bars (Z1…Z5).
    static let zoneHeat: [Color] = [
        signal.opacity(0.14), signal.opacity(0.30), signal.opacity(0.52),
        signal.opacity(0.76), signal,
    ]

    /// Segment color when a given zone (1-based) is the active one.
    static func zoneSegment(active zone: Int) -> Color {
        switch zone {
        case 1: return signal.opacity(0.35)
        case 2: return signal.opacity(0.55)
        case 3: return signal
        case 4: return signal.opacity(0.85)
        default: return signal
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension Font {
    /// Numeric display type — semibold, tight, tabular digits.
    static func stat(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }

    /// Small uppercase label type.
    static func label(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular)
    }
}

extension View {
    /// Uppercase tracked label in muted gray, e.g. "LAST RUN".
    func kicker(_ size: CGFloat, color: Color = Theme.muted) -> some View {
        font(.system(size: size, weight: .medium))
            .kerning(size * 0.12)
            .foregroundStyle(color)
    }
}
