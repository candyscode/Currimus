import SwiftUI

/// Where a number came from, on demand.
///
/// Every derived figure in this app can account for itself, and for a long time
/// it did that by printing a paragraph under the number. Those paragraphs grew
/// — the race screen's ran to five sentences — until the screen was mostly
/// justification and the reader had to walk through prose to find the one
/// figure they came for. Worse, numbers ended up *inside* the prose: the Riegel
/// prediction was a bolded time in the middle of a sentence, which is not a
/// field and cannot be read at a glance (Andi, 2026-07-30).
///
/// So: every number gets a field, and every field can be asked. The explanation
/// is one tap away and full length, which also means it no longer has to be
/// short enough to sit on the screen.
struct Explanation: Identifiable, Equatable {
    var title: String
    /// Markdown — the same inline subset `Explainer` renders, so the source
    /// links keep working.
    var body: String
    var id: String { title }
}

/// The small circled "i" that opens one.
///
/// Sized and coloured like the kickers it sits beside rather than like a
/// control: it is an offer, not an action, and it must not compete with the
/// number above it.
struct InfoButton: View {
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Theme.faint)
                // A 13 pt glyph is a 13 pt target; this is the 44 pt one
                // underneath it, without taking 44 pt of layout.
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("How \(label) is worked out")
    }
}

/// The sheet an `InfoButton` opens.
///
/// A sheet rather than a push: an explanation is an aside, and coming back from
/// it should not feel like navigating. Detents so it takes only the room it
/// needs — most of these are a paragraph — and grows for the ones that are not.
struct ExplanationSheet: View {
    var explanation: Explanation
    @Environment(\.dismiss) private var dismiss
    /// Measured, not `.medium`: most of these are a paragraph, and a fixed half
    /// screen left a hand's width of black under every one of them (Andi,
    /// CUR-38). The long ones still scroll and can still be pulled to full.
    @State private var height: CGFloat = 260
    /// The home indicator's strip. The scroll view is inset by it, so a detent
    /// of exactly the content height leaves the sheet permanently a few points
    /// short of its own text.
    @State private var bottomInset: CGFloat = 0

    /// Past this the sheet stops growing and starts scrolling — a modal that
    /// covers the screen should be dragged there deliberately, not arrive that
    /// way.
    private static let ceiling: CGFloat = 560

    /// `.large` is always offered, not only past the ceiling: an explanation
    /// that measures just under it fills most of a small phone, and a single
    /// fixed detent there can be neither expanded nor put away short of
    /// closing it.
    private var detents: Set<PresentationDetent> {
        [.height(min(height + bottomInset, Self.ceiling)), .large]
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(explanation.title.uppercased())
                        .kicker(13, color: Theme.bright, tracking: 0.12)
                    Explainer(markdown: explanation.body, top: 14, color: Theme.bright)
                }
                .padding(.horizontal, 26)
                .padding(.top, 70)
                .padding(.bottom, 34)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            }
            .scrollIndicators(.hidden)
            TopScrim {
                HStack {
                    Spacer()
                    GlassIconButton(systemImagePath: .close) { dismiss() }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.bg)
    }
}

extension View {
    /// Attaches the sheet to a screen. One binding per screen, whichever field
    /// was asked.
    func explanationSheet(_ explanation: Binding<Explanation?>) -> some View {
        sheet(item: explanation) { ExplanationSheet(explanation: $0) }
    }
}

/// A labelled figure that can account for itself.
///
/// The same shape as `BigDetailStat`, plus the info affordance beside the
/// label — so a screen full of these reads as one row of numbers, not as a
/// number and a paragraph and another number.
struct ExplainedStat: View {
    var value: String
    var label: String
    var accent: Bool = false
    /// nil where there is nothing to explain — a goal the user typed in needs
    /// no derivation.
    var explanation: Explanation?
    var onExplain: (Explanation) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.stat(34)).kerning(-0.5)
                .foregroundStyle(accent ? Theme.signal : Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
            HStack(spacing: 2) {
                Text(label).kicker(13, color: Theme.bright, tracking: 0.12).fixedSize()
                if let explanation {
                    InfoButton(label: label.lowercased()) { onExplain(explanation) }
                        // Pulled tight to the label: the two are one unit, and
                        // the button's own 30 pt target does the rest.
                        .padding(.leading, -6)
                }
            }
        }
    }
}
