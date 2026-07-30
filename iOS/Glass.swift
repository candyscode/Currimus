import SwiftUI

/// iOS v2 design tokens layered on the shared Theme.
extension Theme {
    /// Translucent content card fill / border (the faint white overlay panels).
    static let glassCardFill = Color.white.opacity(0.045)
    static let glassCardStroke = Color.white.opacity(0.08)
    static let chipFill = Color.white.opacity(0.07)
    static let chipStroke = Color.white.opacity(0.09)
}

// MARK: - Liquid Glass building blocks

/// A translucent content panel (the design's rgba-white cards). Not heavy
/// Liquid Glass — a quiet fill so numbers stay legible.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 24
    var padding: EdgeInsets = EdgeInsets(top: 20, leading: 22, bottom: 20, trailing: 22)
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(Theme.glassCardFill, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Theme.glassCardStroke, lineWidth: 1))
    }
}

/// A circular 44pt Liquid Glass button (back / settings).
/// Uses non-interactive glass so the Button's tap wins on the first touch —
/// `.interactive()` glass otherwise swallows the first tap for its own morph.
struct GlassIconButton: View {
    var systemImagePath: GlassGlyph
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            systemImagePath.shape
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .glassEffect(.regular, in: Circle())
                .foregroundStyle(Theme.ink)
        }
        .buttonStyle(.plain)
        // A glyph is not a name. These three were unlabelled, so VoiceOver
        // announced the back, close and settings buttons as "button" and
        // nothing else — and a screen whose only way out is unnamed is a
        // screen with no way out.
        .accessibilityLabel(systemImagePath.name)
    }
}

/// Hand-drawn glyphs matching the design's stroked SVG icons.
enum GlassGlyph {
    case back, settings, close

    var name: LocalizedStringKey {
        switch self {
        case .back: return "Back"
        case .settings: return "Settings"
        case .close: return "Close"
        }
    }

    @ViewBuilder var shape: some View {
        switch self {
        case .back:
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
        case .close:
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
        case .settings:
            SlidersGlyph()
                .stroke(Theme.ink, style: .init(lineWidth: 1.8, lineCap: .round))
                .frame(width: 20, height: 20)
        }
    }
}

/// The two-slider settings glyph from the design.
struct SlidersGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        // top track + knob at ~70%
        p.move(to: .init(x: w * 0.17, y: h * 0.29)); p.addLine(to: .init(x: w * 0.54, y: h * 0.29))
        p.addEllipse(in: CGRect(x: w * 0.62, y: h * 0.19, width: w * 0.2, height: h * 0.2))
        // bottom track + knob at ~30%
        p.move(to: .init(x: w * 0.83, y: h * 0.71)); p.addLine(to: .init(x: w * 0.46, y: h * 0.71))
        p.addEllipse(in: CGRect(x: w * 0.18, y: h * 0.61, width: w * 0.2, height: h * 0.2))
        return p
    }
}

// MARK: - Notice

/// A quiet piece of news: something the app did on its own that the runner
/// should know about, and that must not interrupt anything to say it. No
/// alert, no sheet — a card that sits at the top of a screen until it is
/// dismissed, optionally leading to the screen it is about.
struct NoticeCard: View {
    var systemImage: String
    var text: String
    var action: (() -> Void)?
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.signal)
                .padding(.top, 2)
            Text(text)
                .font(.sg(13)).foregroundStyle(Theme.bright)
                .lineSpacing(3).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 6))
        .background(Theme.glassCardFill, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.glassCardStroke, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { action?() }
    }
}

// MARK: - Explanatory text with sources

/// The quiet paragraph under a number that says where it came from.
///
/// Takes markdown, so a source can be named and linked inline
/// (`Source.tanda.link`) without the call site building an `AttributedString`
/// by hand. SwiftUI parses markdown in a literal `Text`, but not in an
/// interpolated `String` — which is exactly how these lines are assembled.
struct Explainer: View {
    var markdown: String
    var top: CGFloat = 0
    var color: Color = Theme.muted

