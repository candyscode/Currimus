import SwiftUI

struct ProgressScreen: View {
    @EnvironmentObject private var store: RunStore
    @Environment(\.pushRoute) private var push
    @State private var view: RunStore.LogFilter = .road   // .road or .trail

    var body: some View {
        TabScreen(topInset: 8) { EmptyView() } content: {
            VStack(alignment: .leading, spacing: 0) {
                Text("Progress").font(.sg(38, weight: .semibold)).kerning(-0.8).padding(.top, 6)

                SegmentChips(options: [(.road, "Road"), (.trail, "Trail")], selection: $view)
                    .frame(maxWidth: 180, alignment: .leading)
                    .padding(.top, 18)

                if view == .road { roadContent } else { trailContent }
            }
        }
    }

    // MARK: - Road

    private var roadContent: some View {
        let series = RunAnalytics.weeklyAvgPace(runs: store.runs, weeks: 12, roadOnly: true)
        let present = series.compactMap { $0 }
        let road12 = last12WeekRoad
        let avg = road12.km > 0 ? road12.time / road12.km : 0
        let delta = (present.first ?? 0) - (present.last ?? 0)
        return VStack(alignment: .leading, spacing: 0) {
            Text("AVG PACE · LAST 12 WEEKS").kicker(13, color: Theme.bright, tracking: 0.12).padding(.top, 24)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Format.pace(avg)).font(.stat(64)).kerning(-2.6)
                Text("/km").font(.sg(16)).foregroundStyle(Theme.bright)
                Spacer()
                Text("\(Format.paceDelta(-abs(delta))) since \(sinceMonth)")
                    .font(.stat(14)).foregroundStyle(Theme.signal)
            }
            .padding(.top, 8)
            TrendChart(values: series, topLabel: Format.pace((present.max() ?? 0) + 8),
                       bottomLabel: Format.pace((present.min() ?? 0) - 8), invert: true,
                       accessibilityTitle: "Average pace per week, last 12 weeks",
                       describe: { "\(Format.pace($0)) per kilometre" })
                .padding(.top, 18)
            monthAxis.padding(.top, 4)

            divider
            driftRow

            divider
            Text("MONTHLY KM").kicker(13, color: Theme.bright, tracking: 0.12).padding(.bottom, 14)
            MonthBars(items: store.monthlyTotals(count: 6).map { (shortMonth($0.month), $0.km) },
                      unit: "km") { "\(Int($0))" }

            recordsCard(title: "Records", value: "\(store.record(.fiveK)?.value ?? "—") 5K")
        }
    }

    private var driftRow: some View {
        let drift = RunAnalytics.hrAtPace(runs: store.runs, referencePaceSec: 330)
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Heart rate at 5:30 pace").font(.sg(16))
                Text("Same effort, less work").font(.sg(13)).foregroundStyle(Theme.muted)
            }
            Spacer()
            if let drift {
                Text("\(drift.avg) \(Text(drift.delta <= 0 ? "\(drift.delta)" : "+\(drift.delta)").font(.stat(14)).foregroundStyle(Theme.signal))")
                    .font(.stat(26))
            } else {
                Text("—").font(.stat(26)).foregroundStyle(Theme.muted)
            }
        }
    }

    // MARK: - Trail

    private var trailContent: some View {
        let climbSeries = RunAnalytics.weeklyClimbRate(runs: store.runs, weeks: 12)
        let present = climbSeries.compactMap { $0 }
        let avgRate = present.isEmpty ? 0 : present.reduce(0, +) / Double(present.count)
        let rateDelta = (present.last ?? 0) - (present.first ?? 0)
        return VStack(alignment: .leading, spacing: 0) {
            Text("CLIMB RATE · LAST 12 WEEKS").kicker(13, color: Theme.bright, tracking: 0.12).padding(.top, 24)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(Int(avgRate))").font(.stat(64)).kerning(-2.6)
                Text("m/h").font(.sg(16)).foregroundStyle(Theme.bright)
                Spacer()
                Text("\(rateDelta >= 0 ? "+" : "−")\(Int(abs(rateDelta))) since \(sinceMonth)")
                    .font(.stat(14)).foregroundStyle(Theme.signal)
            }
            .padding(.top, 8)
            TrendChart(values: climbSeries, topLabel: "\(Int((present.max() ?? 0)))",
                       bottomLabel: "\(Int((present.min() ?? 0)))", invert: false,
                       accessibilityTitle: "Climb rate per week, last 12 weeks",
                       describe: { "\(Int($0)) metres per hour" })
                .padding(.top, 18)
            monthAxis.padding(.top, 4)

            divider
            gapRow

            divider
            Text("MONTHLY CLIMB · M").kicker(13, color: Theme.bright, tracking: 0.12).padding(.bottom, 14)
            MonthBars(items: store.monthlyClimb(count: 6).map { (shortMonth($0.month), $0.climb) },
                      unit: "metres of climb") { climb in
                climb >= 1000 ? String(format: "%.1fk", climb / 1000) : "\(Int(climb))"
            }

            recordsCard(title: "Most climb", value: "\(Int(store.mostClimbRun?.climbMeters ?? 0)) m")
        }
    }

    private var gapRow: some View {
        let trail = store.filteredRuns(.trail)
        let rawPace = trail.reduce(0) { $0 + $1.paceSecPerKm } / Double(max(trail.count, 1))
        let gap = trail.reduce(0.0) { $0 + RunAnalytics.gradeAdjustedPace($1) } / Double(max(trail.count, 1))
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Grade-adjusted pace").font(.sg(16))
                Text("Climbing costs you less").font(.sg(13)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Text("\(Format.pace(gap)) \(Text(Format.paceDelta(gap - rawPace)).font(.stat(14)).foregroundStyle(Theme.signal))")
                .font(.stat(26))
        }
    }

    // MARK: - Shared

    private func recordsCard(title: String, value: String) -> some View {
        Button { push(.records) } label: {
            GlassCard(cornerRadius: 20, padding: EdgeInsets(top: 18, leading: 22, bottom: 18, trailing: 22)) {
                HStack {
                    Text(title).font(.sg(16, weight: .semibold))
                    Spacer()
                    Text(value).font(.stat(15, weight: .regular)).foregroundStyle(Theme.bright)
                    Chevron()
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 26)
    }

    private var divider: some View { Divider().overlay(Theme.hairline).padding(.vertical, 24) }

    private var monthAxis: some View {
        HStack {
            ForEach(["Apr", "May", "Jun", "Jul"], id: \.self) { m in
                Text(m).font(.sg(12)).foregroundStyle(Theme.muted)
                if m != "Jul" { Spacer() }
            }
        }
    }

    private var sinceMonth: String {
        let d = Calendar.current.date(byAdding: .month, value: -3, to: .now) ?? .now
        return d.formatted(.dateTime.month(.abbreviated))
    }

    private func shortMonth(_ date: Date) -> String { date.formatted(.dateTime.month(.abbreviated)) }

    private var last12WeekRoad: (km: Double, time: TimeInterval) {
        let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -12, to: .now) ?? .now
        let runs = store.runs.filter { !$0.isTrail && $0.date >= cutoff }
        return (runs.reduce(0) { $0 + $1.distanceKm }, runs.reduce(0) { $0 + $1.duration })
    }
}
