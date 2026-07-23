import SwiftUI

// The 10-foot components. They speak the same design language as the iPhone
// (Theme colours, Space Grotesk via `.sg`/`.stat`, the single signal accent)
// but are sized for a television seen across a room: taller bars, larger type,
// generous spacing. The iOS chart shapes in `iOS/Charts.swift` are tuned to
// iPhone point sizes and belong to the iOS target, so the TV carries its own.

// MARK: - Focus / scrolling

/// Makes a *read-only* panel focusable so the Siri Remote can move onto it and
/// carry the scroll view to it.
///
/// tvOS only scrolls a `ScrollView` toward content the focus engine can reach;
/// a screen of pure text (the dashboard, the progress panels) has nothing
/// focusable, so anything past the first screenful is unreachable with the
/// remote. Marking each section focusable fixes that generally — one modifier
/// for every such panel — rather than sprinkling ad-hoc focusable stubs.
///
/// The feedback is deliberately quiet: these panels are read, not activated, so
/// focus lifts them with the same faint fill a log row uses and a gentle scale,
/// not the bright system button glow.
///
/// Focus is read through `.focusable(_:)`'s own callback into `@State` rather
/// than the `isFocused` environment: the environment value is set *inside* the
/// focusable view's subtree, so a modifier that both applies `.focusable()` and
/// reads the environment at the same level never sees the change.
private struct ScrollFocusable: ViewModifier {
    @State private var isFocused = false
    func body(content: Content) -> some View {
        content
            .focusable(true) { focused in isFocused = focused }
            .scaleEffect(isFocused ? 1.02 : 1)
            .background(Theme.ink.opacity(isFocused ? 0.06 : 0),
                        in: RoundedRectangle(cornerRadius: 20))
            .animation(.easeOut(duration: 0.2), value: isFocused)
    }
}

extension View {
    /// See `ScrollFocusable`: makes a read-only section reachable by the remote.
    func scrollFocusable() -> some View { modifier(ScrollFocusable()) }
}

// MARK: - Cards & tiles

/// The translucent content panel, matching the iPhone's `GlassCard` tokens but
/// with the corner radius and padding a big screen wants.
struct TVCard<Content: View>: View {
    var padding: CGFloat = 36
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

/// A single big-number stat: value over an uppercase tracked kicker, the same
/// pairing the iPhone uses in `StatBlock`/`DetailStat`.
struct TVStat: View {
    var value: String
    var label: String
    var accent: Bool = false
    var valueSize: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value).font(.stat(valueSize)).foregroundStyle(accent ? Theme.signal : Theme.ink).lineLimit(1)
            Text(label).kicker(18, color: Theme.bright, tracking: 0.12)
        }
    }
}

/// An uppercase section kicker, sized for the TV.
struct TVSectionLabel: View {
    var text: String
    var body: some View {
        Text(text).kicker(20, color: Theme.bright, tracking: 0.12)
    }
}

// MARK: - Bars

/// Weekday volume bars (Mon-first). The latest run day burns Signal; rest days
/// are a thin idle stub — the same reading as the iPhone's `WeekBars`.
struct TVWeekBars: View {
    var kmPerDay: [Double]
    var height: CGFloat = 220
    private let labels = ["M", "T", "W", "T", "F", "S", "S"]
    private var latest: Int? { kmPerDay.lastIndex { $0 > 0 } }

    /// Monday-first weekday names for VoiceOver — the visible labels are single
    /// letters, which read as nonsense out loud. Matches the iPhone `WeekBars`.
    private var spokenSummary: String {
        let symbols = Calendar.current.weekdaySymbols
        let mondayFirst = Array(symbols[1...]) + [symbols[0]]
        return zip(mondayFirst, kmPerDay).map { name, km in
            km > 0 ? "\(name) \(Format.km(km, decimals: 1)) km" : "\(name) rest"
        }.joined(separator: ", ")
    }

