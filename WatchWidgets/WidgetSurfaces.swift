import WidgetKit
import SwiftUI

// The widgets' entries and views, split out of `CurrimusWidgets.swift` so the
// watch app can compile them too: `-screen widgets` renders them side by side
// in both rendering modes (see `Watch/WidgetPreview.swift`). A complication is
// otherwise only visible by putting it on a face by hand, which is exactly why
// the tinted-mode bug in CUR-42 shipped.
//
// `\.widgetFamily` and `\.widgetRenderingMode` are read-only environment keys,
// so the preview cannot inject either. Instead each rectangular surface is its
// own view — addressable without a family — and takes an optional `mode` that
// stands in for the environment. Both are nil in the widgets themselves.

/// A tinted watch face flattens the widget to a single hue: every colour is
/// replaced by the face's own and **only the alpha channel survives**. So in
/// that mode the design's greys have to be expressed as opacity rather than as
/// hue — a `0x2E2E2E` track under an orange fill arrives as one flat line of
/// identical white, which is how the week bar became unreadable on every face
/// but "Bunt" (CUR-42).
struct WidgetPalette {
    var mode: WidgetRenderingMode

    var isTinted: Bool { mode != .fullColor }
    /// The hero numbers.
    var value: Color { isTinted ? .white : Theme.ink }
    /// Kickers and units — bright enough to read at a glance on a wrist.
    var label: Color { isTinted ? .white.opacity(0.62) : Theme.bright }
    /// Secondary figures that are not the point of the widget.
    var secondary: Color { isTinted ? .white.opacity(0.75) : Theme.dim }
    var track: Color { isTinted ? .white.opacity(0.25) : Theme.track }
    var fill: Color { isTinted ? .white : Theme.signal }
}

// MARK: - This week

struct WeekEntry: TimelineEntry {
    var date: Date
    var weekKm: Double
    var goalKm: Double
    var lastPace: TimeInterval
    var runCount: Int
}

struct WeekWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: WeekEntry

    var body: some View {
        switch family {
        case .accessoryRectangular: WeekRectangularView(entry: entry)
        case .accessoryInline: Text("\(Format.km(entry.weekKm, decimals: 1)) km this week")
        default: WeekCircularView(entry: entry)
        }
    }
}

struct WeekCircularView: View {
    @Environment(\.widgetRenderingMode) private var environmentMode
    var entry: WeekEntry
    var mode: WidgetRenderingMode?

    private var palette: WidgetPalette { WidgetPalette(mode: mode ?? environmentMode) }

    var body: some View {
        VStack(spacing: 2) {
            Text("WEEK")
                .font(.sg(7, weight: .medium))
                .kerning(0.8)
                .foregroundStyle(palette.label)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(Int(entry.weekKm))").font(.stat(17)).foregroundStyle(palette.value)
                Text("km").font(.sg(9)).foregroundStyle(palette.label)
            }
            ProgressCapsule(fraction: entry.weekKm / max(entry.goalKm, 1), mode: mode)
                .frame(width: 30, height: 3)
        }
    }
}

/// Type is ~20 % up on the first cut and a stop brighter (CUR-42) — this is
/// read at arm's length, mid-stride. The last pace moved into the corner the
/// "C" used to occupy, which is what buys the value row its width.
struct WeekRectangularView: View {
    @Environment(\.widgetRenderingMode) private var environmentMode
    var entry: WeekEntry
    var mode: WidgetRenderingMode?

    private var palette: WidgetPalette { WidgetPalette(mode: mode ?? environmentMode) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text("THIS WEEK")
                    .font(.sg(10, weight: .medium))
                    .kerning(1.1)
                    .foregroundStyle(palette.label)
                Spacer(minLength: 0)
                if entry.lastPace > 0 {
                    Text("\(Format.pace(entry.lastPace)) /km")
                        .font(.stat(10, weight: .regular))
                        .foregroundStyle(palette.secondary)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Format.km(entry.weekKm, decimals: 1))
                    .font(.stat(23))
                    .foregroundStyle(palette.value)
                Text("of \(Int(entry.goalKm)) km")
                    .font(.sg(11))
                    .foregroundStyle(palette.label)
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            ProgressCapsule(fraction: entry.weekKm / max(entry.goalKm, 1), mode: mode)
                .frame(height: 5)
        }
    }
}

