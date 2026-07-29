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

    /// Why a run another app recorded cannot be deleted here. Named plainly,
    /// because "not possible" without a reason reads as a bug in Currimus.
    static func importedExplanation(_ run: Run) -> String {
        String(localized: "Apple Health only lets the app that recorded a run delete it, so Currimus cannot remove this one. Delete it in \(run.name), or in the Fitness app, and it will disappear from Currimus on the next refresh.")
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
/// `openRow` says which row is currently showing its action, so opening one
/// closes the rest and a tap anywhere puts them away.
///
/// The row owns its own offset. It used to derive it from `openRow` and add a
/// live drag on top, which meant the settle animation depended on the parent's
/// state landing inside the same transaction — and when it did not, the row
/// slid back under the finger and the button could never be hit. One source of
/// truth here, `openRow` only for closing the others.
struct SwipeToRevealRow<Content: View>: View {
    var id: UUID
    var label: LocalizedStringKey
    var systemImage: String
    /// A muted tile is still pressable. A row that cannot be deleted must say
    /// so when asked rather than swallow the swipe and look broken.
    var isMuted = false
    @Binding var openRow: UUID?
    var action: () -> Void
    /// What a tap on the row itself does — but only when the row is closed.
    ///
    /// The row owns this rather than the content, because the content used to
    /// be a `Button` and that was the whole bug: a horizontal drag never
    /// leaves a full-width button's bounds, so SwiftUI did not cancel it, and
    /// lifting the finger fired the tap that closed the row again. The button
    /// is gone; a `TapGesture` alongside the drag will not fire once the
    /// finger has travelled.
    var onTap: () -> Void
    @ViewBuilder var content: Content

    /// Wide enough for the glyph and its word at the design's type sizes.
    private static var actionWidth: CGFloat { 88 }
    /// Air between the row's own trailing edge and the tile, so the pace does
    /// not sit flush against the delete button once the row settles.
    private static var actionGap: CGFloat { 14 }
    /// How far the list is inset from the screen. The row slides *past* it:
    /// text disappearing at the display edge reads as a row moving off screen,
    /// text disappearing 26 pt early reads as a rendering fault.
    private static var listInset: CGFloat { 26 }
    /// Where an open row rests.
    private static var openOffset: CGFloat { -(actionWidth + actionGap) }
    /// How far past the action the row may be dragged, so the gesture has
    /// somewhere to go instead of ending against a wall.
    private static var overshoot: CGFloat { 28 }

    @State private var offset: CGFloat = 0
    /// Where the row sat when this drag began.
    @State private var base: CGFloat = 0
    @State private var isDragging = false

    var body: some View {
        content
            // The rows are transparent, so without a fill of the app's own
            // background the action tile would show straight through them.
            .background(Theme.bg)
            .offset(x: offset)
            // Applied outside the offset: `offset` moves what is drawn, not
            // the layout, so this background stays put while the row slides.
            .background(alignment: .trailing) { actionTile }
            // Masked rather than clipped, and widened to the screen edge: a
            // mask has no say in layout, so the row keeps its place in the
            // list while its content is free to slide off the display.
            .mask(alignment: .leading) {
                Rectangle().padding(.leading, -Self.listInset)
            }
            .contentShape(Rectangle())
            // Simultaneous, not exclusive: a plain `gesture` here wins the
            // touch outright and the log stops scrolling wherever a row is,
            // which is everywhere. Sharing it lets the scroll view keep the
            // vertical drags, while the guard below ignores them here.
            .simultaneousGesture(swipe)
            // A tap, not a Button. The content used to be one, and a drag that
            // never leaves a full-width button's bounds is not cancelled by
            // SwiftUI — so lifting the finger fired the row's own tap, which
            // closed the row again before the delete tile could be hit. A
            // TapGesture does not fire once the finger has travelled.
            .onTapGesture {
                guard offset == 0 else {
                    withAnimation(.snappy(duration: 0.25)) { offset = 0 }
                    openRow = nil
                    return
                }
                onTap()
            }
            .onAppear {
                // A row can be created already open: the marking mode leaves
                // and re-enters, and the screenshot route opens one on launch.
                if openRow == id, offset == 0 { offset = Self.openOffset }
            }
            .onChange(of: openRow) { _, now in
                // Opened from outside the gesture — the screenshot route does
                // this, and so would any future "reveal the row I just added".
                if now == id {
                    guard !isDragging, offset == 0 else { return }
                    withAnimation(.snappy(duration: 0.25)) { offset = Self.openOffset }
                    return
                }
                // Somebody else opened, or everything was put away. This is
                // authoritative even mid-drag: a gesture the scroll view took
                // over never gets its `onEnded`, and treating that as "still
                // dragging" left the row stuck half-open with no way back.
                isDragging = false
                guard offset != 0 else { return }
                withAnimation(.snappy(duration: 0.25)) { offset = 0 }
            }
            .accessibilityAction(named: Text(label), action)
    }

    private var actionTile: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage).font(.system(size: 17, weight: .semibold))
                Text(label).font(.sg(12, weight: .semibold))
            }
            .foregroundStyle(isMuted ? Theme.dim : Theme.bg)
            .frame(width: Self.actionWidth)
            .frame(maxHeight: .infinity)
            .background(isMuted ? Theme.track : Theme.signal,
                        in: RoundedRectangle(cornerRadius: 14))
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        // Nothing to hit while the row is closed — the row itself covers it,
        // but a stray tap through the corners should not delete a run either.
        .allowsHitTesting(offset < -20)
        // A real button once revealed, rather than hidden from accessibility:
        // VoiceOver reaches it, and so does the UI test that guards this
        // gesture — which is the only way anything but a finger can.
        .accessibilityIdentifier("swipe-action")
        .accessibilityHidden(offset > -20)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                // Vertical intent belongs to the scroll view — but only until
                // this row has taken the drag. Re-checking every frame let a
                // swipe freeze the moment the finger wandered downwards.
                guard isDragging
                        || abs(value.translation.width) > abs(value.translation.height) else { return }
                if !isDragging {
                    isDragging = true
                    base = offset
                    // Claiming the slot here closes any other open row at the
                    // start of the swipe rather than at the end of it.
                    openRow = id
                }
                offset = clamp(base + value.translation.width)
            }
            .onEnded { value in
                guard isDragging else { return }
                isDragging = false
                // Flicks count: where the row would come to rest decides, not
                // where the finger happened to leave the glass.
                let projected = base + value.predictedEndTranslation.width
                let opens = projected < Self.openOffset / 2
                withAnimation(.snappy(duration: 0.25)) {
                    offset = opens ? Self.openOffset : 0
                }
                openRow = opens ? id : nil
            }
    }

    private func clamp(_ x: CGFloat) -> CGFloat {
        min(0, max(Self.openOffset - Self.overshoot, x))
    }
}
