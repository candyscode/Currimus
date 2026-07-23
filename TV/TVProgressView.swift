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
                    recordsPanel.frame(width: 640)
                }

                monthlyPanel
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 60)
        }
    }

    // MARK: - Pace trend

    private var pacePanel: some View {
        let series = RunAnalytics.weeklyAvgPace(runs: store.runs, weeks: 12, roadOnly: true)
        let present = series.compactMap { $0 }
        let road12 = last12WeekRoad
        let avg = road12.km > 0 ? road12.time / road12.km : 0
        let delta = (present.first ?? 0) - (present.last ?? 0)
        return VStack(alignment: .leading, spacing: 0) {
            TVSectionLabel(text: "AVG PACE · LAST 12 WEEKS")
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(Format.pace(avg)).font(.stat(88)).kerning(-3)
                Text("/km").font(.sg(26)).foregroundStyle(Theme.bright)
                Spacer()
                if !present.isEmpty {
                    Text("\(Format.paceDelta(-abs(delta))) since \(sinceMonth)")
                        .font(.stat(20)).foregroundStyle(Theme.signal)
                }
            }
            .padding(.top, 10)
            TVTrendChart(values: series,
                         topLabel: Format.pace((present.max() ?? 0) + 8),
                         bottomLabel: Format.pace((present.min() ?? 0) - 8),
                         invert: true)
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
            TVMonthBars(items: store.monthlyTotals(count: 6).map { (shortMonth($0.month), $0.km) }) {
                "\(Int($0))"
            }
        }
    }

    // MARK: - Helpers

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
