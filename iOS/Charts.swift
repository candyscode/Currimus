import SwiftUI
import MapKit

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

/// A trend polyline over three gridlines, with the band it is drawn into
/// written at the edges. `values` oldest→newest; nil gaps are bridged.
///
/// The axis labels are derived here rather than passed in. They used to be
/// the caller's own `min - 8` / `max + 8` while the line was normalised to
/// exactly min…max, so the curve grazed both edges of a band the labels said
/// it should not reach. One source for both is the only way they stay true to
/// each other.
struct TrendChart: View {
    var values: [TimeInterval?]
    /// Headroom above and below the data, in the values' own unit, so the
    /// line never rides the frame's edge.
    var headroom: Double = 8
    /// Whether a falling line is the improvement (pace) or a rising one
    /// (climb rate). Only affects what VoiceOver calls the direction.
    var lowerIsBetter = true
    var accessibilityTitle: String = "Trend"
    /// What one point along the x axis is. It was the word "weeks", written
    /// into the spoken summary — so the zone-2 chart, which is twelve *months*,
    /// read out "7 weeks, from … to …".
    var period: String = "weeks"
    /// An axis bound, written for the edge label.
    var format: (Double) -> String = { Format.pace($0) }
    /// One value, spoken as a phrase.
    var describe: (TimeInterval) -> String = { "\(Format.pace($0)) per kilometre" }

    /// The band the line is scaled into: the data plus its headroom.
    private var band: (low: Double, high: Double) {
        let present = values.compactMap { $0 }
        guard let low = present.min(), let high = present.max() else { return (0, 1) }
        return (low - headroom, high + headroom)
    }

    /// Oldest and newest point plus the direction between them — the shape a
    /// sighted reader takes from the line at a glance.
    private var spokenSummary: String {
        let present = values.compactMap { $0 }
        guard let first = present.first, let last = present.last else {
            return "No data yet"
        }
        let improved = lowerIsBetter ? last < first : last > first
        let direction = last == first ? "unchanged" : (improved ? "improving" : "slipping")
        return "\(present.count) \(period), from \(describe(first)) to \(describe(last)), \(direction)"
    }

    var body: some View {
        let band = band
        let span = max(band.high - band.low, 1)
        // The larger value is always the higher one on screen. The trail chart
        // used to pass `invert: false`, which drew its biggest climb week at
        // the bottom while the label at the top claimed that number.
        let pts: [CGPoint] = values.enumerated().compactMap { i, v in
            guard let v else { return nil }
            return CGPoint(x: Double(i) / Double(max(values.count - 1, 1)),
                           y: (v - band.low) / span)
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
                Text(format(band.high)).font(.stat(10, weight: .regular)).foregroundStyle(Theme.faint)
                    .position(x: 14, y: 6)
                Text(format(band.low)).font(.stat(10, weight: .regular)).foregroundStyle(Theme.faint)
                    .position(x: 14, y: proxy.size.height - 6)
            }
        }
        .frame(height: 100)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(spokenSummary)
    }
}

/// Time in each heart-rate zone, one bar per zone (Run Detail, iPhone).
///
/// The single proportional strip this replaces was honest but unreadable: it
/// showed five slices of one bar, so a zone with 6 % of the run was a sliver
/// with a number underneath it, and comparing two zones meant comparing two
/// sliver widths. Five bars off a common baseline is the same data, read at a
/// glance. The strip stays on the watch, where a stacked list would not fit.
struct ZoneBreakdown: View {
    var zoneSeconds: [TimeInterval]

    private var total: TimeInterval { zoneSeconds.reduce(0, +) }

    var body: some View {
        if total < 1 {
            // No heart rate reached the recording — say so rather than draw
            // five empty bars that look like five zones of nothing.
            Text("No heart rate was recorded for this run.")
                .font(.sg(13)).foregroundStyle(Theme.muted)
        } else {
            VStack(spacing: 12) {
                ForEach(0..<5, id: \.self) { index in row(index) }
            }
        }
    }

