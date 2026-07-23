import SwiftUI

// The 10-foot components. They speak the same design language as the iPhone
// (Theme colours, Space Grotesk via `.sg`/`.stat`, the single signal accent)
// but are sized for a television seen across a room: taller bars, larger type,
// generous spacing. The iOS chart shapes in `iOS/Charts.swift` are tuned to
// iPhone point sizes and belong to the iOS target, so the TV carries its own.

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
    }
}

/// Labelled monthly bars (km or climb). Current month burns Signal — matches
/// the iPhone's `MonthBars`.
struct TVMonthBars: View {
    var items: [(label: String, value: Double)]
    var height: CGFloat = 200
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
    }
}

// MARK: - Route & elevation

/// Grid-paper card with the run's GPS path, the TV twin of `MapCard`. Draws the
/// recorded route normalized into the card, or a pleasant default loop when a
/// run has no track.
struct TVRouteCard: View {
    var run: Run
    var height: CGFloat = 460

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TVGridPattern().stroke(Color(hex: 0x1A1A1A), lineWidth: 1)
            TVRoutePath(route: run.route)
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
    }
}

struct TVGridPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path(); let step: CGFloat = 60
        var x = rect.minX
        while x <= rect.maxX { p.move(to: .init(x: x, y: rect.minY)); p.addLine(to: .init(x: x, y: rect.maxY)); x += step }
        var y = rect.minY
        while y <= rect.maxY { p.move(to: .init(x: rect.minX, y: y)); p.addLine(to: .init(x: rect.maxX, y: y)); y += step }
        return p
    }
}

/// The recorded GPS track normalized into the card, or a default loop. Mirrors
/// the iPhone's `RoutePath` normalisation so a route reads the same on both.
struct TVRoutePath: Shape {
    var route: [Coordinate]?

    func path(in rect: CGRect) -> Path {
        var p = Path()
        if let route, route.count > 2 {
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
        }
        return p
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
