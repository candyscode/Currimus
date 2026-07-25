import SwiftUI

/// Progress and records on one screen. The iPhone splits these across a tab and
/// a pushed screen; the TV has the room to show the pace trend, monthly volume
/// and the full record table together. Everything reads from the store's
/// aggregates — `weeklyAvgPace`, `monthlyTotals`, `records`, `latestBenchmark` —
/// so the numbers match the phone exactly.
struct TVProgressView: View {
    @EnvironmentObject private var store: RunStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 56) {
                Text("Progress").font(.sg(56, weight: .semibold)).kerning(-1)

                HStack(alignment: .top, spacing: 60) {
                    pacePanel.frame(maxWidth: .infinity, alignment: .leading)
                        .scrollFocusable()
                    recordsPanel.frame(width: 640)
                        .scrollFocusable()
                }

                monthlyPanel.scrollFocusable()
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 60)
        }
    }

    // MARK: - Pace trend

    private var pacePanel: some View {
        let series = RunAnalytics.weeklyAvgPace(runs: store.allRuns, weeks: 12, roadOnly: true)
        let present = series.compactMap { $0 }
        let road12 = last12WeekRoad
        let avg = road12.km > 0 ? road12.time / road12.km : 0
        // Newest minus oldest, so a negative number means faster — the same
        // signed reading the iPhone shows. It used to be `-abs(delta)`, which
        // claimed an improvement whichever way the runner had actually gone.
        let change = (present.last ?? 0) - (present.first ?? 0)
        return VStack(alignment: .leading, spacing: 0) {
            TVSectionLabel(text: "AVG PACE · LAST 12 WEEKS")
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(Format.pace(avg)).font(.stat(88)).kerning(-3)
                Text("/km").font(.sg(26)).foregroundStyle(Theme.bright)
                Spacer()
                if present.count >= 2 {
                    // Signal marks an improvement and nothing else; a slower
                    // twelve weeks is stated plainly rather than dressed in the
                    // accent. Same rule as the iPhone's `trendDelta`.
                    Text("\(Format.paceDelta(change)) since \(windowStartMonth)")
                        .font(.stat(20))
                        .foregroundStyle(change <= 0 ? Theme.signal : Theme.bright)
                }
            }
            .padding(.top, 10)
            TVTrendChart(values: series,
                         topLabel: Format.pace((present.max() ?? 0) + 8),
                         bottomLabel: Format.pace((present.min() ?? 0) - 8),
                         invert: true,
                         accessibilityTitle: "Average pace per week, last 12 weeks",
                         describe: { "\(Format.pace($0)) per kilometre" })
                .padding(.top, 24)
        }
    }

    // MARK: - Records

    private var recordsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            TVSectionLabel(text: "RECORDS")
            TVCard(padding: 28) {
                VStack(spacing: 0) {
                    ForEach(store.records) { record in
                        recordRow(record)
                        if record.id != store.records.last?.id {
                            Theme.hairline.frame(height: 1)
                        }
                    }
                }
            }
            .padding(.top, 16)
        }
    }

    private func recordRow(_ record: RecordEntry) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(record.label).font(.sg(24))
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(record.value).font(.stat(28))
                    .foregroundStyle(record.value == "—" ? Theme.muted : Theme.ink)
                Text(record.delta ?? record.date.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.sg(16))
                    .foregroundStyle(record.isRaceCountdown ? Theme.signal : Theme.muted)
            }
        }
        .padding(.vertical, 22)
    }

    // MARK: - Monthly volume

    private var monthlyPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            TVSectionLabel(text: "MONTHLY KM")
            TVMonthBars(items: store.monthlyTotals(count: 6).map { (shortMonth($0.month), $0.km) },
                        unit: "km") {
                "\(Int($0))"
            }
        }
    }

    // MARK: - Helpers

    /// The month the twelve-week window actually starts in — not "three months
    /// ago", which is a different month from the one the chart begins at.
    private var windowStartMonth: String {
        let start = Calendar.runWeek.date(byAdding: .weekOfYear, value: -11, to: .now) ?? .now
        return start.formatted(.dateTime.month(.abbreviated))
    }

    private func shortMonth(_ date: Date) -> String { date.formatted(.dateTime.month(.abbreviated)) }

    /// `allRuns`, like every other figure on this screen and on the phone:
    /// reading `runs` would make Progress the one place that ignores whatever
    /// the iPhone imported from Health and mirrored up to the TV.
    private var last12WeekRoad: (km: Double, time: TimeInterval) {
        let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -12, to: .now) ?? .now
        let runs = store.allRuns.filter { !$0.isTrail && $0.date >= cutoff }
        return (runs.reduce(0) { $0 + $1.distanceKm }, runs.reduce(0) { $0 + $1.duration })
    }
}

#Preview {
    FontLoader.registerAll()
    return TVProgressView()
        .environmentObject(RunStore(seeded: true))
        .preferredColorScheme(.dark)
}
