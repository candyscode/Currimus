import SwiftUI

/// Weekday volume bars (Home). Rest days are a thin idle stub; the latest run
/// day burns Signal.
struct WeekBars: View {
    var kmPerDay: [Double]
    private let labels = ["M", "T", "W", "T", "F", "S", "S"]
    private var latest: Int? { kmPerDay.lastIndex { $0 > 0 } }

    /// Monday-first weekday names for VoiceOver — the visible labels are
    /// single letters, which read as nonsense out loud.
    private var spokenSummary: String {
        let symbols = Calendar.current.weekdaySymbols
        let mondayFirst = Array(symbols[1...]) + [symbols[0]]
        let days = zip(mondayFirst, kmPerDay).map { name, km in
            km > 0 ? "\(name) \(Format.km(km, decimals: 1)) km" : "\(name) rest"
        }
        return days.joined(separator: ", ")
    }

    var body: some View {
        let maxKm = max(kmPerDay.max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(0..<7, id: \.self) { day in
                let ran = kmPerDay[day] > 0
                let isLatest = day == latest
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isLatest ? Theme.signal : (ran ? Theme.track : Theme.trackIdle))
                        .frame(height: ran ? max(kmPerDay[day] / maxKm * 78, 8) : 5)
                    Text(labels[day])
                        .font(.sg(12, weight: isLatest ? .semibold : .regular))
                        .foregroundStyle(isLatest ? Theme.ink : Theme.muted)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 96)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kilometres per day this week")
        .accessibilityValue(spokenSummary)
    }
}

/// Labelled monthly bars (Progress · km or climb). Current month burns Signal.
struct MonthBars: View {
    var items: [(label: String, value: Double)]
    /// What the numbers are, for VoiceOver ("kilometres", "metres of climb").
    /// Declared before `format` so the formatter stays a trailing closure.
    var unit: String = ""
    var format: (Double) -> String

    var body: some View {
        let maxV = max(items.map(\.value).max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let current = index == items.count - 1
                VStack(spacing: 7) {
                    Text(format(item.value))
                        .font(.stat(12, weight: current ? .semibold : .regular))
                        .foregroundStyle(current ? Theme.signal : Theme.muted)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(current ? Theme.signal : Theme.track)
                        .frame(height: max(item.value / maxV * 70, 4))
                    Text(item.label)
                        .font(.sg(12, weight: current ? .semibold : .regular))
                        .foregroundStyle(current ? Theme.ink : Theme.muted)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 96, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Monthly totals")
        .accessibilityValue(items.map { "\($0.label) \(format($0.value)) \(unit)" }
            .joined(separator: ", "))
    }
}

/// Race-readiness weekly bars (4 weeks, no y-labels).
struct WeekVolumeBars: View {
    var items: [(label: String, km: Double)]

    var body: some View {
        let maxV = max(items.map(\.km).max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let current = index == items.count - 1
                VStack(spacing: 7) {
                    Text("\(Int(item.km))")
                        .font(.stat(12, weight: current ? .semibold : .regular))
                        .foregroundStyle(current ? Theme.signal : Theme.muted)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(current ? Theme.signal : Theme.track)
                        .frame(height: max(item.km / maxV * 86, 6))
                    Text(item.label)
                        .font(.sg(12, weight: current ? .semibold : .regular))
                        .foregroundStyle(current ? Theme.ink : Theme.muted)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 110, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weekly volume, last four weeks")
        .accessibilityValue(items.map { "\($0.label) \(Int($0.km)) km" }.joined(separator: ", "))
    }
}

/// A trend polyline over three gridlines with top/bottom value labels and an
/// end dot. `values` oldest→newest; nil gaps are bridged.
struct TrendChart: View {
    var values: [TimeInterval?]
    var topLabel: String
    var bottomLabel: String
    /// When true, lower value = higher on screen (pace: faster is better).
    var invert: Bool = true
    /// What the line is, and how to say one of its values, for VoiceOver.
    var accessibilityTitle: String = "Trend"
    var describe: (TimeInterval) -> String = { Format.pace($0) }

    /// Oldest and newest point plus the direction between them — the shape a
    /// sighted reader takes from the line at a glance.
    private var spokenSummary: String {
        let present = values.compactMap { $0 }
        guard let first = present.first, let last = present.last else {
            return "No data yet"
        }
        let direction = last == first ? "unchanged" : (last < first ? "improving" : "slipping")
        return "\(present.count) weeks, from \(describe(first)) to \(describe(last)), \(direction)"
    }

    var body: some View {
        let present = values.compactMap { $0 }
        let hi = (present.max() ?? 1)
        let lo = (present.min() ?? 0)
        let span = max(hi - lo, 1)
        let pts: [CGPoint] = values.enumerated().compactMap { i, v in
            guard let v else { return nil }
            let x = Double(i) / Double(max(values.count - 1, 1))
            let norm = (v - lo) / span            // 0 = lo, 1 = hi
            let y = invert ? norm : 1 - norm       // pace: hi(slow) drawn low
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
                .stroke(Theme.signal, style: .init(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                if let last = mapped.last {
                    Circle().fill(Theme.signal).frame(width: 9, height: 9)
                        .position(last)
                }
                Text(topLabel).font(.stat(10, weight: .regular)).foregroundStyle(Theme.faint)
                    .position(x: 14, y: 6)
                Text(bottomLabel).font(.stat(10, weight: .regular)).foregroundStyle(Theme.faint)
                    .position(x: 14, y: proxy.size.height - 6)
            }
        }
        .frame(height: 100)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(spokenSummary)
    }
}

/// Per-km split bars (Run Detail). Fastest km burns Signal.
struct SplitBars: View {
    var splits: [TimeInterval]

    var body: some View {
        let slowest = splits.max() ?? 1
        let fastest = splits.min() ?? 0
        VStack(spacing: 10) {
            ForEach(Array(splits.enumerated()), id: \.offset) { index, split in
                let isFastest = split == fastest && splits.count > 1
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.stat(12, weight: .regular))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 18, alignment: .leading)
                    GeometryReader { proxy in
                        let spread = max(slowest - fastest, 1)
                        let frac = 0.5 + 0.5 * (split - fastest) / spread
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isFastest ? Theme.signal : Theme.track)
                            .frame(width: proxy.size.width * frac)
                    }
                    .frame(height: 14)
                    Text(Format.pace(split))
                        .font(.stat(14, weight: .regular))
                        .foregroundStyle(isFastest ? Theme.signal : Theme.ink)
                }
                // One element per kilometre: swiping through the splits is
                // how this chart is read, so keep the rows navigable.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Kilometre \(index + 1)")
                .accessibilityValue(isFastest
                    ? "\(Format.pace(split)) per kilometre, fastest"
                    : "\(Format.pace(split)) per kilometre")
            }
        }
    }
}

/// Route map placeholder — grid paper with the run's path.
struct MapCard: View {
    var run: Run
    var height: CGFloat = 160

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            GridPattern().stroke(Color(hex: 0x1A1A1A), lineWidth: 1)
            RoutePath(run: run)
                .stroke(Theme.signal, style: .init(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .padding(20)
            Text("MAP")
                .font(.sg(10, weight: .medium)).kerning(1)
                .foregroundStyle(Color(hex: 0x4A4A4A))
                .padding([.bottom, .trailing], 14)
        }
        .frame(height: height)
        .background(Color(hex: 0x111111))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.cardBorder, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(run.route?.isEmpty == false ? "Route map" : "Route map, no GPS track recorded")
    }
}

struct GridPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path(); let step: CGFloat = 34
        var x = rect.minX
        while x <= rect.maxX { p.move(to: .init(x: x, y: rect.minY)); p.addLine(to: .init(x: x, y: rect.maxY)); x += step }
        var y = rect.minY
        while y <= rect.maxY { p.move(to: .init(x: rect.minX, y: y)); p.addLine(to: .init(x: rect.maxX, y: y)); y += step }
        return p
    }
}

