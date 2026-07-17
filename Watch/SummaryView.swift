import SwiftUI

/// Run complete — saved to the iPhone log. Trail gives vert equal billing.
/// Tap anywhere to return home.
struct SummaryView: View {
    var run: Run
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if run.type == .trail {
                HStack(spacing: 5) {
                    TriangleMark().fill(Theme.signal).frame(width: 8, height: 7)
                    Text("TRAIL COMPLETE").kicker(8.5)
                }
            } else {
                Text("RUN COMPLETE").kicker(8.5)
            }

            if run.type == .trail {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(Format.km(run.distanceKm, decimals: 1))
                            .font(.stat(28))
                            .kerning(-1.1)
                        Text("km").font(.sg(11)).foregroundStyle(Theme.muted)
                    }
                    ClimbStat(value: "\(Int(run.climbMeters ?? 0))", size: 28, color: Theme.signal)
                }
                .padding(.top, 7)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(Format.km(run.distanceKm))
                        .font(.stat(32))
                        .kerning(-1.3)
                    Text("km").font(.sg(12)).foregroundStyle(Theme.muted)
                }
                .padding(.top, 7)
            }

            HStack(alignment: .top, spacing: 14) {
                BigStat(value: Format.clock(run.duration), label: "TIME", size: 13, labelSize: 6.5)
                BigStat(value: Format.pace(run.paceSecPerKm), label: "PACE", valueColor: Theme.signal, size: 13, labelSize: 6.5)
                if run.type == .trail {
                    BigStat(
                        value: "\(Int((run.climbMeters ?? 0) / max(run.duration / 3600, 0.01)))",
                        label: "AVG M/H", size: 13, labelSize: 6.5
                    )
                } else {
                    BigStat(value: "\(run.avgHR)", label: "AVG HR", size: 13, labelSize: 6.5)
                }
            }
            .padding(.top, 13)

            Spacer(minLength: 0)

            if run.type == .trail {
                LineChart(points: TrailProfile.route)
                    .stroke(Theme.signal, style: .init(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
                    .frame(height: 27)
                HStack {
                    Text("PROFILE").kicker(7, tracking: 0.12)
                    Spacer()
                    Text("high \(Int(run.highPointMeters ?? 0)) m")
                        .font(.stat(7, weight: .regular))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.top, 4)
            } else {
                ZoneHeatStrip(zoneSeconds: run.zoneSeconds, height: 7)
                HStack {
                    Text("TIME IN ZONES").kicker(7, tracking: 0.12)
                    Spacer()
                    Text("mostly \(run.dominantZone)")
                        .font(.stat(7, weight: .regular))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.top, 4)
            }
        }
        .padding(EdgeInsets(top: 2, leading: 22, bottom: 23, trailing: 22))
        .contentShape(Rectangle())
        .onTapGesture(perform: onDone)
    }
}