// MARK: - Distance

struct DistanceEntry: TimelineEntry {
    var date: Date
    var totals: DistanceTotals
}

struct DistanceWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: DistanceEntry

    var body: some View {
        switch family {
        case .accessoryInline: Text(DistanceRectangularView.inline(entry.totals))
        default: DistanceRectangularView(entry: entry)
        }
    }
}

struct DistanceRectangularView: View {
    @Environment(\.widgetRenderingMode) private var environmentMode
    var entry: DistanceEntry
    var mode: WidgetRenderingMode?

    private var palette: WidgetPalette { WidgetPalette(mode: mode ?? environmentMode) }

    /// Three columns whose width is the **number's**, with the leftover split
    /// into two equal spacers.
    ///
    /// That is what makes the row sit straight (CUR-43). Equal columns did
    /// not: each was as wide as the wider of its number and its label, so
    /// "WEEK" pushed "8.8" away from its column's left edge while "600" left a
    /// gap at the right, and the whole row read as shifted left. Sizing by the
    /// label is no better — at 8.8 / 8.8 / 600 the two gaps between the
    /// numbers came out 9 pt apart. So the numbers own the layout and the
    /// labels are drawn outside it; two identical spacers then put exactly the
    /// same gap between all three, with the first number on the left inset and
    /// the last one on the right.
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("DISTANCE")
                .font(.sg(10, weight: .medium))
                .kerning(1.1)
                .foregroundStyle(palette.label)
            HStack(spacing: 0) {
                column("WEEK", Format.km(entry.totals.weekKm, decimals: 1), accented: true)
                Spacer(minLength: 6)
                column("MONTH", Format.compactKm(entry.totals.monthKm))
                Spacer(minLength: 6)
                column("YEAR", Format.compactKm(entry.totals.yearKm))
            }
        }
        // A hair of breathing room off the face's own edge, and the same on
        // both sides — the row is symmetric now, so the inset has to be too.
        .padding(.horizontal, 3)
    }

    /// One horizon: the number, and under it what it counts. The week is the
    /// one that carries the signal colour — it is the number a runner acts on,
    /// and in a tinted face it is what the accent group tints.
    private func column(_ label: LocalizedStringKey, _ value: String, accented: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.stat(20))
                .foregroundStyle(accented ? palette.fill : palette.value)
                .widgetAccentable(accented)
            // Zero layout width, natural drawn width: the label hangs out of
            // its column to the right rather than widening it, so it cannot
            // move the number above it. The same overflow trick `BigStat`
            // uses on the watch. It has room — the widest label (MONTH, ~36 pt
            // at 9 pt) overhangs the narrowest number by less than half the
            // gap between two columns.
            Text(label)
                .font(.sg(9, weight: .medium))
                .kerning(0.9)
                .foregroundStyle(palette.label)
                .fixedSize()
                .frame(width: 0, alignment: .leading)
        }
        .lineLimit(1)
        // The last reserve on a narrow case: three four-digit totals do not
        // fit 40 mm at full size.
        .minimumScaleFactor(0.6)
    }

    static func inline(_ totals: DistanceTotals) -> String {
        "\(Format.km(totals.weekKm, decimals: 1)) · \(Format.compactKm(totals.monthKm)) · \(Format.compactKm(totals.yearKm)) km"
    }
}

// MARK: - Shared parts

struct ProgressCapsule: View {
    @Environment(\.widgetRenderingMode) private var environmentMode
    var fraction: Double
    var mode: WidgetRenderingMode?

    private var palette: WidgetPalette { WidgetPalette(mode: mode ?? environmentMode) }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.track)
                Capsule()
                    .fill(palette.fill)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                    .widgetAccentable()
            }
        }
    }
}
