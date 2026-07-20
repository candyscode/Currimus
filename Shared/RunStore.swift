import Foundation
import Combine
#if canImport(HealthKit)
import HealthKit
#endif

/// App-wide state: run log, race, records, settings. Recorded runs persist
/// locally; demo content is only seeded with `-demo 1` (screenshots).
/// The iPhone owns the settings and pushes them to the watch; the watch
/// consumes them and syncs finished runs back.
final class RunStore: ObservableObject {
    @Published var runs: [Run] { didSet { persist() } }
    /// Runs other apps recorded, read from Apple Health. Cached on disk so the
    /// widgets — which cannot run a HealthKit query — see them too.
    @Published var importedRuns: [Run] = [] { didSet { persistImported() } }
    @Published var race: Race? { didSet { persistRace(); pushSettings() } }

    /// Everything the user ran, whoever recorded it. Every total, chart and
    /// record reads this; `runs` alone stays the list Currimus owns.
    var allRuns: [Run] { (runs + importedRuns).sorted { $0.date > $1.date } }

    @Published var zones = HRZones() { didSet { persistSettings(); pushSettings() } }
    @Published var weeklyGoalKm: Double = 55 { didSet { persistSettings() } }
    @Published var pacerTargetSecPerKm: TimeInterval = 315 { didSet { persistSettings(); pushSettings() } }
    @Published var pacerDefaultDistanceKm: Double? = 10 { didSet { persistSettings(); pushSettings() } }
    @Published var kilometerAlert = true { didSet { persistSettings(); pushSettings() } }
    @Published var countdownEnabled = true { didSet { persistSettings(); pushSettings() } }
    @Published var usesKilometers = true { didSet { persistSettings() } }

    private static let runsKey = "runs.v2"
    private static let importedKey = "imported.v1"
    private static let raceKey = "race.v1"
    private static let settingsKey = "settings.v1"
    private var isLoading = true

    init(seeded: Bool = UserDefaults.standard.bool(forKey: "demo")) {
        if seeded {
            runs = SampleData.runs
            race = SampleData.race
        } else {
            runs = Self.loadRuns()
            importedRuns = Self.loadImported()
            race = Self.loadRace()
        }
        loadSettings()
        isLoading = false
        // Seed the shared store on first launch: without this the widget shows
        // the default goal until the user happens to change a setting.
        persistSettings()

        RunSync.shared.onReceive = { [weak self] run in self?.add(run) }
        RunSync.shared.onSettings = { [weak self] settings in self?.apply(settings) }
        RunSync.shared.activate()
        pushSettings()
    }

    var lastRun: Run? { allRuns.first }

    func add(_ run: Run) {
        guard !runs.contains(where: { $0.id == run.id }) else { return }
        runs.insert(run, at: 0)
        runs.sort { $0.date > $1.date }
        // Health may already hold the same outing from another app.
        importedRuns = HealthImport.merging(importedRuns, with: runs)
    }

    func deleteRuns(at offsets: IndexSet, in subset: [Run]) {
        // Imported runs live in Health, not here — deleting one locally would
        // only make it come back on the next refresh.
        let ids = offsets.map { subset[$0] }.filter { !$0.isImported }.map(\.id)
        runs.removeAll { ids.contains($0.id) }
    }

    // MARK: - Apple Health

    #if canImport(HealthKit)
    private let healthStore = HKHealthStore()

    /// Pulls in runs other apps recorded. Safe to call on every foreground —
    /// the list is replaced wholesale, so nothing accumulates.
    @MainActor
    func refreshImportedRuns() async {
        guard !UserDefaults.standard.bool(forKey: "demo") else { return }
        await HealthImport.requestAuthorization(healthStore)
        let fetched = await HealthImport.fetchRuns(healthStore)
        let merged = HealthImport.merging(fetched, with: runs)
        if merged != importedRuns { importedRuns = merged }
    }
    #endif

    // MARK: - Persistence

    /// App-group defaults so the widget extension reads the same store as the
    /// app; falls back to standard defaults if the group is unavailable.
    static let defaults: UserDefaults = {
        guard let shared = UserDefaults(suiteName: "group.com.currimus.app") else { return .standard }
        // The log used to live in standard defaults. Moving to the group would
        // read as "all my runs vanished", so carry them over once.
        for key in [runsKey, raceKey, settingsKey, "weeklyGoal", "usesKilometers"]
        where shared.object(forKey: key) == nil {
            if let legacy = UserDefaults.standard.object(forKey: key) {
                shared.set(legacy, forKey: key)
            }
        }
        return shared
    }()

