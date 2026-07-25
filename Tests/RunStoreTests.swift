import XCTest

/// Store-level behaviour: the log, aggregates, records, export and the split
/// between metadata and samples.
///
/// Every case runs against a throwaway `UserDefaults` suite. The store used to
/// be hard-wired to `UserDefaults.standard` and to the real app group, so the
/// tests wrote into whatever was on the machine and left it there — order
/// dependence, and simulator state that outlived the run.
@MainActor
final class RunStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults.standard

    override func setUp() {
        super.setUp()
        suiteName = "com.currimus.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
        RunSampleStore.removeAll()
    }

    override func tearDown() {
        RunStore.flushPendingWrites()
        defaults.removePersistentDomain(forName: suiteName)
        RunSampleStore.removeAll()
        super.tearDown()
    }

    /// A store on the scratch suite. `seeded` fills it with the demo log;
    /// either way it really persists, because that is what is under test.
    private func makeStore(seeded: Bool = false) -> RunStore {
        RunStore(seeded: seeded, defaults: defaults, isDemo: false)
    }

    private func run(_ name: String, km: Double, minutes: Double,
                     date: Date = .now, splits: [TimeInterval] = [],
                     imported: Bool? = nil) -> Run {
        Run(date: date, name: name, distanceKm: km, duration: minutes * 60,
            avgHR: 150, splits: splits, imported: imported)
    }

    // MARK: - Demo log

    func testDemoStoreHasRaceAndRuns() {
        let store = makeStore(seeded: true)
        XCTAssertFalse(store.runs.isEmpty)
        XCTAssertEqual(store.race?.distance, .marathon)
    }

    func testWeekByDayHasSevenSlotsSummingToWeekKm() {
        let store = makeStore(seeded: true)
        XCTAssertEqual(store.weekByDay.count, 7)
        XCTAssertEqual(store.weekByDay.reduce(0, +), store.weekKm, accuracy: 0.001)
    }

    func testFilteringSeparatesRoadAndTrail() {
        let store = makeStore(seeded: true)
        let road = store.filteredRuns(.road)
        let trail = store.filteredRuns(.trail)
        XCTAssertTrue(road.allSatisfy { !$0.isTrail })
        XCTAssertTrue(trail.allSatisfy { $0.isTrail })
        XCTAssertEqual(road.count + trail.count, store.runs.count)
        XCTAssertFalse(trail.isEmpty, "demo data should include trail runs")
    }

    func testRecordsProduceRealBenchmarks() {
        let store = makeStore(seeded: true)
        let records = store.records
        XCTAssertTrue(records.contains { $0.kind == .tenK && !$0.isUnset })
        XCTAssertTrue(records.contains { $0.kind == .longest })
        // Marathon has no effort yet in the build-up → "Not yet" + race note.
        XCTAssertEqual(store.record(.marathon)?.isUnset, true)
    }

    func testPredictionExistsForMarathonBuildUp() throws {
        let store = makeStore(seeded: true)
        let prediction = try XCTUnwrap(store.prediction)
        XCTAssertGreaterThan(prediction.time, 3 * 3600)
    }

    func testSettingsSurviveAWatchSettingsRoundTrip() throws {
        let store = makeStore(seeded: true)
        store.pacerTargetSecPerKm = 300
        store.pacerDefaultDistanceKm = 21.0975
        let data = try JSONEncoder().encode(store.watchSettings)
        let back = try JSONDecoder().decode(WatchSettings.self, from: data)
        XCTAssertEqual(back.pacerTargetSecPerKm, 300)
        XCTAssertEqual(back.pacerDefaultDistanceKm, 21.0975)
    }

    // MARK: - Aggregate caching

    func testAggregatesRefreshWhenTheLogChanges() {
        let store = makeStore()
        XCTAssertEqual(store.weekKm, 0, accuracy: 0.001)

        store.add(run("Own", km: 5, minutes: 25))
        XCTAssertEqual(store.weekKm, 5, accuracy: 0.001)
        XCTAssertEqual(store.allRuns.count, 1)

        // The aggregate cache must drop when imported runs arrive, or every
        // total on Home silently stops counting them.
        store.importedRuns = [run("Fitness", km: 3, minutes: 15, imported: true)]
        XCTAssertEqual(store.weekKm, 8, accuracy: 0.001)
        XCTAssertEqual(store.allRuns.count, 2)
    }

    func testRecordsRefreshWhenARunIsAdded() {
        let store = makeStore()
        XCTAssertEqual(store.record(.fiveK)?.isUnset, true)
        store.add(run("5K", km: 5, minutes: 25, splits: Array(repeating: 300, count: 5)))
        XCTAssertEqual(store.record(.fiveK)?.value, Format.clock(1500))
    }

    func testLatestBenchmarkPrefersTheFresherPR() {
        let store = makeStore()
        store.runs = [
            run("10K", km: 10, minutes: 50.8, date: .now.addingTimeInterval(-2 * 86_400),
                splits: Array(repeating: 305, count: 10)),
            run("5K", km: 5, minutes: 25, date: .now.addingTimeInterval(-90 * 86_400),
                splits: Array(repeating: 300, count: 5)),
        ]
        // The 5 K window is the faster one, but the 10 K PR is two days old —
        // the banner leads with what just happened.
        XCTAssertEqual(store.latestBenchmark?.label, "10K")
    }

    func testBenchmarkHoldersTagTheRightRuns() {
        let store = makeStore()
        let fast = run("Fast 5K", km: 5, minutes: 25, splits: Array(repeating: 300, count: 5))
        let slow = run("Slow 5K", km: 5, minutes: 30, date: .now.addingTimeInterval(-86_400),
                       splits: Array(repeating: 360, count: 5))
        let long = run("Long", km: 21, minutes: 120, date: .now.addingTimeInterval(-2 * 86_400))
        store.runs = [fast, slow, long]
        XCTAssertEqual(store.benchmarkHolders[fast.id], "5K PR")
        XCTAssertEqual(store.benchmarkHolders[long.id], "Longest")
        XCTAssertNil(store.benchmarkHolders[slow.id], "only the holder gets tagged")
    }

    // MARK: - Samples live outside the log

    private func trailRun(date: Date = .now) -> Run {
        Run(date: date, type: .trail, name: "Ridge", distanceKm: 8, duration: 3_600, avgHR: 150,
            climbMeters: 400,
            altitudeSamples: [200, 260, 240],
            route: [Coordinate(lat: 47, lon: 8, elevation: 200, t: 0),
                    Coordinate(lat: 47.1, lon: 8.1, elevation: 260, t: 900)])
    }

    func testSamplesLeaveTheLogAndComeBackOnDemand() {
        let store = makeStore()
        store.add(trailRun())

        // What the widget faults into memory is metadata only …
        XCTAssertNil(store.runs[0].route)
        XCTAssertNil(store.runs[0].altitudeSamples)
        XCTAssertEqual(store.runs[0].climbMeters, 400)

        // … and the detail screen still gets everything.
        let hydrated = store.hydrated(store.runs[0])
        XCTAssertEqual(hydrated.altitudeSamples, [200, 260, 240])
        XCTAssertEqual(hydrated.route?.count, 2)
    }

    func testSamplesSurviveAStoreReload() throws {
        let store = makeStore()
        store.add(trailRun())
        RunStore.flushPendingWrites()

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.runs.count, 1)
        XCTAssertEqual(reloaded.hydrated(reloaded.runs[0]).altitudeSamples, [200, 260, 240])

        // The persisted blob itself stayed light.
        let data = try XCTUnwrap(defaults.data(forKey: AppDefaults.runsKey))
        XCTAssertNil(try JSONDecoder().decode([Run].self, from: data).first?.route)
    }

    func testLegacyInlineSamplesMigrateOutOfTheLog() throws {
        // A log written before samples moved into sidecar files.
        defaults.set(try JSONEncoder().encode([trailRun()]), forKey: AppDefaults.runsKey)

        let store = makeStore()
        XCTAssertNil(store.runs.first?.altitudeSamples)
        XCTAssertEqual(store.hydrated(store.runs[0]).altitudeSamples, [200, 260, 240])

        // Rewritten on disk, not just in memory — otherwise the widget keeps
        // paying for the tracks on every single launch.
        let data = try XCTUnwrap(defaults.data(forKey: AppDefaults.runsKey))
        let stored = try JSONDecoder().decode([Run].self, from: data)
        XCTAssertNil(stored.first?.route)
        XCTAssertNil(stored.first?.altitudeSamples)
    }

    func testDeletingARunRemovesItsTrack() {
        let store = makeStore()
        store.add(trailRun())
        let id = store.runs[0].id
        XCTAssertNotNil(RunSampleStore.load(id))

        store.deleteRuns(at: IndexSet(integer: 0), in: store.allRuns)
        XCTAssertTrue(store.runs.isEmpty)
        XCTAssertNil(RunSampleStore.load(id), "a deleted run must not leave its track on disk")
    }

    // MARK: - Export

    func testCSVHasHeaderAndRowPerRun() {
        let store = makeStore(seeded: true)
        let csv = RunExport.csv(store.runs)
        let lines = csv.split(separator: "\n")
        XCTAssertTrue(String(lines[0]).hasPrefix("date,type,name"))
        XCTAssertEqual(lines.count, store.runs.count + 1)
    }

    func testGPXContainsTracksForHydratedRuns() {
        let store = makeStore()
        store.add(trailRun())
        // Straight from the log there is no track to write …
        XCTAssertFalse(RunExport.gpx(store.runs).contains("<trkpt"))
        // … so export hydrates first, exactly as Settings does.
        let gpx = RunExport.gpx(store.runs.map(store.hydrated))
        XCTAssertTrue(gpx.contains("<gpx"))
        XCTAssertTrue(gpx.contains("<trkpt"))
    }

    // MARK: - Imported runs (Apple Health)

    func testImportedRunsCountTowardsWeeklyTotals() {
        let store = makeStore()
        store.runs = [run("Currimus", km: 5, minutes: 25)]
        let ownOnly = store.weekKm
        store.importedRuns = [run("Fitness", km: 8, minutes: 40, imported: true)]
        XCTAssertEqual(store.weekKm, ownOnly + 8, accuracy: 0.001)
        XCTAssertEqual(store.allRuns.count, 2)
        // The owned list stays the owned list.
        XCTAssertEqual(store.runs.count, 1)
    }

    func testOverlappingImportedRunIsDroppedSoNothingCountsTwice() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let mine = run("Currimus", km: 10, minutes: 50, date: start)
        // Same outing, also recorded by Apple Fitness a few seconds later.
        let theirs = run("Fitness", km: 10.1, minutes: 50,
                         date: start.addingTimeInterval(20), imported: true)
        XCTAssertTrue(HealthImport.merging([theirs], with: [mine]).isEmpty)
    }

    func testNonOverlappingImportedRunSurvivesTheMerge() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let mine = run("Currimus", km: 10, minutes: 50, date: start)
        let later = run("Fitness", km: 6, minutes: 30,
                        date: start.addingTimeInterval(86_400), imported: true)
        XCTAssertEqual(HealthImport.merging([later], with: [mine]).count, 1)
    }

    func testAddingAnOwnRunEvictsTheOverlappingImportedCopy() {
        let store = makeStore()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        store.importedRuns = [run("Fitness", km: 10, minutes: 50, date: start, imported: true)]
        store.add(run("Currimus", km: 10, minutes: 50, date: start.addingTimeInterval(30)))
        XCTAssertTrue(store.importedRuns.isEmpty)
        XCTAssertEqual(store.allRuns.count, 1)
    }

    func testImportedRunsCannotBeDeletedLocally() {
        let store = makeStore()
        store.importedRuns = [run("Fitness", km: 6, minutes: 30, imported: true)]
        store.deleteRuns(at: IndexSet(integer: 0), in: store.allRuns)
        XCTAssertEqual(store.importedRuns.count, 1,
                       "Health owns it — deleting locally would just resurrect it")
    }
}
