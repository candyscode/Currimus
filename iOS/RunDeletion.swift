import SwiftUI

/// Everything the delete interaction needs that is not a screen: the wording,
/// and the container the log rows sit in to be swiped.

// MARK: - Wording

/// One place decides how a delete is phrased, because the log, the selection
/// mode and the run detail all ask the same question and must ask it the same
/// way — including the part people actually need to know, which is that this
/// reaches Apple Health.
enum DeletePrompt {
    static func title(_ runs: [Run]) -> String {
        runs.count == 1
            ? String(localized: "Delete this run?")
            : String(localized: "Delete \(runs.count) runs?")
    }

    static func message(_ runs: [Run]) -> String {
        let km = Format.km(runs.reduce(0) { $0 + $1.distanceKm }, decimals: 1)
        if let run = runs.first, runs.count == 1 {
            let day = run.date.formatted(.dateTime.day().month(.wide))
            return String(localized: "\(Format.km(run.distanceKm)) km, \(day). Every total and record is recalculated without it, and the workout is removed from Apple Health.")
        }
        return String(localized: "\(runs.count) runs, \(km) km in total. Every total and record is recalculated without them, and their workouts are removed from Apple Health.")
    }
}

// MARK: - Swipe container

/// A row that reveals one trailing action when it is dragged to the left.
///
/// `List`'s `swipeActions` is not on the table: the log groups by month, draws
/// its own hairlines and sits on the app's background, none of which survives
/// a `List`. So the gesture is drawn here — and only takes over once the drag
/// is clearly sideways, which is what keeps it out of the scroll view's way.
///
/// `openRow` is shared by every row in the list, so opening one closes the
/// rest and a tap anywhere can put them all away.
struct SwipeToRevealRow<Content: View>: View {
    var id: UUID
    var label: LocalizedStringKey
    var systemImage: String
    @Binding var openRow: UUID?
    var action: () -> Void
    @ViewBuilder var content: Content

    /// Wide enough for the glyph and its word at the design's type sizes.
    private static var actionWidth: CGFloat { 88 }
    /// How far past the action the row may be dragged, so the gesture has
    /// somewhere to go instead of ending against a wall.
    private static var overshoot: CGFloat { 28 }

    @State private var drag: CGFloat = 0

    private var isOpen: Bool { openRow == id }

    private var offset: CGFloat {
        let resting = isOpen ? -Self.actionWidth : 0
        return min(0, max(-Self.actionWidth - Self.overshoot, resting + drag))
    }

    var body: some View {
        content
            // The rows are transparent, so without a fill of the app's own
            // background the action tile would show straight through them.
            .background(Theme.bg)
            .offset(x: offset)
            // Applied outside the offset: `offset` moves what is drawn, not
            // the layout, so this background stays put while the row slides.
            .background(alignment: .trailing) { actionTile }
            .clipped()
            .contentShape(Rectangle())
            // Simultaneous, not exclusive: a plain `gesture` here wins the
            // touch outright and the log stops scrolling wherever a row is,
            // which is everywhere. Sharing it lets the scroll view keep the
            // vertical drags, while the guard below ignores them here.
            .simultaneousGesture(swipe)
            .accessibilityAction(named: Text(label), action)
    }

    private var actionTile: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage).font(.system(size: 17, weight: .semibold))
                Text(label).font(.sg(12, weight: .semibold))
            }
            .foregroundStyle(Theme.bg)
            .frame(width: Self.actionWidth)
            .frame(maxHeight: .infinity)
            .background(Theme.signal, in: RoundedRectangle(cornerRadius: 14))
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        // Nothing to hit while the row is closed — the row itself covers it,
        // but a stray tap through the corners should not delete a run either.
        .allowsHitTesting(isOpen)
        .accessibilityHidden(true)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                // Vertical intent belongs to the scroll view, always.
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if !isOpen, openRow != nil { openRow = nil }
                drag = value.translation.width
            }
            .onEnded { value in
                let resting = isOpen ? -Self.actionWidth : 0
                // Flicks count: where the row would come to rest decides, not
                // where the finger happened to leave the glass.
                let projected = resting + value.predictedEndTranslation.width
                withAnimation(.snappy(duration: 0.25)) {
                    if projected < -Self.actionWidth / 2 {
                        openRow = id
                    } else if isOpen {
                        openRow = nil
                    }
                    drag = 0
                }
            }
    }
}