    private func row(_ index: Int) -> some View {
        let seconds = zoneSeconds[index]
        let share = total > 0 ? seconds / total : 0
        return HStack(spacing: 12) {
            Text("Z\(index + 1) · \(HRZones.zoneNames[index])")
                .font(.sg(12)).foregroundStyle(Theme.muted)
                // "Z4 · Threshold" is the longest of the five and fills this
                // column; it shrinks rather than truncates at larger type.
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(width: 106, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.trackIdle)
                    Capsule().fill(Theme.zoneHeat[index])
                        .frame(width: max(proxy.size.width * share, share > 0 ? 3 : 0))
                }
            }
            .frame(height: 12)
            Text(Self.duration(seconds))
                .font(.stat(13, weight: .regular))
                .foregroundStyle(seconds > 0 ? Theme.ink : Theme.faint)
                .frame(width: 52, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zone \(index + 1), \(HRZones.zoneNames[index])")
        .accessibilityValue("\(Self.duration(seconds)), \(Int((share * 100).rounded())) percent")
    }

    /// Minutes, or hours and minutes once a zone has held for an hour — a
    /// six-hour ultra spends "4h 12" in zone 2, not "252m".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        guard minutes >= 60 else { return "\(minutes)m" }
        return "\(minutes / 60)h \(String(format: "%02d", minutes % 60))"
    }
}

/// The splits, folded down to what a runner reads first — and the full list
/// one tap away.
///
/// A half marathon is 21 bars, a marathon 42; they pushed everything below
/// them off the screen and buried the three numbers people actually look for.
/// Average, fastest and slowest carry the shape of the run, and the second
/// half against the first says whether it was run evenly, which is the one
/// judgement the bar chart makes you count out by eye.
struct SplitsSummary: View {
    var splits: [TimeInterval]
    @State private var isExpanded = false

    private var average: TimeInterval { splits.reduce(0, +) / Double(splits.count) }
    private var fastest: TimeInterval { splits.min() ?? 0 }
    private var slowest: TimeInterval { splits.max() ?? 0 }

