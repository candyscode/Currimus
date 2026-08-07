#if DEBUG
import SwiftUI
import WidgetKit

/// The rectangular complications, rendered inside the app so they can be
/// looked at (`-screen widgets`).
///
/// A widget is otherwise only visible by editing a watch face by hand, and the
/// *tinted* rendering needs a face colour set on top of that — which is why the
/// week widget shipped with a progress bar that vanished on every face but
/// "Bunt" (CUR-42).
///
/// The tinted pane is an honest emulation: watchOS replaces every colour with
/// the face's own and keeps nothing but the alpha channel, and `tint.mask(view)`
/// is exactly that operation. It is the worst case — the real thing splits the
/// content into an accent group and a default group and gives them two shades —
/// so a layout that survives here survives on a face.
struct WidgetPreviewView: View {
    /// `-screen widgets` for the colour faces, `-screen widgets-tint` for the
    /// tinted ones. Two routes rather than one scroller: four panes do not fit
    /// above the fold, and a screenshot cannot scroll.
    var tinted: Bool

    private let week = WeekEntry(date: .now, weekKm: 7, goalKm: 55, lastPace: 312, runCount: 2)
    private let totals = DistanceEntry(
        date: .now,
        totals: DistanceTotals(weekKm: 7, monthKm: 84.2, yearKm: 1204)
    )

    private var tint: Color? { tinted ? .red : nil }
    private var mode: WidgetRenderingMode { tinted ? .accented : .fullColor }

    var body: some View {
        VStack(spacing: 10) {
            pane(tinted ? "WEEK · TINTED" : "WEEK · COLOR", tint: tint) {
                WeekRectangularView(entry: week, mode: mode)
            }
            pane(tinted ? "DIST · TINTED" : "DIST · COLOR", tint: tint) {
                DistanceRectangularView(entry: totals, mode: mode)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private func pane<Content: View>(
        _ caption: String,
        tint: Color? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(caption).kicker(8, color: Theme.faint)
            let widget = content()
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint == nil ? Theme.bg : Color.black)
                if let tint {
                    // The hidden copy carries the size — a mask on its own is
                    // as flexible as the colour it masks, and the pane
                    // collapses to nothing.
                    widget.hidden().overlay { tint.mask(widget) }
                } else {
                    widget
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
#endif
