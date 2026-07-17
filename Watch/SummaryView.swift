import SwiftUI

/// Run complete — crown scrolls down to Done → Home. Saved to the iPhone log.
struct SummaryView: View {
    var run: Run
    var onDone: () -> Void

    var body: some View {
        SummaryScroller(onDone: onDone) {
            VStack(alignment: .leading, spacing: 0) {
                Text("RUN COMPLETE").kicker(8, color: Theme.bright, tracking: 0.1)
                    .padding(.top, 8)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(Format.km(run.distanceKm))
                        .font(.stat(32))
                        .kerning(-1.3)
                    Text("km").font(.sg(12)).foregroundStyle(Theme.muted)
                }
                .padding(.top, 5)

                HStack(alignment: .top, spacing: 14) {
                    BigStat(value: Format.clock(run.duration), label: "TIME", size: 13)
                    BigStat(value: Format.pace(run.paceSecPerKm), label: "PACE", valueColor: Theme.signal, size: 13)
                    BigStat(value: "\(run.avgHR)", label: "AVG HR", size: 13)
                }
                .padding(.top, 13)

                Spacer(minLength: 0)

                ZoneHeatStrip(zoneSeconds: run.zoneSeconds, height: 7)
                HStack {
                    Text("TIME IN ZONES").kicker(8, color: Theme.bright, tracking: 0.1)
                    Spacer()
                    Text("mostly \(run.dominantZone)")
                        .font(.stat(7, weight: .regular))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.top, 4)
            }
        }
    }
}

/// Trail complete — vert gets equal billing; Done → Home below the fold.
struct TrailSummaryView: View {
    var run: Run
    /// Elevation profile of the run (planned route or recorded).
    var profile: [CGPoint]
    var onDone: () -> Void

    var body: some View {
        SummaryScroller(onDone: onDone) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    TriangleMark().fill(Theme.signal).frame(width: 8, height: 7)
                    Text("TRAIL COMPLETE").kicker(8, color: Theme.bright, tracking: 0.1)
                }
                .padding(.top, 8)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(Format.km(run.distanceKm, decimals: 1))
                            .font(.stat(23))
                            .kerning(-0.9)
                        Text("km").font(.sg(11)).foregroundStyle(Theme.muted)
                    }
                    ClimbStat(value: "\(Int(run.climbMeters ?? 0))", size: 23, color: Theme.signal)
                }
                .padding(.top, 5)

                HStack(alignment: .top, spacing: 14) {
                    BigStat(value: Format.clock(run.duration), label: "TIME", size: 13)
                    BigStat(value: Format.pace(run.paceSecPerKm), label: "PACE", size: 13)
                    BigStat(
                        value: "\(Int((run.climbMeters ?? 0) / max(run.duration / 3600, 0.01)))",
                        label: "AVG M/H", size: 13
                    )
                }
                .padding(.top, 13)

                Spacer(minLength: 0)

                LineChart(points: profile)
                    .stroke(Theme.signal, style: .init(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
                    .frame(height: 27)
                HStack {
                    Text("PROFILE").kicker(8, color: Theme.bright, tracking: 0.1)
                    Spacer()
                    Text("high \(Int(run.highPointMeters ?? 0)) m")
                        .font(.stat(7, weight: .regular))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.top, 4)
            }
        }
    }
}

/// One full-height summary page with the Done button below the fold —
/// the crown (or a swipe) scrolls down to it.
struct SummaryScroller<Content: View>: View {
    var onDone: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    content
                        .frame(height: proxy.size.height - 25)
                        .padding(EdgeInsets(top: 2, leading: 22, bottom: 0, trailing: 22))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: onDone) {
                        Text("Done")
                            .font(.sg(9.5, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 31, maxHeight: 31)
                            .background(Theme.button, in: Capsule())
                            .overlay(Capsule().stroke(Theme.buttonBorder, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 22)
                }
            }
        }
    }
}
