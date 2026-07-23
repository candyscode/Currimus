import Foundation
import Combine
#if canImport(HealthKit)
import HealthKit
#endif

/// App-wide state: run log, race, records, settings. Recorded runs persist
/// locally; demo content is only seeded with `-demo 1` (screenshots).
/// The iPhone owns the settings and pushes them to the watch; the watch
/// consumes them and syncs finished runs back.
///
/// The log itself holds metadata only — GPS tracks and altitude series live in
/// `RunSampleStore`, reachable through `samples(for:)` / `hydrated(_:)`.
@MainActor
final class RunStore: ObservableObject {
    @Published var runs: [Run] { didSet { invalidateAggregates(); persist() } }
    /// Runs other apps recorded, read from Apple Health. Cached on disk so the
    /// widgets — which cannot run a HealthKit query — see them too.
    @Published var importedRuns: [Run] = [] { didSet { invalidateAggregates(); persistImported() } }
    @Published var race: Race? { didSet { invalidateAggregates(); persistRace(); pushSettings() } }

    @Published var zones = HRZones() { didSet { persistSettings(); pushSettings() } }
    @Published var weeklyGoalKm: Double = 55 { didSet { persistSettings() } }
    @Published var pacerTargetSecPerKm: TimeInterval = 315 { didSet { persistSettings(); pushSettings() } }
    @Published var pacerDefaultDistanceKm: Double? = 10 { didSet { persistSettings(); pushSettings() } }
    @Published var kilometerAlert = true { didSet { persistSettings(); pushSettings() } }
    @Published var countdownEnabled = true { didSet { persistSettings(); pushSettings() } }
    @Published var usesKilometers = true { didSet { persistSettings() } }
    /// GPS fidelity the watch records with — the run's dominant battery cost.
    @Published var gpsAccuracy: GPSAccuracy = .high { didSet { persistSettings(); pushSettings() } }
    /// Dim and simplify the run screen while the wrist is down.
    @Published var alwaysOnReduced = true { didSet { persistSettings(); pushSettings() } }

    /// Where this store reads and writes. Injected so tests get a scratch
    /// suite instead of scribbling on the real app group. `nonisolated(unsafe)`
    /// for the same reason as `AppDefaults.shared`: thread-safe, unannotated.
    private nonisolated(unsafe) let defaults: UserDefaults
    /// Demo builds keep everything in memory — no disk writes at all.
    private let isDemo: Bool
    private var isLoading = true

    /// Encoding the log used to happen synchronously inside `didSet`, i.e. on
    /// the main thread on every single mutation. It is off the main thread now.
    private static let ioQueue = DispatchQueue(label: "com.currimus.app.store-io", qos: .utility)