    private var text: AttributedString {
        (try? AttributedString(markdown: markdown,
                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(markdown)
    }

    var body: some View {
        Text(text)
            .font(.sg(13)).foregroundStyle(color).lineSpacing(3)
            .tint(Theme.signal)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, top)
    }
}

// MARK: - Weekly goal

/// The weekly-distance picker, wherever it is offered.
///
/// One list of options, because there are two ways in now: the Settings row,
/// and the "goal 55 km" caption on Home, which used to state the goal and give
/// no way to change it — the number is right there, and the setting was three
/// taps away behind a screen that does not mention it.
struct WeeklyGoalMenu<Label: View>: View {
    @Binding var goalKm: Double
    @ViewBuilder var label: () -> Label

    var body: some View {
        Menu {
            ForEach(Array(stride(from: 20, through: 90, by: 5)), id: \.self) { goal in
                Button("\(goal) km") { goalKm = Double(goal) }
            }
        } label: {
            label()
        }
        .accessibilityLabel("Weekly goal")
        .accessibilityValue("\(Int(goalKm)) kilometres")
    }
}

// MARK: - Segmented chips (Log filter, Progress road/trail, Race Setup)

struct SegmentChips<T: Hashable>: View {
    var options: [(value: T, label: String)]
    @Binding var selection: T
    var flexible: [T: CGFloat] = [:]   // relative widths (Race Setup Marathon = 1.3)

    var body: some View {
        HStack(spacing: 10) {
            ForEach(options, id: \.value) { option in
                let active = option.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(.sg(14, weight: .semibold))
                        .foregroundStyle(active ? Theme.bg : Theme.bright)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background {
                            if active {
                                Capsule().fill(Theme.ink)
                            } else {
                                Capsule().fill(Theme.chipFill)
                                    .overlay(Capsule().stroke(Theme.chipStroke, lineWidth: 1))
                            }
                        }
                }
                .buttonStyle(.plain)
                .layoutPriority(flexible[option.value].map(Double.init) ?? 1)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// A tappable settings/list row with a trailing chevron (design's ≥56pt rows).
struct ChevronRow<Trailing: View>: View {
    var title: String
    var subtitle: String?
    var minHeight: CGFloat = 56
    var showsChevron: Bool = true
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.sg(16))
                if let subtitle {
                    Text(subtitle).font(.sg(13)).foregroundStyle(Theme.muted)
                }
            }
            Spacer()
            trailing()
                .font(.sg(15))
                .foregroundStyle(Theme.bright)
            if showsChevron {
                Chevron()
            }
        }
        // Padding *and* a minimum height: a short row is centred in 56 pt as
        // before, and a row whose subtitle wraps keeps the same gap to the
        // hairlines instead of growing tight against them.
        .padding(.vertical, 10)
        .frame(minHeight: minHeight)
        .contentShape(Rectangle())
    }
}

struct Chevron: View {
    var size: CGFloat = 16
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: size * 0.9, weight: .semibold))
            .foregroundStyle(Theme.muted)
    }
}

// MARK: - Toggle styled to the design

struct SignalToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { configuration.isOn.toggle() }
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? Theme.signal : Theme.track)
                    .frame(width: 52, height: 32)
                Circle()
                    .fill(configuration.isOn ? Theme.bg : Theme.ink)
                    .frame(width: 28, height: 28)
                    .padding(2)
            }
        }
        .buttonStyle(.plain)
        // The switch draws no text of its own, so without this VoiceOver
        // announced an unnamed button and read the row title as unrelated
        // static text. Hand back a real toggle carrying the label — bound to
        // the live state, not a constant: with `.constant` VoiceOver could
        // read the switch but its double-tap did nothing, so the setting was
        // reachable and unusable at the same time.
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}
