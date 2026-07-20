import SwiftUI

// CURRIMUS design language — near-black ink, one signal hue, tabular numerals.
enum Theme {
    static let bg = Color(hex: 0x0A0A0A)
    static let ink = Color(hex: 0xF5F4F2)
    static let signal = Color(hex: 0xFF4D00)
    static let muted = Color(hex: 0x6B6B6B)
    /// Readability pass: metric labels are brighter than plain muted.
    static let bright = Color(hex: 0xA8A8A8)
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
    /// Above this size, type is display type: the race countdown, the week
    /// total, the run hero. It sits in fixed grids tuned to the design and is
    /// already the largest thing on screen, so it does not scale.
    static let displayThreshold: CGFloat = 20

    /// Bundled Space Grotesk face for a given weight.
    ///
    /// Small type — labels, list rows, explanatory copy — scales with Dynamic
    /// Type. At the default setting `relativeTo:` yields exactly `size`, so
    /// nothing moves for most people; the app root caps the top end.
    static func sg(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let face: String
        switch weight {
        case .bold, .heavy, .black: face = "SpaceGrotesk-Bold"
        case .semibold: face = "SpaceGrotesk-SemiBold"
        case .medium: face = "SpaceGrotesk-Medium"
        case .light, .thin, .ultraLight: face = "SpaceGrotesk-Light"
        default: face = "SpaceGrotesk-Regular"
        }
        #if os(iOS)
        if size <= displayThreshold {
            return .custom(face, size: size, relativeTo: .body)
        }
        #endif
        // watchOS stays fixed throughout: the run glance is a measured grid
        // whose values are already the biggest type in the product, and a
        // reflowed pace mid-stride helps nobody.
        return .custom(face, size: size)
    }

    /// Numeric display type — Space Grotesk semibold with tabular digits.
    static func stat(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        sg(size, weight: weight).monospacedDigit()
    }
}

/// Space Grotesk's line box is 1.276 em tall (984 ascent / 292 descent at
/// 1000 upm, cap height 700). The design crops every numeric line to
/// `line-height: 1`, slicing 0.138 em off each side of that box; SwiftUI
/// keeps the full box. So a padding copied 1:1 from the design renders
/// 0.138 em too tall for every cropped text edge it touches — these helpers
/// convert the design's gaps into the paddings that land the same ink gap.
enum LineBox {
    /// What `line-height: 1` crops from each side, as a fraction of the size.
    static let crop: CGFloat = (1.276 - 1) / 2
    /// Descender room under a digit line (digits have no descenders).
    static let descent: CGFloat = 0.292

    /// The design's gap minus the crop for each `line-height: 1` edge it
    /// touches. Label edges (`line-height: normal`) need no correction.
    static func gap(_ designGap: CGFloat, cropping sizes: CGFloat...) -> CGFloat {
        sizes.reduce(designGap) { $0 - crop * $1 }
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