    init(seeded: Bool = UserDefaults.standard.bool(forKey: "demo"),
         defaults: UserDefaults = AppDefaults.shared,
         isDemo: Bool? = nil) {
        self.defaults = defaults
        // Seeded runs and demo mode are the same thing everywhere except in
        // tests, which want the sample log without the "never persist" rule.
        self.isDemo = isDemo ?? seeded

        if seeded {
            runs = SampleData.runs
            race = SampleData.race
        } else {
            runs = Self.loadRuns(from: defaults)
            importedRuns = Self.loadImported(from: defaults)
            race = Self.loadRace(from: defaults)
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

    // MARK: - Log

    /// Everything the user ran, whoever recorded it. Every total, chart and
    /// record reads this; `runs` alone stays the list Currimus owns.
    ///
    /// Cached: it used to re-merge and re-sort the whole log on every access,
    /// and SwiftUI touches it many times per body pass.
    var allRuns: [Run] {
        if let cachedAllRuns { return cachedAllRuns }
        let merged = (runs + importedRuns).sorted { $0.date > $1.date }
        cachedAllRuns = merged
        return merged
    }

    private var cachedAllRuns: [Run]?
    private var cachedRecords: [RecordEntry]?
    private var cachedHolders: [UUID: String]?
    private var cachedLatestBenchmark: LatestBenchmark??

    private func invalidateAggregates() {
        cachedAllRuns = nil
        cachedRecords = nil
        cachedHolders = nil
        cachedLatestBenchmark = nil
    }

    var lastRun: Run? { allRuns.first }

    func add(_ run: Run) {
        guard !runs.contains(where: { $0.id == run.id }) else { return }
        storeSamples(of: run)
        // The log keeps metadata; the track and profile went to their sidecar.
        runs.insert(run.strippingSamples, at: 0)
        runs.sort { $0.date > $1.date }
        // Health may already hold the same outing from another app.
        importedRuns = HealthImport.merging(importedRuns, with: runs)
        // Publish the freshly-arrived run to the Apple TV. Push the full run,
        // samples included, so its route and elevation reach the TV's detail.
        cloudUpsert(run)
    }

    #if os(tvOS)
    /// tvOS is a read-only mirror of what the phone published to CloudKit — no
    /// recording, no HealthKit, no watch. This replaces the whole log in one
    /// shot, so the Apple TV reuses every aggregate, record and chart the phone
    /// computes with byte-identical logic instead of a parallel implementation.
    ///
    /// The phone syncs `allRuns` (its own runs *and* the ones it imported from
    /// Health), so the split is reconstructed from each run's `imported` flag.
    /// Persisting to standard defaults is a welcome side effect: it doubles as
    /// an offline cache for the next cold launch before CloudKit answers.
    func replaceAllFromCloud(_ cloudRuns: [Run]) {
        let incoming = cloudRuns.sorted { $0.date > $1.date }
        // Move each run's GPS track and altitude series into the sidecar store
        // (Caches on tvOS) so `samples(for:)` / `hydrated(_:)` — and with them
        // the run-detail map and elevation profile — work exactly as on iOS,
        // and the log itself stays metadata-only.
        for run in incoming where run.carriesSamples { storeSamples(of: run) }
        importedRuns = incoming.filter(\.isImported).map(\.strippingSamples)
        runs = incoming.filter { !$0.isImported }.map(\.strippingSamples)
    }
    #endif

    func deleteRuns(at offsets: IndexSet, in subset: [Run]) {
        // Imported runs live in Health, not here — deleting one locally would
        // only make it come back on the next refresh.
        let ids = offsets.map { subset[$0] }.filter { !$0.isImported }.map(\.id)
        runs.removeAll { ids.contains($0.id) }
        for id in ids {
            sampleCache[id] = nil
            if !isDemo { RunSampleStore.delete(id) }
            cloudDelete(id)
        }
    }

    // MARK: - Samples (GPS track + altitude series)

    private var sampleCache: [UUID: RunSamples] = [:]

    /// The heavy half of a run, loaded from its sidecar on first ask.
    func samples(for run: Run) -> RunSamples {
        if let cached = sampleCache[run.id] { return cached }
        // A run that still carries its samples (demo data, a run just handed
        // over by the watch) is its own source.
        let loaded = RunSampleStore.load(run.id) ?? RunSamples(run)
        sampleCache[run.id] = loaded
        return loaded
    }

    /// The run with its GPS track and altitude series put back — what a detail
    /// screen or an export needs, and nothing else does.
    func hydrated(_ run: Run) -> Run { run.merging(samples(for: run)) }

    private func storeSamples(of run: Run) {
        guard run.carriesSamples else { return }
        let samples = RunSamples(run)
        sampleCache[run.id] = samples
        guard !isDemo else { return }
        RunSampleStore.save(samples, for: run.id)
    }

    // MARK: - CloudKit mirror (iPhone → Apple TV)

    /// The phone is the only writer to CloudKit. These are no-ops everywhere
    /// else: the watch has its own phone to hand runs to, and the TV only reads.
    /// Each fires a detached task so a network round-trip never blocks a log
    /// mutation on the main actor; the local store is the source of truth and
    /// the sync is best-effort (`RunCloudSync` logs its own failures).

    #if os(iOS)
    /// Publish existing runs to CloudKit once, e.g. on first launch after the
    /// feature ships, so a TV signed into the same account sees history — not
    /// just runs recorded from now on. Idempotent, so calling it again is safe.
    func backfillCloud() {
        let hydratedRuns = allRuns.map(hydrated)
        Task.detached { await RunCloudSync.backfill(hydratedRuns) }
    }

    private func cloudUpsert(_ run: Run) {
        guard !isDemo else { return }
        Task.detached { await RunCloudSync.upsert(run) }
    }

    private func cloudDelete(_ id: UUID) {
        guard !isDemo else { return }
        Task.detached { await RunCloudSync.delete(id: id) }
    }

    /// Mirror the change in the imported-runs set: publish arrivals, remove
    /// departures. Imported runs carry no samples, so the metadata is enough.
    private func cloudSyncImportedDelta(from previous: [Run], to current: [Run]) {
        guard !isDemo else { return }
        let previousIDs = Set(previous.map(\.id))
        let currentIDs = Set(current.map(\.id))
        let added = current.filter { !previousIDs.contains($0.id) }
        let removed = previousIDs.subtracting(currentIDs)
        Task.detached {
            for run in added { await RunCloudSync.upsert(run) }
            for id in removed { await RunCloudSync.delete(id: id) }
        }
    }
    #else
    func cloudUpsert(_ run: Run) {}
    func cloudDelete(_ id: UUID) {}
    func cloudSyncImportedDelta(from previous: [Run], to current: [Run]) {}
    #endif

    // MARK: - Apple Health

    #if canImport(HealthKit)
    private let healthStore = HKHealthStore()

    /// Pulls in runs other apps recorded. Safe to call on every foreground —
    /// the list is replaced wholesale, so nothing accumulates.
    /// `requestingAccess` decides whether this may raise the Health permission
    /// sheet. The phone asks — it is the device that owns settings and where
    /// the sheet is expected. The watch never asks here: it would cover a live
    /// run screen at launch. Its own prompt comes when a run starts, and this
    /// query simply returns nothing until then.
    func refreshImportedRuns(requestingAccess: Bool = false) async {
        guard !isDemo else { return }
        if requestingAccess { await HealthImport.requestAuthorization(healthStore) }
        let fetched = await HealthImport.fetchRuns(healthStore)
        let merged = HealthImport.merging(fetched, with: runs)
        if merged != importedRuns {
            let previous = importedRuns
            importedRuns = merged
            // The TV mirrors `allRuns`, imported runs included, so it has no
            // Health to derive them itself. Sync only the delta.
            cloudSyncImportedDelta(from: previous, to: merged)
        }
        await refreshHeartRateZones()
    }

    /// Re-derives the zones from Health. Never touches zones the user has
    /// tuned by hand — a measured number is better than a formula, but not
    /// better than a decision.
    @MainActor
    func refreshHeartRateZones(force: Bool = false, requestingAccess: Bool = false) async {
        guard force || zones.overrides == nil else { return }
        if requestingAccess { await HealthImport.requestAuthorization(healthStore) }
        guard let result = await HeartRateProfile.derive(healthStore) else { return }
        var updated = zones
        updated.maxHR = result.maxHR
        updated.restingHR = result.restingHR
        updated.derivation = result.derivation
        if force { updated.overrides = nil }
        if updated != zones { zones = updated }
    }
    #endif

    // MARK: - Persistence

    private static func loadRuns(from defaults: UserDefaults) -> [Run] {
        guard let data = defaults.data(forKey: AppDefaults.runsKey) else { return [] }
        do {
            let stored = try JSONDecoder().decode([Run].self, from: data)
            return migrateSamplesIfNeeded(stored, in: defaults)
        } catch {
            Log.store.error("run log unreadable: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Older installs kept the GPS track and altitude series inside the log
    /// blob. Move them to their sidecar files once, so the blob the widget
    /// faults in shrinks back to metadata.
    private static func migrateSamplesIfNeeded(_ stored: [Run], in defaults: UserDefaults) -> [Run] {
        guard stored.contains(where: \.carriesSamples) else { return stored }
        let lightweight = stored.map { run -> Run in
            guard run.carriesSamples else { return run }
            RunSampleStore.save(RunSamples(run), for: run.id)
            return run.strippingSamples
        }
        do {
            defaults.set(try JSONEncoder().encode(lightweight), forKey: AppDefaults.runsKey)
            Log.store.notice("moved samples of \(lightweight.count) runs into sidecar files")
        } catch {
            Log.store.error("sample migration could not be saved: \(error.localizedDescription, privacy: .public)")
            return stored
        }
        return lightweight
    }

    private static func loadImported(from defaults: UserDefaults) -> [Run] {
        guard let data = defaults.data(forKey: AppDefaults.importedKey) else { return [] }
        do {
            return try JSONDecoder().decode([Run].self, from: data)
        } catch {
            Log.store.error("imported log unreadable: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private static func loadRace(from defaults: UserDefaults) -> Race? {
        guard let data = defaults.data(forKey: AppDefaults.raceKey) else { return nil }
        do {
            return try JSONDecoder().decode(Race.self, from: data)
        } catch {
            Log.store.error("race unreadable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// `Sendable` is the honest constraint: the value really does leave the
    /// main actor for the encoder. Every caller already qualifies — `[Run]`,
    /// `Race` and `WatchSettings` are all value types of value types.
    private func write<T: Encodable & Sendable>(_ value: T, forKey key: String) {
        guard !isLoading, !isDemo else { return }
        nonisolated(unsafe) let defaults = self.defaults
        Self.ioQueue.async {
            do {
                defaults.set(try JSONEncoder().encode(value), forKey: key)
            } catch {
                Log.store.error("could not save \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func persist() {
        write(runs, forKey: AppDefaults.runsKey)
        guard !isLoading, !isDemo else { return }
        // A deleted run must not leave its track behind.
        let live = Set(runs.map(\.id))
        Self.ioQueue.async { RunSampleStore.prune(keeping: live) }
    }

    private func persistImported() { write(importedRuns, forKey: AppDefaults.importedKey) }

    /// Test seam: block until the queued writes have landed on disk.
    static func flushPendingWrites() { ioQueue.sync {} }

    private func persistRace() {
        guard !isLoading, !isDemo else { return }
        if let race {
            write(race, forKey: AppDefaults.raceKey)
        } else {
            defaults.removeObject(forKey: AppDefaults.raceKey)
        }
    }

    private func persistSettings() {
        guard !isLoading else { return }
        // Settings are tiny and the widget reads them on the next tick, so
        // these stay synchronous — demo builds included, the widget has no
        // other way to learn the goal.
        do {
            defaults.set(try JSONEncoder().encode(watchSettings), forKey: AppDefaults.settingsKey)
        } catch {
            Log.store.error("could not save settings: \(error.localizedDescription, privacy: .public)")
        }
        defaults.set(weeklyGoalKm, forKey: AppDefaults.goalKey)
        defaults.set(usesKilometers, forKey: AppDefaults.unitsKey)
        defaults.set(gpsAccuracy.rawValue, forKey: AppDefaults.gpsAccuracyKey)
    }

    private func loadSettings() {
        if let data = defaults.data(forKey: AppDefaults.settingsKey) {
            do {
                let s = try JSONDecoder().decode(WatchSettings.self, from: data)
                pacerTargetSecPerKm = s.pacerTargetSecPerKm
                pacerDefaultDistanceKm = s.pacerDefaultDistanceKm
                kilometerAlert = s.kilometerAlert
                countdownEnabled = s.countdownEnabled
                zones = HRZones(maxHR: s.maxHR, overrides: s.zoneBounds)
            } catch {
                Log.store.error("settings unreadable: \(error.localizedDescription, privacy: .public)")
            }
        }
        if defaults.object(forKey: AppDefaults.goalKey) != nil {
            weeklyGoalKm = defaults.double(forKey: AppDefaults.goalKey)
        }
        if defaults.object(forKey: AppDefaults.unitsKey) != nil {
            usesKilometers = defaults.bool(forKey: AppDefaults.unitsKey)
        }
        if let raw = defaults.string(forKey: AppDefaults.gpsAccuracyKey),
           let accuracy = GPSAccuracy(rawValue: raw) {
            gpsAccuracy = accuracy
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
            zoneBounds: zones.overrides,
            restingHR: zones.restingHR,
            gpsAccuracy: gpsAccuracy,
            alwaysOnReduced: alwaysOnReduced
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
        zones = HRZones(maxHR: settings.maxHR, overrides: settings.zoneBounds,
                        restingHR: settings.restingHR)
        if let accuracy = settings.gpsAccuracy { gpsAccuracy = accuracy }
        if let reduced = settings.alwaysOnReduced { alwaysOnReduced = reduced }
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
        if let cachedRecords { return cachedRecords }
        let built = buildRecords()
        cachedRecords = built
        return built
    }

    private func buildRecords() -> [RecordEntry] {
        let runs = allRuns
        let prs = RunAnalytics.personalBests(runs: runs)

        let benchmarks: [RecordEntry.Kind] = [.oneK, .fiveK, .tenK, .half, .marathon]
        var entries: [RecordEntry] = benchmarks.map { kind in
            guard let km = kind.km else { preconditionFailure("benchmark kinds carry a distance") }
            if let time = prs[km] {
                return RecordEntry(kind: kind, value: Format.clock(time),
                                   date: recordDate(km: km, in: runs))
            }
            let isTarget = race?.distance.km == km
            let note = isTarget
                ? String(localized: "race day in \(race?.daysUntil() ?? 0) days")
                : "—"
            return RecordEntry(kind: kind, value: "—", date: .now,
                               delta: note, isRaceCountdown: isTarget)
        }
        if let longest = longestRun {
            entries.append(RecordEntry(kind: .longest,
                                       value: "\(Format.km(longest.distanceKm, decimals: 1)) km",
                                       date: longest.date))
        }
        if let climb = mostClimbRun, (climb.climbMeters ?? 0) > 0 {
            entries.append(RecordEntry(kind: .mostClimb,
                                       value: "\(Int(climb.climbMeters ?? 0)) m",
                                       date: climb.date, delta: String(localized: "trail")))
        }
        return entries
    }

    /// One record row by kind — what the Progress cards and the tests want,
    /// without matching on display text.
    func record(_ kind: RecordEntry.Kind) -> RecordEntry? {
        records.first { $0.kind == kind }
    }

    /// The benchmark PR the Records banner leads with: the freshest one, and
    /// what it beat.
    struct LatestBenchmark {
        var label: String
        var value: String
        /// How much it beat the previous best, when there was one.
        var delta: String?
        var date: Date
    }

    /// Cached because it is O(runs × splits) and the Records screen used to
    /// recompute it — twice — on every body pass.
    var latestBenchmark: LatestBenchmark? {
        if let cachedLatestBenchmark { return cachedLatestBenchmark }
        let built = buildLatestBenchmark()
        cachedLatestBenchmark = .some(built)
        return built
    }

    private func buildLatestBenchmark() -> LatestBenchmark? {
        let runs = allRuns
        let candidates: [(km: Int, label: String)] = [(5, "5K"), (10, "10K")]
        // Freshest first: a 10K PR set last week leads over a 5K PR from May.
        let held = candidates.compactMap { candidate -> LatestBenchmark? in
            guard let holder = RunAnalytics.fastestWindowHolder(km: candidate.km, runs: runs) else { return nil }
            let previous = RunAnalytics.fastestWindow(
                km: candidate.km, runs: runs.filter { $0.id != holder.run.id })
            return LatestBenchmark(
                label: candidate.label,
                value: Format.clock(holder.seconds),
                delta: previous.map { "\(Format.paceDelta(holder.seconds - $0)) vs previous" },
                date: holder.run.date
            )
        }
        return held.max { $0.date < $1.date }
    }

    /// Which runs currently hold a benchmark, for the log's inline PR tag.
    /// Computed once per log change instead of once per row render.
    var benchmarkHolders: [UUID: String] {
        if let cachedHolders { return cachedHolders }
        var map: [UUID: String] = [:]
        let runs = allRuns
        for (km, label) in [(5, "5K PR"), (10, "10K PR")] {
            if let holder = RunAnalytics.fastestWindowHolder(km: km, runs: runs) {
                map[holder.run.id] = label
            }
        }
        if let longest = longestRun { map[longest.id, default: ""] = "Longest" }
        cachedHolders = map
        return map
    }

    /// Attribute a PR to the run that holds the fastest window.
    private func recordDate(km: Double, in runs: [Run]) -> Date {
        if km <= 10, let holder = RunAnalytics.fastestWindowHolder(km: Int(km), runs: runs) {
            return holder.run.date
        }
        return runs.filter { $0.distanceKm >= km - 0.4 }
            .min { $0.paceSecPerKm < $1.paceSecPerKm }?.date ?? .now
    }
}