/// The recorded GPS track normalized into the card, or a pleasant default loop.
struct RoutePath: Shape {
    var run: Run

    func path(in rect: CGRect) -> Path {
        var p = Path()
        if let route = run.route, route.count > 2 {
            let lats = route.map(\.lat), lons = route.map(\.lon)
            let minLat = lats.min()!, maxLat = lats.max()!, minLon = lons.min()!, maxLon = lons.max()!
            let spanLat = max(maxLat - minLat, 1e-5), spanLon = max(maxLon - minLon, 1e-5)
            let mapped = route.map { c in
                CGPoint(x: (c.lon - minLon) / spanLon * rect.width,
                        y: (1 - (c.lat - minLat) / spanLat) * rect.height)
            }
            p.move(to: mapped[0]); mapped.dropFirst().forEach { p.addLine(to: $0) }
        } else {
            let w = rect.width, h = rect.height
            p.move(to: .init(x: 0.06 * w, y: 0.78 * h))
            p.addCurve(to: .init(x: 0.30 * w, y: 0.34 * h),
                       control1: .init(x: 0.16 * w, y: 0.62 * h), control2: .init(x: 0.16 * w, y: 0.38 * h))
            p.addCurve(to: .init(x: 0.58 * w, y: 0.56 * h),
                       control1: .init(x: 0.44 * w, y: 0.30 * h), control2: .init(x: 0.46 * w, y: 0.58 * h))
            p.addCurve(to: .init(x: 0.84 * w, y: 0.22 * h),
                       control1: .init(x: 0.70 * w, y: 0.54 * h), control2: .init(x: 0.72 * w, y: 0.24 * h))
            p.addCurve(to: .init(x: 0.95 * w, y: 0.40 * h),
                       control1: .init(x: 0.90 * w, y: 0.21 * h), control2: .init(x: 0.95 * w, y: 0.30 * h))
        }
        return p
    }
}

/// Elevation profile (Trail Detail) from altitude samples.
struct ElevationProfile: View {
    var samples: [Double]
    var height: CGFloat = 120

    var body: some View {
        let pts = RoutePoints.normalized(samples)
        return ZStack {
            LineChart(points: pts.map { CGPoint(x: $0.x, y: $0.y) })
                .stroke(Theme.signal, style: .init(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Elevation profile")
        .accessibilityValue(spokenSummary)
    }

    private var spokenSummary: String {
        guard let low = samples.min(), let high = samples.max(), samples.count > 1 else {
            return "No elevation recorded"
        }
        return "From \(Format.elevation(samples[0])) to \(Format.elevation(samples[samples.count - 1])), "
            + "low \(Format.elevation(low)), high \(Format.elevation(high))"
    }
}
