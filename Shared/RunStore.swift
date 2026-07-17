import Foundation
import Combine

/// App-wide state: run log, records, settings. Sample data stands in for
/// HealthKit / WatchConnectivity sync in this build.
final class RunStore: ObservableObject {
    @Published var runs: [Run]
    @Published var zones = HRZones()
    @Published var weeklyGoalKm: Double = 35
    @Published var pacerTargetSecPerKm: TimeInterval {
        didSet { UserDefaults.standard.set(pacerTargetSecPerKm, forKey: "pacerTarget") }
    }
    @Published var kilometerAlert = true
    @Published var usesKilometers = true

    init(seeded: Bool = true) {
        runs = seeded ? SampleData.runs : []
        let stored = UserDefaults.standard.double(forKey: "pacerTarget")
        pacerTargetSecPerKm = stored > 0 ? stored : 315 // 5:15
    }

    var lastRun: Run? { runs.first }

    func add(_ run: Run) {
        runs.insert(run, at: 0)
        runs.sort { $0.date > $1.date }
    }

    // MARK: - Aggregates

    private var calendar: Calendar { Calendar.current }

    func runs(inWeekOf date: Date = .now) -> [Run] {
        runs.filter { calendar.isDate($0.date, equalTo: date, toGranularity: .weekOfYear) }
    }

    func runs(inMonthOf date: Date) -> [Run] {
        runs.filter { calendar.isDate($0.date, equalTo: date, toGranularity: .month) }
    }

    var weekKm: Double { runs(inWeekOf: .now).reduce(0) { $0 + $1.distanceKm } }

    /// Last week's km up to the same weekday, so the comparison stays honest
    /// mid-week.
    var lastWeekKmToDate: Double {
        guard let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: .now),
              let cutoff = calendar.date(byAdding: .day, value: -7, to: .now) else { return 0 }
        return runs(inWeekOf: lastWeek)
            .filter { $0.date <= cutoff }
            .reduce(0) { $0 + $1.distanceKm }
    }

    var monthKm: Double { runs(inMonthOf: .now).reduce(0) { $0 + $1.distanceKm } }

    /// Km per weekday of the current week, Monday first.
    var weekByDay: [Double] {
        var days = [Double](repeating: 0, count: 7)
        for run in runs(inWeekOf: .now) {
            let weekday = calendar.component(.weekday, from: run.date) // 1 = Sun
            days[(weekday + 5) % 7] += run.distanceKm
        }
        return days
    }

    /// (month start, total km) for the last `count` months, oldest first.
    func monthlyTotals(count: Int) -> [(month: Date, km: Double)] {
        (0..<count).reversed().compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: -offset, to: .now) else { return nil }
            return (month, runs(inMonthOf: month).reduce(0) { $0 + $1.distanceKm })
        }
    }

    /// Runs grouped by month, newest month first.
    var runsByMonth: [(month: Date, runs: [Run])] {
        let grouped = Dictionary(grouping: runs) {
            calendar.dateInterval(of: .month, for: $0.date)?.start ?? $0.date
        }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!.sorted { $0.date > $1.date }) }
    }

    var records: [RecordEntry] { SampleData.records }
}