    /// How the second half ran against the first. Needs enough kilometres for
    /// the two halves to mean something; an odd middle kilometre is left out
    /// of both rather than counted twice.
    private var halves: String? {
        guard splits.count >= 6 else { return nil }
        let half = splits.count / 2
        let first = splits.prefix(half).reduce(0, +) / Double(half)
        let second = splits.suffix(half).reduce(0, +) / Double(half)
        let delta = second - first
        guard abs(delta) >= 2 else {
            return String(localized: "Held an even pace from half to half.")
        }
        let seconds = Int(abs(delta).rounded())
        return delta < 0
            ? String(localized: "Second half \(seconds) s/km faster — a negative split.")
            : String(localized: "Second half \(seconds) s/km slower.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { isExpanded.toggle() }
            } label: {
                GlassCard(cornerRadius: 20,
                          padding: EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 18)) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 18) {
                            DetailStat(value: Format.pace(average), label: "AVG /KM")
                            DetailStat(value: Format.pace(fastest), label: "FASTEST", accent: true)
                            DetailStat(value: Format.pace(slowest), label: "SLOWEST")
                            Spacer(minLength: 0)
                            Chevron()
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                                .padding(.top, 4)
                        }
                        if let halves {
                            Text(halves).font(.sg(13)).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Hides every kilometre" : "Shows every kilometre")

            if isExpanded {
                SplitBars(splits: splits)
                    .padding(.top, 20)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
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

/// The run's recorded GPS track on a real map.
///
/// This used to be grid paper with the word MAP in the corner — and when a
/// run had no track at all it drew a decorative bézier loop, so a treadmill
/// session came with an invented route through an imaginary park. A drawing
/// of a run that did not happen is worse than no drawing.
struct MapCard: View {
    var run: Run
    var height: CGFloat = 160
    @State private var isExpanded = false

    private var route: [CLLocationCoordinate2D] {
        (run.route ?? []).map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    var body: some View {
        Group {
            if route.count > 1 {
                RouteMap(route: route, region: region)
            } else {
                empty
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.cardBorder, lineWidth: 1))
        .overlay(alignment: .bottomTrailing) {
            if route.count > 1 {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 26, height: 26)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(8)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .onTapGesture { if route.count > 1 { isExpanded = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(route.count > 1 ? "Route map" : "No GPS track recorded")
        .accessibilityAddTraits(route.count > 1 ? .isButton : [])
        .fullScreenCover(isPresented: $isExpanded) {
            RouteMapFullScreen(route: route, region: region)
        }
    }

    /// Said plainly, because it has a cause the user can act on: a run records
    /// without location, it just loses the route.
    private var empty: some View {
        ZStack {
            Theme.card
            VStack(spacing: 6) {
                Image(systemName: run.isTreadmill
                      ? "figure.run.treadmill"
                      : "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.system(size: 22)).foregroundStyle(Theme.faint)
                // A treadmill run has no track because there was nothing to
                // track, which is not the same as a recording that failed.
                Text(run.isTreadmill ? "Indoor run — nowhere to draw"
                                     : "No GPS track for this run")
                    .font(.sg(13)).foregroundStyle(Theme.muted)
            }
        }
    }

    /// The track's bounding box with a margin, so the line never runs into
    /// the card's edge. The floor keeps a lap around a single block from
    /// filling the frame with one street.
    private var region: MKCoordinateRegion {
        let lats = route.map(\.latitude), lons = route.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else {
            return MKCoordinateRegion()
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                           longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.35, 0.003),
                                   longitudeDelta: max((maxLon - minLon) * 1.35, 0.003))
        )
    }
}

/// `MKMapView` rather than SwiftUI's `Map`.
///
/// The map has to be dark: everything around it is `#0A0A0A`, and a daylight
/// map in the middle of a run detail reads as a different app. SwiftUI's `Map`
/// has no way to say so — `mapColorScheme` does not exist on iOS, and MapKit
/// ignores `\.colorScheme` because it is UIKit underneath. Even the root
/// view's `preferredColorScheme(.dark)` does not reach it. `MKMapView` takes
/// the instruction directly.
private struct RouteMap: UIViewRepresentable {
    var route: [CLLocationCoordinate2D]
    var region: MKCoordinateRegion
    /// The card embedded in a scrolling detail screen locks scroll/zoom, so
    /// panning doesn't fight the page; the full-screen presentation is the
    /// one place that turns them back on.
    var interactive: Bool = false

    func makeUIView(context: Context) -> MKMapView {
        let view = MKMapView()
        view.delegate = context.coordinator
        view.overrideUserInterfaceStyle = .dark
        view.pointOfInterestFilter = .excludingAll
        view.showsCompass = false
        view.showsScale = false
        view.isRotateEnabled = false
        view.isPitchEnabled = false
        view.isScrollEnabled = interactive
        view.isZoomEnabled = interactive
        view.addOverlay(MKPolyline(coordinates: route, count: route.count))
        view.setRegion(region, animated: false)
        return view
    }

    func updateUIView(_ view: MKMapView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = UIColor(Theme.signal)
            renderer.lineWidth = 3
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }
    }
}

/// The route, expanded to fill the screen so it can be zoomed and panned —
/// tapped open from the `MapCard`, which keeps its own map locked to a
/// scroll-safe preview.
private struct RouteMapFullScreen: View {
    var route: [CLLocationCoordinate2D]
    var region: MKCoordinateRegion
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            Theme.bg.ignoresSafeArea()
            RouteMap(route: route, region: region, interactive: true)
                .ignoresSafeArea()
            TopScrim {
                HStack {
                    GlassIconButton(systemImagePath: .close) { dismiss() }
                    Spacer()
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
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
