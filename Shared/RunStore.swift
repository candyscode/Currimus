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
    /// Zone the watch holds the runner in by vibration alone; nil = off.
    @Published var zoneCoachTarget: Int? { didSet { persistSettings(); pushSettings() } }
    @Published var countdownEnabled = true { didSet { persistSettings(); pushSettings() } }
    /// GPS fidelity the watch records with — the run's dominant battery cost.
    @Published var gpsAccuracy: GPSAccuracy = .high { didSet { persistSettings(); pushSettings() } }
    /// Dim and simplify the run screen while the wrist is down.
    @Published var alwaysOnReduced = true { didSet { persistSettings(); pushSettings() } }
    /// Whether there is a watch to record on. iPhone side only; the watch is
    /// obviously its own answer.
    @Published private(set) var watchState: WatchAvailability = .unknown

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

    init(seeded: Bool = DebugFlags.seedsDemoContent,
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
        #if os(iOS)
        RunSync.shared.onWatchState = { [weak self] state in self?.watchState = state }
        #endif
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
    private var cachedFastestPaceOfMonth: Set<UUID>?
    /// Grouping and sorting the whole log ran on every body pass of the Log
    /// screen — including every tap of a checkbox in its marking mode.
    private var cachedMonths: [LogFilter: [(month: Date, runs: [Run])]] = [:]
    private var cachedLogText: [UUID: LogRowText] = [:]

    private func invalidateAggregates() {
        cachedAllRuns = nil
        cachedRecords = nil
        cachedHolders = nil
        cachedLatestBenchmark = nil
        cachedFastestPaceOfMonth = nil
        cachedMonths = [:]
        cachedLogText = [:]
    }

    var lastRun: Run? { allRuns.first }

    func add(_ run: Run) {
        guard !runs.contains(where: { $0.id == run.id }) else { return }
        // The watch refused to file these locally and told the runner so —
        // but it sent them to the phone anyway, and the phone took them. The
        // claim on the watch ("no distance, this run is not being saved") was
        // therefore false, and the log filled with 0.00 km entries that drag
        // every weekly pace average with them.
        guard run.hasUsableDistance else {
            Log.store.notice("run without distance not filed")
            return
        }
        storeSamples(of: run)
        // The log keeps metadata; the track and profile went to their sidecar.
        runs.insert(run.strippingSamples, at: 0)
        runs.sort { $0.date > $1.date }
        // Health may already hold the same outing from another app.
        importedRuns = HealthImport.merging(importedRuns, with: runs)
    }

    func deleteRuns(at offsets: IndexSet, in subset: [Run]) {
        delete(offsets.map { subset[$0] })
    }

    /// Deletes one run — what the log's own delete action calls, since the
    /// screen is a hand-built scroll view and has no `IndexSet` to offer.
    func delete(_ run: Run) { delete([run]) }

    /// Deletes runs here and in Apple Health.
    ///
    /// The log goes first and synchronously: the list must close over the row
    /// the moment the runner confirms, not when a Health query comes back.
    /// Health follows in the background, and only says anything if it refused
    /// — see `healthNotice`.
    func delete(_ runs: [Run]) {
        let mine = runs.filter { !$0.isImported }
        guard !mine.isEmpty else { return }
        healthNotice = nil
        remove(mine)
        #if canImport(HealthKit)
        guard !isDemo else { return }
        Task { await deleteFromHealth(mine) }
        #endif
    }

    /// Set when a delete could not be carried through to Apple Health, so the
    /// log can say so. Nil the rest of the time: a delete that worked needs no
    /// announcement.
    @Published var healthNotice: String?

    #if canImport(HealthKit)
    private func deleteFromHealth(_ runs: [Run]) async {
        switch await HealthImport.deleteWorkouts(for: runs, in: healthStore) {
        case .removed(let count):
            Log.store.notice("removed \(count) workout(s) from Health")
        case .nothingFound, .unavailable:
            break
        case .refused:
            healthNotice = String(localized: "Deleted here. Apple Health did not allow Currimus to remove the workout — turn on \"Workouts\" under Settings › Apps › Health › Data Access & Devices › Currimus.")
        case .failed(let reason):
            Log.store.error("health delete failed: \(reason, privacy: .public)")
            healthNotice = String(localized: "Deleted here. The workout could not be removed from Apple Health.")
        }
    }
    #endif

    /// Writes back an edited run. Imported runs are Health's, not ours.
    func update(_ run: Run) {
        guard !run.isImported,
              let index = runs.firstIndex(where: { $0.id == run.id }) else { return }
        // The log holds metadata only — an edit must not put the track back in.
        runs[index] = run.strippingSamples
    }

    private func remove(_ candidates: [Run]) {
        // Imported runs live in Health, not here — deleting one locally would
        // only make it come back on the next refresh.
        let ids = candidates.filter { !$0.isImported }.map(\.id)
        guard !ids.isEmpty else { return }
        runs.removeAll { ids.contains($0.id) }
        for id in ids {
            sampleCache[id] = nil
            if !isDemo { RunSampleStore.delete(id) }
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

    #if canImport(HealthKit)
    /// Fills in what a run another app recorded keeps in Health rather than in
    /// the log — its heart-rate zones and its GPS track.
    ///
    /// On demand, when a detail screen asks: pulling every sample of eighteen
    /// months of other apps' workouts on each refresh would spend a lot of
    /// battery filling screens nobody opened. What comes back is cached like
    /// any other run's samples, so the second visit costs nothing.
    func hydrateImported(_ run: Run) async { await hydrate(run) }

    /// Rebuilds what Health can still tell us about one run — zones, route,
    /// distance per zone and per-kilometre splits — for a run of ours as much
    /// as for one another app recorded.
    func hydrate(_ run: Run, force: Bool = false) async {
        guard !isDemo, force || needsHydration(run) else { return }
        // The route type was added to the read set after most installs had
        // already answered the Health prompt, so it sits undetermined and
        // every query comes back empty. Asking again raises the sheet for the
        // types that are new and is a no-op for the rest.
        if !askedHealth {
            askedHealth = true
            await HealthImport.requestAuthorization(healthStore)
        }
        guard let detail = await HealthImport.detail(for: run, zones: zones,
                                                     fallbackRoute: samples(for: run).route,
                                                     in: healthStore) else { return }
        // Asked, and answered.
        hydratedImported.insert(run.id)

        // Written to the sidecar, not just to the run: the imported list is
        // replaced wholesale on every refresh, and zones that lived only there
        // vanished from under the detail screen the runner was looking at.
        let rebuilt = detail.zoneSeconds.reduce(0, +) >= 1 ? detail.zoneSeconds : nil
        if !detail.route.isEmpty || rebuilt != nil {
            let samples = RunSamples(route: detail.route.isEmpty ? nil : detail.route,
                                     zoneSeconds: rebuilt,
                                     zoneDistanceKm: detail.zoneDistanceKm,
                                     splits: detail.splits.isEmpty ? nil : detail.splits,
                                     gradeAdjustedSecPerKm: detail.gradeAdjustedSecPerKm)
            sampleCache[run.id] = samples
            RunSampleStore.save(samples, for: run.id)
        }
        if let index = importedRuns.firstIndex(where: { $0.id == run.id }) {
            if let rebuilt { importedRuns[index].zoneSeconds = rebuilt }
            importedRuns[index].zoneDistanceKm = detail.zoneDistanceKm
            if !detail.splits.isEmpty { importedRuns[index].splits = detail.splits }
            importedRuns[index].gradeAdjustedSecPerKm = detail.gradeAdjustedSecPerKm
        } else if let index = runs.firstIndex(where: { $0.id == run.id }) {
            // One of ours, recorded before it kept distance per zone. Its own
            // splits and zone seconds stay — they were measured live and are
            // the better record.
            runs[index].zoneDistanceKm = detail.zoneDistanceKm
            runs[index].gradeAdjustedSecPerKm = detail.gradeAdjustedSecPerKm
        }
    }

    // MARK: - Rebuilding the whole log from Health

    /// How far a full rebuild has got, for the sheet that shows it.
    struct Rebuild: Equatable {
        var done: Int
        var total: Int
        var isFinished: Bool { done >= total }
    }

    @Published private(set) var rebuild: Rebuild?
    private var rebuildTask: Task<Void, Never>?

    /// Reconstructs every run the log holds that has no measured distance per
    /// zone — all of them, not the dozen a launch does on its own.
    ///
    /// Each run costs two or three Health queries, so this is a deliberate act
    /// with its progress on screen rather than something the app does behind
    /// the runner's back.
    func rebuildEverythingFromHealth() {
        guard rebuildTask == nil else { return }
        let pending = rebuildable.sorted { $0.date > $1.date }
        rebuild = Rebuild(done: 0, total: pending.count)
        rebuildTask = Task { @MainActor [weak self] in
            for (index, run) in pending.enumerated() {
                if Task.isCancelled { break }
                await self?.hydrate(run, force: true)
                self?.rebuild = Rebuild(done: index + 1, total: pending.count)
            }
            self?.rebuildTask = nil
        }
    }

    func cancelRebuild() {
        rebuildTask?.cancel()
        rebuildTask = nil
    }

    /// Cleared when the sheet is dismissed, so the row goes back to offering
    /// the rebuild rather than reporting the last one forever.
    func clearRebuild() {
        guard rebuildTask == nil else { return }
        rebuild = nil
    }

    /// How many runs a rebuild would still have to fetch.
    var runsAwaitingRebuild: Int { rebuildable.count }

    /// Runs with no measured distance per zone that have not already been
    /// asked about this session.
    ///
    /// The second half matters: a run whose workout Health no longer holds, or
    /// one that never had a route, can never gain the measurement — without
    /// this it would sit in the count for ever and the button would promise
    /// something it cannot deliver.
    private var rebuildable: [Run] {
        allRuns.filter {
            ($0.zoneDistanceKm == nil || $0.gradeAdjustedSecPerKm == nil)
                && !hydratedImported.contains($0.id)
        }
    }

    /// Fills in what Health can still tell us about imported runs, a few at a
    /// time and newest first.
    ///
    /// The zone-2 chart counts only runs whose zone distance was measured, so
    /// without this it would fill in one run at a time as detail screens
    /// happened to be opened — a chart that changes shape because you went
    /// looking at an old run. Bounded per launch, because each run costs two
    /// Health queries.
    func backfillImported(limit: Int = 12) async {
        guard !isDemo else { return }
        let cutoff = Calendar.current.date(byAdding: .month, value: -12, to: .now) ?? .distantPast
        let pending = importedRuns
            .filter { $0.date >= cutoff && $0.zoneDistanceKm == nil }
            .sorted { $0.date > $1.date }
            .prefix(limit)
        for run in pending { await hydrate(run) }
    }


    /// Whether Health still holds something this run does not.
    ///
    /// The sample file is asked for directly rather than through `samples(for:)`,
    /// which manufactures an empty one when the file is missing: an indoor run
    /// has no route and never will, so inferring "not fetched yet" from an
    /// empty route re-queried Health on every single visit.
    private func needsHydration(_ run: Run) -> Bool {
        guard !hydratedImported.contains(run.id) else { return false }
        guard let stored = RunSampleStore.load(run.id) else { return true }
        // A run with zones but no route is either indoors or was fetched
        // before Health granted the route type — worth one ask per session,
        // which `hydratedImported` bounds.
        return stored.route?.isEmpty ?? true
    }

    /// Imported runs already asked about in this session, route or no route.
    private var hydratedImported: Set<UUID> = []
    /// Health is asked for permission once per session, at the first hydration.
    private var askedHealth = false
    #endif

    private func storeSamples(of run: Run) {
        guard run.carriesSamples else { return }
        let samples = RunSamples(run)
        sampleCache[run.id] = samples
        guard !isDemo else { return }
        RunSampleStore.save(samples, for: run.id)
    }

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
        let merged = HealthImport.merging(fetched, with: runs).map(carryingHydratedZones)
        if merged != importedRuns { importedRuns = merged }
        await refreshHeartRateZones()
        await backfillImported()
    }

    /// A refresh re-reads each workout's *summary*, which carries no zone
    /// breakdown at all. Without this, every return to the foreground threw
    /// away the zones built from a run's heart-rate trace and the run fell
    /// back to being placed by its average heart rate.
    func carryingHydratedZones(_ run: Run) -> Run {
        guard let known = importedRuns.first(where: { $0.id == run.id }) else { return run }
        var carried = run
        if run.zoneSeconds.reduce(0, +) < 1, known.zoneSeconds.reduce(0, +) >= 1 {
            carried.zoneSeconds = known.zoneSeconds
        }
        // Same for everything else rebuilt out of Health: a refresh reads the
        // workout's summary, which has none of it.
        carried.zoneDistanceKm = run.zoneDistanceKm ?? known.zoneDistanceKm
        if run.splits.isEmpty { carried.splits = known.splits }
        return carried
    }

    /// Re-derives the zones from Health. Never touches zones the user has
    /// tuned by hand — a measured number is better than a formula, but not
    /// better than a decision.
    ///
    /// Runs on every launch and every return to the foreground: a max heart
    /// rate and a resting pulse are not settings, they are measurements that
    /// move with the runner, and zones built on last year's numbers quietly
    /// mis-describe every run recorded against them.
    @MainActor
    func refreshHeartRateZones(force: Bool = false, requestingAccess: Bool = false) async {
        guard force || zones.isAutomatic else { return }
        if requestingAccess { await HealthImport.requestAuthorization(healthStore) }
        guard let result = await HeartRateProfile.derive(healthStore) else { return }
        var updated = zones
        updated.maxHR = result.maxHR
        updated.restingHR = result.restingHR
        updated.derivation = result.derivation
        if force { updated.overrides = nil }
        guard updated != zones else { return }
        // Only news when there was something to change from, and only when the
        // app changed it by itself: the very first derivation is Currimus
        // learning the runner, and a forced recalculation is already on screen.
        if !force, zones.derivation != nil,
           let summary = HRZones.changeSummary(from: zones, to: updated) {
            // Assigned only when there is something to say: a refresh that
            // moved nothing visible must not wipe a notice the runner has not
            // read yet.
            zoneNotice = summary
        }
        zones = updated
    }
    #endif

    /// Set when a launch found the heart-rate zones had moved. Read by Home,
    /// which says so once and quietly, and cleared when it is dismissed.
    @Published var zoneNotice: String?

    /// What can honestly be said about the Apple Health connection.
    ///
    /// Not whether access was granted — Health hides read authorization by
    /// design, returning an empty result for a denied type rather than an
    /// error, precisely so that a refusal cannot be used to infer a medical
    /// condition. "Connected" is therefore not a question this app can ask.
    /// What it can report is evidence: whether anything actually came back.
    enum HealthAccess: Equatable {
        case unavailable
        case reading(runs: Int)
        case nothingRead
    }

    var healthAccess: HealthAccess {
        #if canImport(HealthKit)
        guard HealthImport.isAvailable else { return .unavailable }
        return importedRuns.isEmpty ? .nothingRead : .reading(runs: importedRuns.count)
        #else
        return .unavailable
        #endif
    }

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
        // A deleted run must not leave its track behind — but an imported
        // run's track was fetched from Health and cached here too, and it is
        // not in `runs`. Pruning against the owned list alone deleted it on
        // the next save.
        let live = Set(runs.map(\.id)).union(importedRuns.map(\.id))
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
        // On the io queue, not here. This fires on every single toggle in
        // Settings, and a JSON encode plus three synchronous `UserDefaults`
        // writes on the main thread is precisely the work that makes a switch
        // stutter under the finger. The queue is serial, so the order the
        // settings were changed in is the order they land in; the widget reads
        // them on its own tick and cannot tell the difference. Demo builds
        // included — the widget has no other way to learn the goal.
        nonisolated(unsafe) let defaults = self.defaults
        let settings = watchSettings
        let goal = weeklyGoalKm
        let accuracy = gpsAccuracy.rawValue
        Self.ioQueue.async {
            do {
                defaults.set(try JSONEncoder().encode(settings), forKey: AppDefaults.settingsKey)
            } catch {
                Log.store.error("could not save settings: \(error.localizedDescription, privacy: .public)")
            }
            defaults.set(goal, forKey: AppDefaults.goalKey)
            defaults.set(accuracy, forKey: AppDefaults.gpsAccuracyKey)
        }
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
                zoneCoachTarget = s.zoneCoachTarget
            } catch {
                Log.store.error("settings unreadable: \(error.localizedDescription, privacy: .public)")
            }
        }
        if defaults.object(forKey: AppDefaults.goalKey) != nil {
            weeklyGoalKm = defaults.double(forKey: AppDefaults.goalKey)
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
            alwaysOnReduced: alwaysOnReduced,
            zoneCoachTarget: zoneCoachTarget
        )
    }

    private func pushSettings() {
        guard !isLoading else { return }
        #if os(iOS)
        // `updateApplicationContext` is a synchronous hop to another process,
        // and it sat on the main thread behind every toggle.
        let settings = watchSettings
        Self.ioQueue.async { RunSync.shared.send(settings: settings) }
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
        zoneCoachTarget = settings.zoneCoachTarget
        isLoading = false
        persistSettings()
        #endif
    }

    // MARK: - Aggregates

    private var calendar: Calendar { Calendar.current }
    /// Weeks are Monday-first everywhere, whatever the device's locale says.
    private var weekCalendar: Calendar { .runWeek }

    func runs(inWeekOf date: Date = .now) -> [Run] {
        allRuns.filter { weekCalendar.isDate($0.date, equalTo: date, toGranularity: .weekOfYear) }
    }

    func runs(inMonthOf date: Date) -> [Run] {
        allRuns.filter { calendar.isDate($0.date, equalTo: date, toGranularity: .month) }
    }

    var weekKm: Double { runs(inWeekOf: .now).reduce(0) { $0 + $1.distanceKm } }

    var weekGoalFraction: Double { weeklyGoalKm > 0 ? weekKm / weeklyGoalKm : 0 }

    var lastWeekKmToDate: Double {
        guard let lastWeek = weekCalendar.date(byAdding: .weekOfYear, value: -1, to: .now),
              let cutoff = weekCalendar.date(byAdding: .day, value: -7, to: .now) else { return 0 }
        return runs(inWeekOf: lastWeek).filter { $0.date <= cutoff }.reduce(0) { $0 + $1.distanceKm }
    }

    var monthKm: Double { runs(inMonthOf: .now).reduce(0) { $0 + $1.distanceKm } }

    /// Km per weekday of the current week, Monday first.
    var weekByDay: [Double] {
        var days = [Double](repeating: 0, count: 7)
        for run in runs(inWeekOf: .now) {
            // Weekday numbering is fixed (1 = Sun) whatever the week starts on;
            // this maps it onto the M…S slots the bars are labelled with.
            let weekday = weekCalendar.component(.weekday, from: run.date)
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
    enum LogFilter: Hashable { case all, road, trail }

    func filteredRuns(_ filter: LogFilter) -> [Run] {
        switch filter {
        case .all: return allRuns
        case .road: return allRuns.filter { !$0.isTrail }
        case .trail: return allRuns.filter { $0.isTrail }
        }
    }

    /// The strings one log row draws, computed once per log change.
    func logText(for run: Run, prTag: String?) -> LogRowText {
        if let cached = cachedLogText[run.id] { return cached }
        let built = LogRowText(run: run, prTag: prTag)
        cachedLogText[run.id] = built
        return built
    }

    func runsByMonth(_ filter: LogFilter = .all) -> [(month: Date, runs: [Run])] {
        if let cached = cachedMonths[filter] { return cached }
        let built = buildRunsByMonth(filter)
        cachedMonths[filter] = built
        return built
    }

    private func buildRunsByMonth(_ filter: LogFilter) -> [(month: Date, runs: [Run])] {
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
            guard let weekDate = weekCalendar.date(byAdding: .weekOfYear, value: -offset, to: .now) else { return nil }
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
            // Nothing set over this distance yet. Say which distance is
            // missing rather than printing an em dash that reads as a fault.
            let isTarget = race?.distance.km == km
            let days = race?.daysUntil() ?? 0
            // On the day itself, and after it, "in 0 days" is not what a
            // runner is looking at the screen to read.
            let note: String
            if isTarget, days > 0 {
                note = String(localized: "race day in \(Format.plural(days, "day", "days"))")
            } else if isTarget, days == 0 {
                note = String(localized: "race day is today")
            } else {
                note = kind.emptyHint
            }
            return RecordEntry(kind: kind, value: String(localized: "Not yet"),
                               isUnset: true, date: .now,
                               delta: note, isRaceCountdown: isTarget && days >= 0)
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

        /// Whether "NEW" is a fair thing to call it.
        ///
        /// The banner said NEW whatever the date was, so a personal best from
        /// last October announced itself as news every time the screen opened.
        /// A record does not stop being a record; it does stop being new.
        var isRecent: Bool { date > Date.now.addingTimeInterval(-60 * 86_400) }
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
            let km = Double(candidate.km)
            guard let holder = RunAnalytics.bestEffortHolder(km: km, runs: runs) else { return nil }
            let previous = RunAnalytics.bestEffortHolder(
                km: km, runs: runs.filter { $0.id != holder.run.id })?.seconds
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
        for (km, label) in [(5.0, "5K PR"), (10.0, "10K PR")] {
            if let holder = RunAnalytics.bestEffortHolder(km: km, runs: runs) {
                map[holder.run.id] = label
            }
        }
        if let longest = longestRun { map[longest.id, default: ""] = "Longest" }
        cachedHolders = map
        return map
    }

    /// Which run holds the fastest pace within its own calendar month — the
    /// log's accent color leads with "fastest this month", not a fixed
    /// threshold that meant nothing without knowing the runner's level.
    /// Trail is excluded: its pace isn't comparable to road/pacer pace, so it
    /// never earns the accent.
    var fastestPaceOfMonthHolders: Set<UUID> {
        if let cachedFastestPaceOfMonth { return cachedFastestPaceOfMonth }
        let eligible = allRuns.filter { !$0.isTrail && $0.hasUsableDistance && $0.paceSecPerKm > 0 }
        let byMonth = Dictionary(grouping: eligible) {
            calendar.dateInterval(of: .month, for: $0.date)?.start ?? $0.date
        }
        let built = Set(byMonth.values.compactMap { runs in
            runs.min { $0.paceSecPerKm < $1.paceSecPerKm }?.id
        })
        cachedFastestPaceOfMonth = built
        return built
    }

    /// Attribute a PR to the run that holds it — the same lookup the record
    /// itself came from, so the row's date always belongs to the row's time.
    private func recordDate(km: Double, in runs: [Run]) -> Date {
        RunAnalytics.bestEffortHolder(km: km, runs: runs)?.run.date ?? .now
    }
}
