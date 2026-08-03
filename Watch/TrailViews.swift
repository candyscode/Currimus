import SwiftUI

/// Trail run: the glance plus climb, swipe left for the elevation page.
struct TrailRunPager: View {
    @ObservedObject var session: RunSession
    @Environment(\.isLuminanceReduced) private var systemDimmed
    @Environment(\.alwaysOnReduced) private var reducedEnabled

    private var dimmed: Bool { (systemDimmed || AlwaysOn.forcedForDebug) && reducedEnabled }
    private var palette: RunPalette { RunPalette(dimmed: dimmed) }
    @State private var page = (DebugFlags.screen ?? "").hasPrefix("elevation") ? 1 : 0

    var body: some View {
        // Hand-rolled pager instead of TabView: TabView reserves ~20pt at the
        // bottom even with the index hidden, which pushed the zone bar out of
        // line with the plain run screen. A plain HStack + drag keeps both
        // modes layout-identical.
        GeometryReader { proxy in
            HStack(spacing: 0) {
                trailGlance
                    .frame(width: proxy.size.width, height: proxy.size.height)
                TrailElevationView(session: session)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .offset(x: page == 0 ? 0 : -proxy.size.width)
            .animation(.snappy(duration: 0.3), value: page)
        }
        // Clip only horizontally (hide the neighbouring page); leave vertical
        // overflow so the hero pulled up under the caption isn't cut off.
        .mask { Rectangle().padding(.vertical, -120) }
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 15)
                .onEnded { value in
                    if value.translation.width < -25 {
                        page = 1
                    } else if value.translation.width > 25 {
                        page = 0
                    }
                }
        )
        .onTapGesture { session.pause() }
        .overlay {
            if let alert = session.kilometerAlert {
                KilometerAlertView(alert: alert).transition(.opacity)
            } else if let warning = session.zoneWarning {
                ZoneWarningView(warning: warning).transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.kilometerAlert)
        .animation(.easeInOut(duration: 0.25), value: session.zoneWarning)
        // One caption for the pager, driven by the visible page. Hidden while
        // an alert owns the canvas.
        .topBarCaption {
            if session.kilometerAlert == nil, session.zoneWarning == nil {
                TopBarCaption(text: page == 0 ? "TRAIL" : "ELEVATION", color: palette.label,
                              mark: true, markColor: palette.signal)
            }
        }
    }

    private var trailGlance: some View {
        RunTimeline(session: session) { elapsed in
            trailGlanceBody(elapsed: elapsed)
        }
    }

