import SwiftUI

/// Run complete — crown scrolls down to Done → Home. Saved to the iPhone log.
struct SummaryView: View {
    var run: Run
    var onDone: () -> Void

    var body: some View {
        SummaryScroller(onDone: onDone, caption: TopBarCaption(text: "RUN COMPLETE")) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(Format.km(run.distanceKm))
                        .font(.stat(32))
                        .kerning(-1.3)
                    Text("km").font(.sg(12)).foregroundStyle(Theme.muted)
                }

                StatRow {
                    BigStat(value: Format.clock(run.duration), label: "TIME", size: 13)
                    BigStat(value: Format.pace(run.paceSecPerKm), label: "PACE", valueColor: Theme.signal, size: 13)
                    BigStat(value: run.avgHR > 0 ? "\(run.avgHR)" : "–", label: "AVG HR", size: 13)
                }
                .padding(.top, 13)

                ZoneHeatStrip(zoneSeconds: run.zoneSeconds, height: 7)
                    .padding(.top, 18)
                HStack {
                    Text("TIME IN ZONES").kicker(8, color: Theme.bright, tracking: 0.1)
                    Spacer()
                    Text(run.dominantZone > 0 ? "mostly \(run.dominantZone)" : "–")
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
        SummaryScroller(onDone: onDone, caption: TopBarCaption(text: "TRAIL COMPLETE", mark: true)) {
            VStack(alignment: .leading, spacing: 0) {
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

                StatRow {
                    BigStat(value: Format.clock(run.duration), label: "TIME", size: 13)
                    BigStat(value: Format.pace(run.paceSecPerKm), label: "PACE", size: 13)
                    BigStat(
                        value: "\(Int((run.climbMeters ?? 0) / max(run.duration / 3600, 0.01)))",
                        label: "AVG M/H", size: 13
                    )
                }
                .padding(.top, 13)

                LineChart(points: profile)
                    .stroke(Theme.signal, style: .init(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
                    .frame(height: 27)
                    .padding(.top, 18)
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

/// Summary page — content flows naturally, Done follows right after
/// (crown scrolls when it doesn't fit). The caption rides the top bar.
struct SummaryScroller<Content: View>: View {
    var onDone: () -> Void
    var caption: TopBarCaption
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content

                Button(action: onDone) {
                    Text("Done")
                        .font(.sg(13, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
                        .background(Theme.button, in: Capsule())
                        .overlay(Capsule().stroke(Theme.buttonBorder, lineWidth: 0.75))
                }
                .buttonStyle(.plain)
                .padding(.top, 18)
            }
            .padding(EdgeInsets(top: 6, leading: 20, bottom: 16, trailing: 20))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .topBarCaption { caption }
    }
}