    private static func loadRuns() -> [Run] {
        guard let data = defaults.data(forKey: runsKey),
              let stored = try? JSONDecoder().decode([Run].self, from: data) else { return [] }
        return stored
    }

    private static func loadImported() -> [Run] {
        guard let data = defaults.data(forKey: importedKey),
              let stored = try? JSONDecoder().decode([Run].self, from: data) else { return [] }
        return stored
    }

    private func persistImported() {
        guard !isLoading, !UserDefaults.standard.bool(forKey: "demo"),
              let data = try? JSONEncoder().encode(importedRuns) else { return }
        Self.defaults.set(data, forKey: Self.importedKey)
    }

    private static func loadRace() -> Race? {
        guard let data = defaults.data(forKey: raceKey) else { return nil }
        return try? JSONDecoder().decode(Race.self, from: data)
    }

    private func persist() {
        guard !isLoading, !UserDefaults.standard.bool(forKey: "demo"),
              let data = try? JSONEncoder().encode(runs) else { return }
        Self.defaults.set(data, forKey: Self.runsKey)
    }

    private func persistRace() {
        guard !isLoading, !UserDefaults.standard.bool(forKey: "demo") else { return }
        if let race, let data = try? JSONEncoder().encode(race) {
            Self.defaults.set(data, forKey: Self.raceKey)
        } else {
            Self.defaults.removeObject(forKey: Self.raceKey)
        }
    }

    private func persistSettings() {
        guard !isLoading else { return }
        if let data = try? JSONEncoder().encode(watchSettings) {
            Self.defaults.set(data, forKey: Self.settingsKey)
        }
        Self.defaults.set(weeklyGoalKm, forKey: "weeklyGoal")
        Self.defaults.set(usesKilometers, forKey: "usesKilometers")
    }

    private func loadSettings() {
        if let data = Self.defaults.data(forKey: Self.settingsKey),
           let s = try? JSONDecoder().decode(WatchSettings.self, from: data) {
            pacerTargetSecPerKm = s.pacerTargetSecPerKm
            pacerDefaultDistanceKm = s.pacerDefaultDistanceKm
            kilometerAlert = s.kilometerAlert
            countdownEnabled = s.countdownEnabled
            zones = HRZones(maxHR: s.maxHR, overrides: s.zoneBounds)
        }
        if Self.defaults.object(forKey: "weeklyGoal") != nil {
            weeklyGoalKm = Self.defaults.double(forKey: "weeklyGoal")
        }
        if Self.defaults.object(forKey: "usesKilometers") != nil {
            usesKilometers = Self.defaults.bool(forKey: "usesKilometers")
        }
    }

    // MARK: - Settings sync

    var watchSettings: WatchSettings {
        WatchSettings(
            pacerTargetSecPerKm: pacerTargetSecPerKm,
            pacerDefaultDistanceKm: pacerDefaultDistanceKm,
            kilometerAlert: kilometerAlert,
            countdownEnabled: countdownEnabled,
            maxHR: zones.maxHR,
            zoneBounds: zones.overrides
        )
    }

    private func pushSettings() {
        guard !isLoading else { return }
        #if os(iOS)
        RunSync.shared.send(settings: watchSettings)
        #endif
    }

    /// Watch side: apply settings pushed from the iPhone.
    private func apply(_ settings: WatchSettings) {
        #if os(watchOS)
        isLoading = true
        pacerTargetSecPerKm = settings.pacerTargetSecPerKm
        pacerDefaultDistanceKm = settings.pacerDefaultDistanceKm
        kilometerAlert = settings.kilometerAlert
        countdownEnabled = settings.countdownEnabled
        zones = HRZones(maxHR: settings.maxHR, overrides: settings.zoneBounds)
        isLoading = false
        persistSettings()
        #endif
    }

    // MARK: - Aggregates

    private var calendar: Calendar { Calendar.current }

    func runs(inWeekOf date: Date = .now) -> [Run] {
        allRuns.filter { calendar.isDate($0.date, equalTo: date, toGranularity: .weekOfYear) }
    }

    func runs(inMonthOf date: Date) -> [Run] {
        allRuns.filter { calendar.isDate($0.date, equalTo: date, toGranularity: .month) }
    }

    var weekKm: Double { runs(inWeekOf: .now).reduce(0) { $0 + $1.distanceKm } }

    var weekGoalFraction: Double { weeklyGoalKm > 0 ? weekKm / weeklyGoalKm : 0 }

