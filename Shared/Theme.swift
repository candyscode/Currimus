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
    /// Bundled Space Grotesk face for a given weight.
    static func sg(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let face: String
        switch weight {
        case .bold, .heavy, .black: face = "SpaceGrotesk-Bold"
        case .semibold: face = "SpaceGrotesk-SemiBold"
        case .medium: face = "SpaceGrotesk-Medium"
        case .light, .thin, .ultraLight: face = "SpaceGrotesk-Light"
        default: face = "SpaceGrotesk-Regular"
        }
        return .custom(face, size: size)
    }

    /// Numeric display type — Space Grotesk semibold with tabular digits.
    static func stat(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        sg(size, weight: weight).monospacedDigit()
    }
}

extension View {
    /// Uppercase tracked label in muted gray, e.g. "LAST RUN".
    /// `tracking` is the CSS letter-spacing in em (design uses 0.10–0.20).
    func kicker(_ size: CGFloat, color: Color = Theme.muted, tracking: CGFloat = 0.14) -> some View {
        font(.sg(size))
            .kerning(size * tracking)
            .foregroundStyle(color)
    }
}

/// The trail mark — hard-edged filled triangle, like the design's ▲ glyph.
struct TriangleMark: Shape {
    var pointingDown = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if pointingDown {
            path.move(to: .init(x: rect.minX, y: rect.minY))
            path.addLine(to: .init(x: rect.maxX, y: rect.minY))
            path.addLine(to: .init(x: rect.midX, y: rect.maxY))
        } else {
            path.move(to: .init(x: rect.midX, y: rect.minY))
            path.addLine(to: .init(x: rect.maxX, y: rect.maxY))
            path.addLine(to: .init(x: rect.minX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}