    var body: some View {
        let maxKm = max(kmPerDay.max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 16) {
            ForEach(0..<7, id: \.self) { day in
                let ran = kmPerDay[day] > 0
                let isLatest = day == latest
                VStack(spacing: 14) {
                    Spacer(minLength: 0)
                    if ran {
                        Text(Format.km(kmPerDay[day], decimals: 1))
                            .font(.stat(18, weight: isLatest ? .semibold : .regular))
                            .foregroundStyle(isLatest ? Theme.signal : Theme.muted)
                    }
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isLatest ? Theme.signal : (ran ? Theme.track : Theme.trackIdle))
                        .frame(height: ran ? max(kmPerDay[day] / maxKm * height, 14) : 8)
                    Text(labels[day])
                        .font(.sg(18, weight: isLatest ? .semibold : .regular))
                        .foregroundStyle(isLatest ? Theme.ink : Theme.muted)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height + 80, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kilometres per day this week")
        .accessibilityValue(spokenSummary)
    }
}

/// Labelled monthly bars (km or climb). Current month burns Signal — matches
/// the iPhone's `MonthBars`.
struct TVMonthBars: View {
    var items: [(label: String, value: Double)]
    var height: CGFloat = 200
    /// What the numbers are, for VoiceOver ("kilometres", "metres of climb").
    var unit: String = ""
    var format: (Double) -> String

    var body: some View {
        let maxV = max(items.map(\.value).max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 20) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let current = index == items.count - 1
                VStack(spacing: 12) {
                    Text(format(item.value))
                        .font(.stat(18, weight: current ? .semibold : .regular))
                        .foregroundStyle(current ? Theme.signal : Theme.muted)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(current ? Theme.signal : Theme.track)
                        .frame(height: max(item.value / maxV * height, 8))
                    Text(item.label)
                        .font(.sg(18, weight: current ? .semibold : .regular))
                        .foregroundStyle(current ? Theme.ink : Theme.muted)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height + 80, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Monthly totals")
        .accessibilityValue(items.map { "\($0.label) \(format($0.value)) \(unit)" }
            .joined(separator: ", "))
    }
}

/// Per-km split bars (run detail). Fastest km burns Signal, like `SplitBars`.
struct TVSplitBars: View {
    var splits: [TimeInterval]

    var body: some View {
        let slowest = splits.max() ?? 1
        let fastest = splits.min() ?? 0
        VStack(spacing: 14) {
            ForEach(Array(splits.enumerated()), id: \.offset) { index, split in
                let isFastest = split == fastest && splits.count > 1
                HStack(spacing: 18) {
                    Text("\(index + 1)")
                        .font(.stat(18, weight: .regular))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 32, alignment: .leading)
                    GeometryReader { proxy in
                        let spread = max(slowest - fastest, 1)
                        let frac = 0.5 + 0.5 * (split - fastest) / spread
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isFastest ? Theme.signal : Theme.track)
                            .frame(width: proxy.size.width * frac)
                    }
                    .frame(height: 22)
                    Text(Format.pace(split))
                        .font(.stat(20, weight: .regular))
                        .foregroundStyle(isFastest ? Theme.signal : Theme.ink)
                        .frame(width: 110, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Kilometre \(index + 1)")
                .accessibilityValue(isFastest
                    ? "\(Format.pace(split)) per kilometre, fastest"
                    : "\(Format.pace(split)) per kilometre")
            }
        }
    }
}

/// Proportional time-in-zone heat strip, matching `ZoneHeatStrip`.
struct TVZoneHeatStrip: View {
    var zoneSeconds: [TimeInterval]
    var height: CGFloat = 20

    var body: some View {
        GeometryReader { proxy in
            let total = zoneSeconds.reduce(0, +)
            if total < 1 {
                Capsule().fill(Theme.trackIdle)
                    .frame(width: proxy.size.width, height: height)
            } else {
                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { index in
                        Theme.zoneHeat[index]
                            .frame(width: max(proxy.size.width * zoneSeconds[index] / total - 3, 0))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: height / 2))
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time in heart rate zones")
        .accessibilityValue(spokenSummary)
    }

    /// The zones with meaningful time in them, as percentages — matching the
    /// iPhone `ZoneHeatStrip`. Zones under 30 s are noise and stay out.
    private var spokenSummary: String {
        let total = zoneSeconds.reduce(0, +)
        guard total >= 1 else { return "No heart rate recorded" }
        return zoneSeconds.enumerated()
            .filter { $0.element >= 30 }
            .map { index, seconds in "zone \(index + 1) \(Int((seconds / total * 100).rounded()))%" }
            .joined(separator: ", ")
    }
}

/// A trend polyline over gridlines with end dot — the TV twin of `TrendChart`.
/// `values` oldest→newest; nil gaps are bridged. Lower = higher on screen when
/// `invert` (pace: faster is better).
struct TVTrendChart: View {
    var values: [TimeInterval?]
    var topLabel: String
    var bottomLabel: String
    var invert: Bool = true
    var height: CGFloat = 240
    /// What the line is, and how to say one of its values, for VoiceOver.
    var accessibilityTitle: String = "Trend"
    var describe: (TimeInterval) -> String = { Format.pace($0) }

    /// Oldest and newest point plus the direction between them — the shape a
    /// sighted reader takes from the line at a glance. Mirrors `TrendChart`.
    private var spokenSummary: String {
        let present = values.compactMap { $0 }
        guard let first = present.first, let last = present.last else { return "No data yet" }
        let direction = last == first ? "unchanged" : (last < first ? "improving" : "slipping")
        return "\(present.count) weeks, from \(describe(first)) to \(describe(last)), \(direction)"
    }

    var body: some View {
        let present = values.compactMap { $0 }
        let hi = present.max() ?? 1
        let lo = present.min() ?? 0
        let span = max(hi - lo, 1)
        let pts: [CGPoint] = values.enumerated().compactMap { i, v in
            guard let v else { return nil }
            let x = Double(i) / Double(max(values.count - 1, 1))
            let norm = (v - lo) / span
            let y = invert ? norm : 1 - norm
            return CGPoint(x: x, y: y)
        }
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { i in
                    Theme.hairline.frame(height: 1)
                    if i < 2 { Spacer() }
                }
            }
            GeometryReader { proxy in
                let mapped = pts.map { CGPoint(x: $0.x * proxy.size.width,
                                               y: (1 - $0.y) * proxy.size.height) }
                Path { p in
                    guard let first = mapped.first else { return }
                    p.move(to: first); mapped.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(Theme.signal, style: .init(lineWidth: 4, lineCap: .round, lineJoin: .round))
                if let last = mapped.last {
                    Circle().fill(Theme.signal).frame(width: 16, height: 16).position(last)
                }
                Text(topLabel).font(.stat(16)).foregroundStyle(Theme.faint).position(x: 24, y: 10)
                Text(bottomLabel).font(.stat(16)).foregroundStyle(Theme.faint)
                    .position(x: 24, y: proxy.size.height - 10)
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(spokenSummary)
    }
}

// MARK: - Route & elevation

/// Grid-paper card with the run's GPS path, the TV twin of `MapCard`. The route
/// and grid geometry are the shared `RouteShape` / `GridShape` (identical to the
/// phone); only the grid spacing, stroke width and padding are scaled up here.
struct TVRouteCard: View {
    var run: Run
    var height: CGFloat = 460

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            GridShape(step: 60).stroke(Color(hex: 0x1A1A1A), lineWidth: 1)
            RouteShape(route: run.route)
                .stroke(Theme.signal, style: .init(lineWidth: 5, lineCap: .round, lineJoin: .round))
                .padding(40)
            Text("MAP")
                .font(.sg(14, weight: .medium)).kerning(1.5)
                .foregroundStyle(Color(hex: 0x4A4A4A))
                .padding(24)
        }
        .frame(height: height)
        .background(Color(hex: 0x111111))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Theme.cardBorder, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(run.route?.isEmpty == false ? "Route map" : "Route map, no GPS track recorded")
    }
}

/// Elevation profile from altitude samples, using the shared `RoutePoints`
/// normalisation and `LineChart` shape so it matches the phone exactly.
struct TVElevationProfile: View {
    var samples: [Double]
    var height: CGFloat = 240

    var body: some View {
        let pts = RoutePoints.normalized(samples)
        LineChart(points: pts.map { CGPoint(x: $0.x, y: $0.y) })
            .stroke(Theme.signal, style: .init(lineWidth: 4, lineCap: .round, lineJoin: .round))
            .frame(height: height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Elevation profile")
            .accessibilityValue(spokenSummary)
    }

    /// Low / high and the endpoints — mirroring the iPhone `ElevationProfile`.
    private var spokenSummary: String {
        guard let low = samples.min(), let high = samples.max(), samples.count > 1 else {
            return "No elevation recorded"
        }
        return "From \(Format.elevation(samples[0])) to \(Format.elevation(samples[samples.count - 1])), "
            + "low \(Format.elevation(low)), high \(Format.elevation(high))"
    }
}

// MARK: - Rows

/// A log row for the TV — focusable, so the remote can move through the list
/// and the highlighted run lifts with a subtle fill. Mirrors `LogRow`'s content.
struct TVLogRow: View {
    var run: Run
    var prTag: String?
    @Environment(\.isFocused) private var isFocused

    private var isFast: Bool { !run.isTrail && run.paceSecPerKm < 310 }

    var body: some View {
        HStack(spacing: 28) {
            Text(run.date.formatted(.dateTime.weekday(.abbreviated)).uppercased()
                 + "  " + run.date.formatted(.dateTime.day(.twoDigits).month(.twoDigits)))
                .font(.sg(18)).foregroundStyle(Theme.muted)
                .frame(width: 160, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Text("\(Format.km(run.distanceKm)) km").font(.stat(26))
                    if run.isTrail { TVTrailTag() }
                }
                detail
            }
            Spacer()
            Text(Format.pace(run.paceSecPerKm))
                .font(.stat(26))
                .foregroundStyle(isFast || prTag != nil ? Theme.signal : Theme.ink)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .background(Theme.ink.opacity(isFocused ? 0.10 : 0), in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .bottom) { Theme.hairline.frame(height: 1).padding(.horizontal, 28) }
        // One clean sentence instead of the row's fragments, so the focused run
        // reads sensibly. The link wrapping this row supplies the button trait.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }

    private var spokenLabel: String {
        let date = run.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let pr = prTag.map { ", \($0)" } ?? ""
        let kind = run.isTrail ? "trail run" : run.classification.label
        return "\(date), \(Format.km(run.distanceKm)) kilometres, \(kind), "
            + "\(Format.pace(run.paceSecPerKm)) per kilometre\(pr)"
    }

    @ViewBuilder
    private var detail: some View {
        if run.isImported {
            Text("\(run.name) · \(Format.clock(run.duration))")
                .font(.stat(17, weight: .regular)).foregroundStyle(Theme.bright)
        } else if run.isTrail {
            Text("Trail · \(Format.clock(run.duration)) · +\(Int(run.climbMeters ?? 0)) m")
                .font(.stat(17, weight: .regular)).foregroundStyle(Theme.bright)
        } else if let prTag, prTag != "Longest" {
            (Text("\(Format.clock(run.duration)) · ") + Text(prTag).foregroundStyle(Theme.signal).fontWeight(.semibold))
                .font(.stat(17, weight: .regular)).foregroundStyle(Theme.bright)
        } else {
            Text("\(run.classification.label) · \(Format.clock(run.duration)) · Z\(run.dominantZone)")
                .font(.stat(17, weight: .regular)).foregroundStyle(Theme.bright)
        }
    }
}

struct TVTrailTag: View {
    var body: some View {
        Text("TRAIL")
            .font(.sg(14, weight: .bold)).kerning(1.5)
            .foregroundStyle(Theme.signal)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.signal.opacity(0.4), lineWidth: 1))
    }
}