    private func trailGlanceBody(elapsed: TimeInterval) -> some View {
        RunScaffold {
            VStack(alignment: .leading, spacing: 0) {
                // Same 52 pt hero box as Run/Pacer (shrinks to fit long trail
                // times), so the value sits at an identical height on all three.
                Text(Format.clock(elapsed))
                    .font(.stat(52))
                    .kerning(-2.3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(palette.hero)
                    .contentTransition(dimmed ? .identity : .numericText())
                    .animation(dimmed ? nil : .linear(duration: 0.25), value: elapsed)

                // The design's 1fr 1fr grid (gap 20 px 36 px, 22 px below the
                // hero) — grouped under the timer so the free space pools
                // above the zone bar.
                Grid(alignment: .topLeading, horizontalSpacing: 18,
                     verticalSpacing: LineBox.gap(10, cropping: 17)) {
                    GridRow {
                        BigStat(value: Format.km(session.distanceKm), label: "KM",
                                valueColor: palette.value,
                                size: 17, labelGap: 2.5, labelOutsideLayout: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        BigStat(value: Format.pace(session.rollingPace), label: "PACE /KM",
                                valueColor: palette.value,
                                size: 17, labelGap: 2.5, labelOutsideLayout: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GridRow {
                        // No triangle here either, and for the same reason as
                        // on the elevation page: "M CLIMBED" underneath says
                        // which way it goes, and the mark cost a fifth of the
                        // column that a four-digit Alpine day needs (CUR-41).
                        BigStat(value: Format.elevation(session.climbMeters, unit: false),
                                label: "M CLIMBED", valueColor: palette.value,
                                size: 17, labelGap: 2.5, labelOutsideLayout: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        BigStat(
                            value: "\(Int(session.climbRatePerHour))",
                            label: "M/H · LAST MIN",
                            valueColor: dimmed ? palette.hero : Theme.signal,
                            size: 17, labelGap: 2.5, labelOutsideLayout: true
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                // The design draws Trail's hero at 38 pt; ours stays 52 (same
                // box as Run — the user's call). Preserve the *drawn* ink gap:
                // the 11 pt margin plus the design box's slack under a 38 pt
                // line, minus our 52 pt descender room and the 17 pt cap crop.
                .padding(.top, 11 + (LineBox.descent - LineBox.crop) * 38
                              - LineBox.descent * 52 - LineBox.crop * 17)
            }
        } footer: {
            ZoneFooter(zone: session.currentZone,
                       position: session.zones.position(forHR: session.heartRate))
        }
    }
}

/// An elevation profile with a two-value Y axis: the lowest and highest
/// elevation reached (or on the route), as dashed hairlines on the curve's
/// extremes with the values in a left gutter. No axis line, no ticks, no X
/// axis — the profile itself is the scale. (Design: "Watch Elevation Y-Axis
/// Exploration"; px values halved to watch points.)
struct ElevationChart: View {
    /// Normalized profile (x 0…1 left→right, y 0…1 bottom→top).
    var points: [CGPoint]
    var lowMeters: Double
    var highMeters: Double
    var showsDot = true
    var lineWidth: CGFloat = 1.5
    var labelSize: CGFloat = 7
    /// Hairline positions, measured from the chart's edges (design: 14 / 10 px
    /// of 150 on the trail page, 10 / 8 px of 62 on the summary). They are
    /// fixed, so the two labels always sit the same distance apart however
    /// flat the run was — the profile is scaled into the band between them.
    var topInset: CGFloat = 7
    var bottomInset: CGFloat = 5

    /// The design starts the plot at x = 64 of 308 to clear the labels.
    private let gutter = 64.0 / 308.0
    @Environment(\.runPalette) private var palette

    var body: some View {
        GeometryReader { proxy in
            let plotX = proxy.size.width * gutter
            let plotW = proxy.size.width - plotX
            let topY = topInset
            let bottomY = proxy.size.height - bottomInset
            let low = points.map(\.y).min() ?? 0
            let high = points.map(\.y).max() ?? 0
            let band = (low: low, high: high, top: topY, bottom: bottomY)
            let progressMapped = mapped(points, plotX: plotX, plotW: plotW, band: band)

            ZStack(alignment: .topLeading) {
                Path { p in
                    p.move(to: .init(x: plotX, y: topY))
                    p.addLine(to: .init(x: proxy.size.width, y: topY))
                    p.move(to: .init(x: plotX, y: bottomY))
                    p.addLine(to: .init(x: proxy.size.width, y: bottomY))
                }
                .stroke(palette.dimmed ? Color(hex: 0x1C1C1C) : Color(hex: 0x242424),
                        style: .init(lineWidth: 0.75, dash: [1.5, 3]))

                if progressMapped.count > 1 {
                    line(progressMapped).stroke(
                        palette.signal, style: .init(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                }
                if showsDot, let last = progressMapped.last {
                    // Parks with the wrist down: at 1 Hz it would only nudge
                    // once a second anyway, so it reads as still either way.
                    Circle().fill(palette.secondary)
                        .frame(width: 7, height: 7).position(last)
                }

                label(Format.elevation(highMeters), color: palette.dimmed ? Color(hex: 0x5A5A5A) : Theme.bright)
                    .frame(width: plotX, alignment: .leading).position(x: plotX / 2, y: topY)
                label(Format.elevation(lowMeters), color: palette.dimmed ? Color(hex: 0x454545) : Theme.muted)
                    .frame(width: plotX, alignment: .leading).position(x: plotX / 2, y: bottomY)
            }
        }
    }

    /// Scales the profile so its lowest point lands on the bottom hairline and
    /// its highest on the top one. A dead-flat run has no span to scale into —
    /// the line then rides the middle of the band and both labels read the
    /// same elevation, so the chart never changes shape or size.
    private func mapped(_ pts: [CGPoint], plotX: CGFloat, plotW: CGFloat,
                        band: (low: CGFloat, high: CGFloat, top: CGFloat, bottom: CGFloat)) -> [CGPoint] {
        let span = band.high - band.low
        return pts.map { point in
            let t = span > 0.0001 ? (point.y - band.low) / span : 0.5
            return CGPoint(x: plotX + point.x * plotW,
                           y: band.bottom - t * (band.bottom - band.top))
        }
    }

    private func line(_ pts: [CGPoint]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        pts.dropFirst().forEach { path.addLine(to: $0) }
        return path
    }

    private func label(_ text: String, color: Color) -> some View {
        Text(text).font(.stat(labelSize, weight: .regular)).foregroundStyle(color).lineLimit(1)
    }
}

/// Where am I on the mountain. With a planned route: the dot is you, gray is
/// what's left. Without one: the profile you have run so far, growing right.
struct TrailElevationView: View {
    @ObservedObject var session: RunSession
    @Environment(\.isLuminanceReduced) private var systemDimmed
    @Environment(\.alwaysOnReduced) private var reducedEnabled

    private var dimmed: Bool { (systemDimmed || AlwaysOn.forcedForDebug) && reducedEnabled }
    private var palette: RunPalette { RunPalette(dimmed: dimmed) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            chart
                .frame(height: 75)   // design 150 px

            Spacer(minLength: 14)

            // Where the design had M TO TOP (a route-relative goal) the live
            // altitude now sits — it takes the Signal because on this page it
            // is the number you came for; climbed and down are the ledger.
            // No triangles on this row. They cost a fifth of each column's
            // width, and an Alpine day spends most of itself in four digits —
            // "▲ 11…" is what a 1 157 m climb read as (Andi, CUR-41). The word
            // underneath already says which way the number goes, which the
            // triangle only ever repeated.
            HStack(alignment: .top, spacing: 12) {
                // All three through the same formatter, so a row of three
                // four-digit numbers is not written two different ways — the
                // altimeter had a thousands separator and the two beside it did
                // not.
                elevationStat(Format.elevation(session.climbMeters, unit: false), "CLIMBED",
                              color: palette.value)
                elevationStat(Format.elevation(session.altitudeMeters, unit: false), "ELEVATION",
                              color: dimmed ? palette.hero : Theme.signal)
                elevationStat(Format.elevation(session.descentMeters, unit: false), "DOWN",
                              color: palette.hero)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(EdgeInsets(top: 8, leading: 20, bottom: 16, trailing: 20))
        // The chart reads its colours from the ambient palette, and this page
        // sits outside the run scaffold — so it publishes its own.
        .environment(\.runPalette, palette)
    }

    /// One of the three columns under the profile.
    ///
    /// Equal widths, so three four-digit numbers divide the row rather than
    /// pushing each other off it, and a scale factor as the last resort for a
    /// narrow case — the 40 mm one has 86 px less to give than the Ultra.
    private func elevationStat(_ value: String, _ label: LocalizedStringKey,
                               color: Color) -> some View {
        VStack(alignment: .leading, spacing: LineBox.gap(2.5, cropping: 15)) {
            Text(value)
                .font(.stat(15))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            // 0.6, not 0.8: three equal columns on a 40 mm case leave about
            // 33 pt each, and "CLIMBED" at 8 pt with this tracking wants 38.
            // Scaling is invisible on the Ultra, where nothing has to shrink.
            Text(label).kicker(8, color: palette.label, tracking: 0.1)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The axis is live: it follows what you have actually run.
    private var chart: some View {
        let samples = session.altitudeProfile
        return ElevationChart(
            points: RoutePoints.normalized(samples),
            lowMeters: samples.min() ?? 0,
            highMeters: samples.max() ?? 0
        )
    }
}

