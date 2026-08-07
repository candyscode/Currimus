import Foundation
import Combine
import WidgetKit
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
        // A demo store reads nothing and writes nothing: its settings are the
        // defaults, every time. See `persistSettings` for what this used to
        // cost — the short version is that a demo run inherited whatever a
        // previous debug session had left in the real app group, so the watch's
        // whole simulated run sat in zone 5 against a stray max HR of 136.
        if !self.isDemo { loadSettings() }
        #if canImport(HealthKit)
        if !self.isDemo {
            rebuildQueue.restoreSettled(
                defaults.stringArray(forKey: AppDefaults.settledRebuildsKey) ?? [])
        }
        #endif
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
    private var cachedEstimate: RunAnalytics.TrainingPrediction??
    /// The day the cached estimate was worked out on. Its training window is
    /// counted back from "now", so the answer ages even when the log does not.
    private var estimateDay: Date?
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
        cachedEstimate = nil
        estimateDay = nil
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
        // The recovery net may have got here first — same outing, different id,
        // because a run read back out of Health is identified by its workout.
        // What the watch sends is the better record of the two: it has the
        // per-kilometre splits, the live zone seconds and the climb as it was
        // measured, none of which survive in a workout summary. So it replaces
        // the recovered stand-in rather than sitting beside it.
        if let recovered = runs.firstIndex(where: { $0.recovered == true && overlaps($0, run) }) {
            Log.store.notice("watch run replaces the copy recovered from Health")
            // `remove` is local only — it does not touch Health, and it must
            // not: the workout it was recovered from is this same outing.
            remove([runs[recovered]])
        }
        storeSamples(of: run)
        // The log keeps metadata; the track and profile went to their sidecar.
        runs.insert(run.strippingSamples, at: 0)
        runs.sort { $0.date > $1.date }
        // Health may already hold the same outing from another app.
        importedRuns = HealthImport.merging(importedRuns, with: runs)
    }

    /// Two records of the same outing — the only way to pair a run that came
    /// over from the watch with the same run read back out of Health, since
    /// the two carry different identities.
    private func overlaps(_ a: Run, _ b: Run) -> Bool {
        (a.date...(a.date + a.duration)).overlaps(b.date...(b.date + b.duration))
    }

    // MARK: - Runs deleted on purpose

    /// When runs the user deleted began, so the recovery sweep does not put
    /// them back. Trimmed to the sweep's own window — past that, Health has
    /// nothing to recover them from either.
    private var deletedOutings: [Date] {
        get { (defaults.array(forKey: AppDefaults.deletedOutingsKey) as? [Date]) ?? [] }
        set { if !isDemo { defaults.set(newValue, forKey: AppDefaults.deletedOutingsKey) } }
    }

    private func remember(deleted runs: [Run]) {
        #if canImport(HealthKit)
        let cutoff = Calendar.current.date(byAdding: .day,
                                           value: -HealthImport.recoveryWindowDays,
                                           to: .now) ?? .distantPast
        deletedOutings = (deletedOutings + runs.map(\.date)).filter { $0 >= cutoff }
        #endif
    }

    private func wasDeletedOnPurpose(_ run: Run) -> Bool {
        deletedOutings.contains { HealthImport.isSameOuting(start: $0, as: run) }
    }

    /// Test seam — the recovery sweep itself needs a HealthKit store with data
    /// in it, which no simulator has; this is the decision it turns on.
    func wasDeletedOnPurposeForTesting(_ run: Run) -> Bool { wasDeletedOnPurpose(run) }

    #if os(watchOS)
    /// Gives back the GPS track of any of our own workouts in Health that was
    /// saved without one (CUR-44).
    ///
    /// Only on the watch: HealthKit lets an app attach objects to a workout it
    /// saved itself and to no other, and the watch is what saved these. Costs
    /// nothing once a run has been answered — the ids that came back settled
    /// are never asked about again.
    func restoreMissingRoutes() async {
        guard !isDemo, HealthImport.isAvailable else { return }
        var settled = Set(routesSettled)
        let candidates = RouteRepair.candidates(from: runs, settled: settled)
        guard !candidates.isEmpty else { return }
        let answered = await RouteRepair.sweep(candidates, in: healthStore)
        guard !answered.isEmpty else { return }
        settled.formUnion(answered)
        // Bounded by the log itself, so the list cannot outgrow the runs it
        // describes — the same pruning `RunSampleStore` gets.
        routesSettled = Array(settled.intersection(runs.map(\.id)))
    }

    private var routesSettled: [UUID] {
        get { (defaults.array(forKey: RouteRepair.settledKey) as? [String] ?? []).compactMap(UUID.init) }
        set { defaults.set(newValue.map(\.uuidString), forKey: RouteRepair.settledKey) }
    }
    #endif

    #if canImport(HealthKit)
    /// Files any run of ours that Apple Health holds and the log does not.
    ///
    /// The safety net under the whole watch→phone crossing (CUR-40). The watch
    /// saves the workout to Health before it attempts the transfer, so that
    /// copy exists even when nothing arrives — which is exactly what happened:
    /// a two-hour trail run sat in Apple Fitness while Currimus showed nothing.
    ///
    /// Runs on every foreground, costs one workout query, and adds nothing when
    /// the transfer worked — which is almost always.
    ///
    /// The watch runs it too, over the importer's window rather than the
    /// recovery one and without hydrating (CUR-46). Its reason is different:
    /// the watch's log holds only what *this* watch recorded and kept, while
    /// the imported list deliberately excludes everything Currimus itself
    /// recorded. A workout of ours that the local log has lost — a reinstall
    /// wipes the app group, a replaced watch never had it — therefore fell
    /// through both, and the widget's year total was short by exactly those
    /// runs while Apple Fitness listed every one of them.
    func recoverOwnRuns(since: Date? = nil, hydrating: Bool = true) async {
        guard !isDemo, HealthImport.isAvailable else { return }
        let since = since ?? Calendar.current.date(byAdding: .day,
                                                   value: -HealthImport.recoveryWindowDays,
                                                   to: .now) ?? .distantPast
        let candidates = await HealthImport.fetchOwnRuns(healthStore, since: since)
        let missing = candidates.filter { candidate in
            !runs.contains { overlaps($0, candidate) } && !wasDeletedOnPurpose(candidate)
        }
        guard !missing.isEmpty else { return }
        Log.store.notice("recovering \(missing.count) run(s) from Health that never arrived")
        for var run in missing {
            run.recovered = true
            add(run)
        }
        // What a workout summary does not carry — the route, the splits, the
        // zones — is still in Health beside it. Only where it gets drawn: the
        // watch shows no detail screen for an old run, so pulling every
        // heart-rate sample of eighteen months of them would spend a battery
        // filling screens that do not exist.
        guard hydrating else { return }
        // Re-checked each time round, because each one suspends: the watch's
        // own copy of one of these outings can arrive over WatchConnectivity in
        // between, and `add` then drops the stand-in being hydrated. Hydrating
        // it anyway writes a sidecar for a run that is no longer in any list,
        // and nothing ever comes back for it.
        for run in missing {
            guard runs.contains(where: { $0.id == run.id }) else { continue }
            await hydrate(run, force: true)
        }
    }
    #endif

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
        // Written down before anything else: the recovery sweep reads Health,
        // and Health's copy is deleted asynchronously and can refuse. Without
        // this, a run deleted on purpose would reappear on the next foreground
        // — the safety net catching something nobody dropped.
        remember(deleted: mine)
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
        // Asked, whatever comes back: background work does not ask twice in
        // one session.
        rebuildQueue.asking(run.id)
        let outcome = await HealthImport.detail(for: run, zones: zones,
                                                fallbackRoute: samples(for: run).route,
                                                in: healthStore)
        let detail: HealthImport.WorkoutDetail
        switch outcome {
        case .detail(let found):
            detail = found
        case .noWorkout:
            // Health answered and has nothing. That is final, so the rebuild
            // stops offering this one.
            settle(run.id)
            return
        case .unavailable:
            // Health could not answer — the device may still be locked, or
            // access not granted yet. Marking this as done would tell the
            // runner everything was rebuilt when nothing was, and leaving it
            // marked as *attempted* would mean nothing tries again until the
            // app is relaunched.
            rebuildQueue.couldNotAsk(run.id)
            return
        }

        // One value, written in one place. The sidecar keeps a copy because
        // the imported list is replaced wholesale on every refresh, and
        // anything living only there is one foreground from being lost —
        // which is how the zones went missing once and the grade adjustment
        // twice.
        let rebuilt = Reconstruction(
            zoneSeconds: detail.zoneSeconds.reduce(0, +) >= 1 ? detail.zoneSeconds : nil,
            zoneDistanceKm: detail.zoneDistanceKm,
            splits: detail.splits.isEmpty ? nil : detail.splits,
            gradeAdjustedSecPerKm: detail.gradeAdjustedSecPerKm,
            route: detail.route.isEmpty ? nil : detail.route
        )
        if !rebuilt.isEmpty {
            // Merged into what is on disk, never written over it. The sidecar
            // also carries the altitude series, and replacing the file
            // wholesale took the run's elevation profile with it.
            var samples = self.samples(for: run)
            samples.rebuilt = rebuilt.filling(from: samples.rebuilt)
            sampleCache[run.id] = samples
            RunSampleStore.save(samples, for: run.id)
        }
        // `applied(to:)` only ever fills gaps: a run Currimus recorded knows
        // its own zones and splits better than anything reassembled after the
        // fact.
        if let index = importedRuns.firstIndex(where: { $0.id == run.id }) {
            importedRuns[index] = rebuilt.applied(to: importedRuns[index]).strippingSamples
            // Health has now given everything it holds. If that still leaves
            // the run short — a route with no heart-rate trace beside it, or
            // no route at all to take a gradient from — no future rebuild can
            // do better, and it should stop being offered.
            if HealthRebuild.isStillShort(importedRuns[index]) { settle(run.id) }
        } else if let index = runs.firstIndex(where: { $0.id == run.id }) {
            runs[index] = rebuilt.applied(to: runs[index]).strippingSamples
            if HealthRebuild.isStillShort(runs[index]) { settle(run.id) }
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
        let pending = rebuildQueue.outstanding(in: allRuns).sorted { $0.date > $1.date }
        rebuild = Rebuild(done: 0, total: pending.count)
        rebuildTask = Task { @MainActor [weak self] in
            for (index, run) in pending.enumerated() {
                if Task.isCancelled { break }
                await self?.hydrate(run, force: true)
                // Checked again after the await: cancelling frees the slot at
                // once, so a new rebuild may already be reporting its own
                // progress by the time this step returns.
                guard !Task.isCancelled else { break }
                self?.rebuild = Rebuild(done: index + 1, total: pending.count)
            }
            // Only if it is still ours: a cancelled run may finish its last
            // step after the next rebuild has already been started.
            if !Task.isCancelled { self?.rebuildTask = nil }
        }
    }

    func cancelRebuild() {
        rebuildTask?.cancel()
        rebuildTask = nil
    }

    // MARK: - The first import

    /// What the first launch is doing, for the sheet that shows it.
    ///
    /// One state for what is really three steps — the permission sheet, the
    /// list of workouts, and then the traces behind each of them. The runner
    /// asked for one thing ("bring my runs in") and should watch one thing.
    struct FirstImport: Equatable {
        enum Stage: Equatable { case reading, filling, finished }
        var stage: Stage = .reading
        var done = 0
        var total = 0
        /// How many runs the log holds now. Zero at the end means Health
        /// answered with nothing — declined, or genuinely empty. It never says
        /// which, so the screen has to cover both.
        var imported = 0

        var isFinished: Bool { stage == .finished }
        var fraction: Double {
            switch stage {
            case .reading: return 0
            case .filling: return total > 0 ? Double(done) / Double(total) : 0
            case .finished: return 1
            }
        }
    }

    @Published private(set) var firstImport: FirstImport?
    private var firstImportTask: Task<Void, Never>?

    /// The whole of setting Currimus up: raise the Health prompt, read every
    /// running workout on the device, then fill in the heart-rate traces and
    /// GPS tracks the summaries do not carry.
    ///
    /// Deliberately the default on a fresh install rather than an offer. A
    /// runner arriving with years in Health wants their log, not an empty app
    /// and a button admitting one could be filled.
    func startFirstImport() {
        guard firstImportTask == nil else { return }
        firstImport = FirstImport()
        firstImportTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // No backfill: the full fill follows immediately with its progress
            // on screen, and doing the first dozen twice is a dozen runs of
            // Health queries spent behind a bar that has not started moving.
            await self.refreshImportedRuns(requestingAccess: true, backfilling: false)
            guard !Task.isCancelled else { return }

            let pending = self.rebuildQueue.outstanding(in: self.allRuns).sorted { $0.date > $1.date }
            self.firstImport = FirstImport(stage: .filling, done: 0, total: pending.count,
                                           imported: self.allRuns.count)
            for (index, run) in pending.enumerated() {
                if Task.isCancelled { break }
                await self.hydrate(run, force: true)
                guard !Task.isCancelled else { break }
                self.firstImport?.done = index + 1
            }
            guard !Task.isCancelled else { return }
            self.firstImport = FirstImport(stage: .finished, done: pending.count,
                                           total: pending.count, imported: self.allRuns.count)
            self.firstImportTask = nil
        }
    }

    /// Stops the fill where it is. What is already read stays read — this is
    /// not an undo, it is "that is enough for now".
    func stopFirstImport() {
        firstImportTask?.cancel()
        firstImportTask = nil
        firstImport = FirstImport(stage: .finished, done: firstImport?.done ?? 0,
                                  total: firstImport?.total ?? 0, imported: allRuns.count)
    }

    /// Dismisses the sheet. With runs in the log this is the way into the app.
    func clearFirstImport() {
        guard firstImportTask == nil else { return }
        firstImport = nil
    }

    /// Debug seam for `-import reading|filling|done|nothing`: the simulator's
    /// Health has nothing to hand over, so every real import there is finished
    /// before the sheet can be looked at.
    func setFirstImportForDebug(_ state: FirstImport?) { firstImport = state }

    /// Cleared when the sheet is dismissed, so the row goes back to offering
    /// the rebuild rather than reporting the last one forever.
    func clearRebuild() {
        guard rebuildTask == nil else { return }
        rebuild = nil
    }

    /// How many runs a rebuild would still have to fetch.
    var runsAwaitingRebuild: Int { rebuildQueue.outstanding(in: allRuns).count }

    /// Test seam: what a full-but-empty answer from Health does to the queue.
    func markUnrebuildableForTesting(_ id: UUID) { settle(id) }

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
        // Imported runs, as the name says. The manual rebuild in Settings
        // covers our own older runs as well; doing that on every foreground
        // spent two or three Health queries per run for something nobody had
        // asked for.
        let pending = rebuildQueue.next(from: importedRuns.filter { $0.date >= cutoff },
                                        limit: limit)
        for run in pending { await hydrate(run) }
    }


    /// Whether Health still holds something this run does not.
    ///
    /// The sample file is asked for directly rather than through `samples(for:)`,
    /// which manufactures an empty one when the file is missing: an indoor run
    /// has no route and never will, so inferring "not fetched yet" from an
    /// empty route re-queried Health on every single visit.
    /// Whether to put the question at all. One rule, in one place: this was
    /// three predicates read by three callers, and every bug in this path came
    /// out of changing one of them.
    private func needsHydration(_ run: Run) -> Bool { rebuildQueue.shouldAsk(run) }

    /// Who has been asked, who is finished with, and what is still
    /// outstanding — see `HealthRebuild`.
    ///
    /// Deliberately not `@Published`: `asking()` runs once per hydration, and
    /// a backfill of twelve re-rendered every observing view twelve times.
    /// Only the settled set moves the Settings count, so only `settle` below
    /// announces itself.
    private var rebuildQueue = HealthRebuild()

    /// Health answered as fully as it can for this run, and it is still short
    /// — so stop offering it, and tell the Settings row its count moved.
    ///
    /// Written to disk as well: "Health has nothing more for this run" does not
    /// stop being true overnight, and without persisting it the Settings row
    /// counted the same unrebuildable runs after every launch and offered work
    /// that could not change anything.
    private func settle(_ id: UUID) {
        objectWillChange.send()
        rebuildQueue.settle(id)
        guard !isDemo else { return }
        nonisolated(unsafe) let defaults = self.defaults
        let ids = rebuildQueue.settledIDs
        Self.ioQueue.async { defaults.set(ids, forKey: AppDefaults.settledRebuildsKey) }
    }
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
    /// `backfilling` is only turned off by the first import, which does the
    /// whole log with a progress bar of its own straight afterwards.
    func refreshImportedRuns(requestingAccess: Bool = false, backfilling: Bool = true) async {
        guard !isDemo else { return }
        if requestingAccess { await HealthImport.requestAuthorization(healthStore) }
        // Ours first. A run of ours that never made the crossing has to be back
        // in the log before the imported list is merged against it, or the same
        // outing appears twice — once as a recovery and once as "some other
        // app's run" — for the rest of that foreground.
        #if os(iOS)
        await recoverOwnRuns()
        #else
        // The watch reads back its own history rather than only the last
        // ninety days, because here recovery is what *completes the log*, not
        // what patches a failed transfer — see the note on `recoverOwnRuns`.
        await recoverOwnRuns(since: HealthImport.importWindowStart(), hydrating: false)
        #endif
        let fetched = await HealthImport.fetchRuns(healthStore)
        let merged = HealthImport.merging(fetched, with: runs).map(carryingHydratedZones)
        if merged != importedRuns { importedRuns = merged }
        await refreshHeartRateZones()
        if backfilling { await backfillImported() }
    }

    /// A refresh re-reads each workout's *summary*, which carries no zone
    /// breakdown at all. Without this, every return to the foreground threw
    /// away the zones built from a run's heart-rate trace and the run fell
    /// back to being placed by its average heart rate.
    func carryingHydratedZones(_ run: Run) -> Run {
        guard let known = importedRuns.first(where: { $0.id == run.id }) else { return run }
        // Every rebuilt field lives in one type, so this cannot fall behind
        // the next one that gets added — which is exactly how the zones went
        // missing once and the grade adjustment twice.
        return Reconstruction(of: known).applied(to: run)
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
        let isLog = key == AppDefaults.runsKey || key == AppDefaults.importedKey
        Self.ioQueue.async {
            do {
                defaults.set(try JSONEncoder().encode(value), forKey: key)
                // Once the bytes are down, and only for the two keys a widget
                // reads. Nothing asked the complications to refresh before, so
                // they redrew on their own half-hourly schedule: a run could
                // finish and the week bar not move for half an hour, and the
                // totals corrected by an import waited just as long (CUR-46).
                if isLog { WidgetCenter.shared.reloadAllTimelines() }
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
        // Demo builds excluded, like every other write.
        //
        // This used to write anyway, on the argument that the widget had no
        // other way to learn the goal. It bought nothing: `write(runs)` is
        // already skipped in demo mode, so the widget saw demo settings beside
        // real runs — a mixture of two states, worse than either. What it cost
        // was real. A `-demo 1 -zones derived` run left its injected max heart
        // rate in the app group of that simulator, and every later demo run
        // read it back: the watch's simulated run then sat in zone 5 from end
        // to end, its caption stuck on "MAX", and a snapshot reference recorded
        // in that state was a picture of a stray number.
        guard !isLoading, !isDemo else { return }
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
                // Every field `watchSettings` writes, read back. Three used to
                // be dropped here, and each one was a promise the app broke on
                // the next launch: the resting pulse (so the zones silently
                // fell from Karvonen back to a share of max), the derivation
                // (so a hand-set max was overwritten and the zones-moved
                // notice could never fire) and the always-on setting.
                zones = HRZones(maxHR: s.maxHR, overrides: s.zoneBounds,
                                restingHR: s.restingHR, derivation: s.derivation)
                zoneCoachTarget = s.zoneCoachTarget
                if let reduced = s.alwaysOnReduced { alwaysOnReduced = reduced }
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
            derivation: zones.derivation,
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
        // Including the derivation: the watch runs the same automatic refresh,
        // so without it the watch would overwrite a max the runner set on the
        // phone by hand.
        zones = HRZones(maxHR: settings.maxHR, overrides: settings.zoneBounds,
                        restingHR: settings.restingHR, derivation: settings.derivation)
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
    ///
    /// Rolling seven-day buckets ending now, not calendar weeks — and unlike
    /// every other weekly total in the app, that is the right grid here. Race
    /// readiness is "how much have I run lately", and a calendar week makes the
    /// newest bucket however many days old today happens to be: on a Monday the
    /// four bars covered 22 days, three full and one nearly empty, and the
    /// percentage beside them compared that against a full 28. The bars have
    /// always been labelled W1…now rather than by date, so they were never
    /// claiming calendar weeks in the first place.
    ///
    /// `offset` counts buckets back from now, so `windows(4).last` is the most
    /// recent seven days.
    func last4Weeks() -> [(label: String, km: Double)] {
        rolling7DayKm(buckets: 4).enumerated().map { index, km in
            (index == 3 ? "now" : "W\(index + 1)", km)
        }
    }

    var last4WeeksKm: Double { last4Weeks().reduce(0) { $0 + $1.km } }

    /// The four seven-day buckets before the four `last4Weeks` shows, summed.
    /// The same grid and directly adjacent, so the comparison has neither a
    /// hole in it nor a part-week on one side.
    var previous4WeeksKm: Double {
        rolling7DayKm(buckets: 8).prefix(4).reduce(0, +)
    }

    /// Kilometres per rolling seven-day bucket, oldest first.
    private func rolling7DayKm(buckets: Int) -> [Double] {
        let day: TimeInterval = 86_400
        let now = Date.now
        return (0..<buckets).reversed().map { offset in
            let end = now.addingTimeInterval(-Double(offset) * 7 * day)
            let start = end.addingTimeInterval(-7 * day)
            return allRuns.filter { $0.date > start && $0.date <= end }
                .reduce(0) { $0 + $1.distanceKm }
        }
    }

    // MARK: - Records & the race estimate

    /// What the last eight weeks of training say the race will take.
    ///
    /// The one estimate the app shows. Riegel's scaling of a past effort used
    /// to sit beside it under "FROM RACING" and is gone (CUR-38): two forecasts
    /// for one race left the runner to pick, and the one that reads the work
    /// done is the one worth planning around. `RunAnalytics.predict` is still
    /// there, unit-tested, for the day it is wanted back.
    ///
    /// Tanda is fitted on the marathon and says nothing about a 10 K, so it is
    /// only asked for one.
    ///
    /// Cached like every other aggregate on this screen's path — it walks every
    /// road run of the last eight weeks, and Home reads it on every body pass.
    var raceEstimate: RunAnalytics.TrainingPrediction? {
        // Outside the cache, and deliberately: this one depends on the clock
        // rather than on the log, and a race that passed midnight with the app
        // open would otherwise keep forecasting a finish it had already run.
        guard let race, !race.isPast, race.distance == .marathon else { return nil }
        let today = Calendar.current.startOfDay(for: .now)
        if let cachedEstimate, estimateDay == today { return cachedEstimate }
        let built = RunAnalytics.trainingPrediction(runs: allRuns)
        cachedEstimate = .some(built)
        estimateDay = today
        return built
    }

    /// The run that was the race, if there is one.
    ///
    /// Matched on the day and the distance rather than on anything the runner
    /// had to declare: nobody opens an app mid-race to tick a box, and a
    /// marathon in the log on marathon day is not a coincidence.
    var raceResult: Run? {
        guard let race, race.isPast else { return nil }
        return allRuns.first {
            Calendar.current.isDate($0.date, inSameDayAs: race.date)
                && $0.distanceKm >= race.distance.km * 0.95
        }
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
        /// The benchmark's distance. Not shown — it settles which record leads
        /// when one run set several on the same day, and one run usually does:
        /// a marathon also files the fastest half and the fastest kilometre
        /// inside it. The marathon is what happened that day.
        var km: Double = 0

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
        // Every benchmark, not just 5 and 10 km. Someone who has just run their
        // first marathon has set the most interesting record in the log, and
        // the banner used to headline their 10 K from March instead — the tile
        // was "your best 10K" wearing a general name (Andi, CUR-38).
        let held = RecordEntry.Kind.allCases.compactMap { kind -> (kind: RecordEntry.Kind, km: Double, holder: (run: Run, seconds: TimeInterval))? in
            guard let km = kind.km,
                  let holder = RunAnalytics.bestEffortHolder(km: km, runs: runs) else { return nil }
            return (kind, km, holder)
        }
        // Freshest first: a 10 K set last week leads over a marathon from May,
        // and the marathon leads the day it is run. Then the longest, because
        // one run holds several benchmarks at once — a first marathon also
        // holds the fastest half and the fastest kilometre *of that same run*,
        // and announcing the kilometre would be true and absurd. A 1 km record
        // set on its own day is still news and still leads.
        guard let best = held.max(by: { ($0.holder.run.date, $0.km) < ($1.holder.run.date, $1.km) })
        else { return nil }

        // Only the winner is asked what it beat: that question costs a copy of
        // the whole log and another walk of every split, and four of the five
        // answers were thrown away.
        let previous = RunAnalytics.bestEffortHolder(
            km: best.km, runs: runs.filter { $0.id != best.holder.run.id })?.seconds
        return LatestBenchmark(
            label: best.kind.label,
            value: Format.clock(best.holder.seconds),
            delta: previous.map { "\(Format.paceDelta(best.holder.seconds - $0)) vs previous" },
            date: best.holder.run.date,
            km: best.km
        )
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
