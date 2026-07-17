import SwiftUI

/// Run complete — saved to the iPhone log. Trail gives vert equal billing.
struct SummaryView: View {
    var run: Run
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(run.type == .trail ? "▲ TRAIL COMPLETE" : "RUN COMPLETE").kicker(9)

            if run.type == .trail {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    StatInline(value: Format.km(run.distanceKm, decimals: 1), unit: "km", size: 26)
                    Text("▲ \(Int(run.climbMeters ?? 0))")
                        .font(.stat(26))
                        .foregroundStyle(Theme.signal)
                }
                .padding(.top, 6)
            } else {
                StatInline(value: Format.km(run.distanceKm), unit: "km", size: 30)
                    .padding(.top, 6)
            }

            HStack(alignment: .top, spacing: 14) {
                BigStat(value: Format.clock(run.duration), label: "TIME", size: 14)
                BigStat(value: Format.pace(run.paceSecPerKm), label: "PACE", valueColor: Theme.signal, size: 14)
                if run.type == .trail {
                    BigStat(
                        value: "\(Int((run.climbMeters ?? 0) / max(run.duration / 3600, 0.01)))",
                        label: "AVG M/H", size: 14
                    )
                } else {
                    BigStat(value: "\(run.avgHR)", label: "AVG HR", size: 14)
                }
            }
            .padding(.top, 12)

            Spacer(minLength: 0)

            if run.type == .trail {
                LineChart(points: TrailProfile.route)
                    .stroke(Theme.signal, style: .init(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .frame(height: 26)
                HStack {
                    Text("PROFILE").kicker(7)
                    Spacer()
                    Text("high \(Int(run.highPointMeters ?? 0)) m")
                        .font(.stat(8, weight: .regular))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.top, 4)
            } else {
                ZoneHeatStrip(zoneSeconds: run.zoneSeconds)
                HStack {
                    Text("TIME IN ZONES").kicker(7)
                    Spacer()
                    Text("mostly \(run.dominantZone)")
                        .font(.stat(8, weight: .regular))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.top, 4)
            }

            Button(action: onDone) {
                Text("Done")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(Theme.button, in: Capsule())
                    .overlay(Capsule().stroke(Theme.buttonBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
        .padding(.horizontal, 4)
    }
}