    var lastWeekKmToDate: Double {
        guard let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: .now),
              let cutoff = calendar.date(byAdding: .day, value: -7, to: .now) else { return 0 }
        return runs(inWeekOf: lastWeek).filter { $0.date <= cutoff }.reduce(0) { $0 + $1.distanceKm }
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

    func monthlyTotals(count: Int) -> [(month: Date, km: Double)] {
        (0..<count).reversed().compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: -offset, to: .now) else { return nil }
            return (month, runs(inMonthOf: month).reduce(0) { $0 + $1.distanceKm })
        }
    }

    func monthlyClimb(count: Int) -> [(month: Date, climb: Double)] {
        (0..<count).reversed().compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: -offset, to: .now) else { return nil }
            let climb = runs(inMonthOf: month).reduce(0.0) { $0 + ($1.climbMeters ?? 0) }
            return (month, climb)
        }
    }

    /// Filtered log grouped by month, newest first.
    enum LogFilter { case all, road, trail }

    func filteredRuns(_ filter: LogFilter) -> [Run] {
        switch filter {
        case .all: return allRuns
        case .road: return allRuns.filter { !$0.isTrail }
        case .trail: return allRuns.filter { $0.isTrail }
        }
    }

    func runsByMonth(_ filter: LogFilter = .all) -> [(month: Date, runs: [Run])] {
        let grouped = Dictionary(grouping: filteredRuns(filter)) {
            calendar.dateInterval(of: .month, for: $0.date)?.start ?? $0.date
        }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!.sorted { $0.date > $1.date }) }
    }

    var yearKm: Double {
        allRuns.filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .year) }
            .reduce(0) { $0 + $1.distanceKm }
    }

    /// (week label, km) for the last 4 weeks (race readiness), oldest first.
    func last4Weeks() -> [(label: String, km: Double)] {
        (0..<4).reversed().compactMap { offset in
            guard let weekDate = calendar.date(byAdding: .weekOfYear, value: -offset, to: .now) else { return nil }
            let km = runs(inWeekOf: weekDate).reduce(0) { $0 + $1.distanceKm }
            return (offset == 0 ? "now" : "W\(4 - offset)", km)
        }
    }

    var last4WeeksKm: Double { last4Weeks().reduce(0) { $0 + $1.km } }

    // MARK: - Records & prediction

    var prediction: RunAnalytics.Prediction? {
        guard let race else { return nil }
        return RunAnalytics.predict(race: race, runs: allRuns)
    }

    /// Longest run and its date.
    var longestRun: Run? { allRuns.max { $0.distanceKm < $1.distanceKm } }
    var mostClimbRun: Run? { allRuns.max { ($0.climbMeters ?? 0) < ($1.climbMeters ?? 0) } }

    var records: [RecordEntry] {
        let prs = RunAnalytics.personalBests(runs: allRuns)
        var entries: [RecordEntry] = []
        func add(_ label: String, km: Double) {
            if let t = prs[km] {
                let date = recordDate(km: km)
                entries.append(RecordEntry(label: label, value: Format.clock(t), date: date))
            } else {
                let note = race?.distance.km == km ? "race day in \(race?.daysUntil() ?? 0) days" : "—"
                entries.append(RecordEntry(label: label, value: "—", date: .now, delta: note))
            }
        }
        add("1 km", km: 1)
        add("5 km", km: 5)
        add("10 km", km: 10)
        add("Half marathon", km: 21.0975)
        add("Marathon", km: 42.195)
        if let longest = longestRun {
            entries.append(RecordEntry(label: "Longest run", value: "\(Format.km(longest.distanceKm, decimals: 1)) km", date: longest.date))
        }
        if let climb = mostClimbRun, (climb.climbMeters ?? 0) > 0 {
            entries.append(RecordEntry(label: "Most climb", value: "\(Int(climb.climbMeters ?? 0)) m", date: climb.date, delta: "trail"))
        }
        return entries
    }

    /// The single most impressive fresh PR for the Records banner, if any.
    var newestRecord: RecordEntry? { records.first { $0.label == "5 km" && $0.value != "—" } }

    private func recordDate(km: Double) -> Date {
        // Attribute the PR to the run that holds the fastest window.
        if km <= 10, let run = allRuns.filter({ $0.splits.count >= Int(km) })
            .min(by: { (RunAnalytics.fastestWindow(km: Int(km), runs: [$0]) ?? .infinity)
                     < (RunAnalytics.fastestWindow(km: Int(km), runs: [$1]) ?? .infinity) }) {
            return run.date
        }
        return runs.filter { $0.distanceKm >= km - 0.4 }.min { $0.paceSecPerKm < $1.paceSecPerKm }?.date ?? .now
    }
}
