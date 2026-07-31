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

    func testTheRaceEstimateExistsForAMarathonBuildUp() throws {
        let store = makeStore(seeded: true)
        let estimate = try XCTUnwrap(store.raceEstimate)
        XCTAssertGreaterThan(estimate.time, 3 * 3600)
    }

    /// Tanda is fitted on the marathon and says nothing about a 10 K, so the
    /// screen must have nothing to print rather than a scaled guess (CUR-38).
    func testNoRaceEstimateForAShorterRace() {
        let store = makeStore(seeded: true)
        store.race = Race(name: "Autumn 10K", distance: .tenK,
                          date: .now.addingTimeInterval(30 * 86_400), goalTime: 45 * 60)
        XCTAssertNil(store.raceEstimate)
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

    // MARK: - What a relaunch keeps
    //
    // The suite had no test of this shape at all: every settings test checked
    // that `WatchSettings` round-trips through `JSONCoder`, which is the
    // struct's own Codable and not the question. What the store *writes* and
    // what it *reads back* were never compared, and three fields were being
    // dropped on the way in — see CUR-29. This is the test that shape of bug
    // needs, so it goes through the disk and a second store.

    /// Every setting the store owns, set, persisted, and read by a fresh store.
    func testEverySettingSurvivesARelaunch() throws {
        let first = makeStore()
        first.pacerTargetSecPerKm = 291
        first.pacerDefaultDistanceKm = RaceDistance.half.km
        first.kilometerAlert = false
        first.countdownEnabled = false
        first.weeklyGoalKm = 72
        first.gpsAccuracy = .saving
        first.alwaysOnReduced = false
        first.zoneCoachTarget = 3
        RunStore.flushPendingWrites()

        let second = makeStore()
        XCTAssertEqual(second.pacerTargetSecPerKm, 291)
        XCTAssertEqual(second.pacerDefaultDistanceKm, RaceDistance.half.km)
        XCTAssertEqual(second.kilometerAlert, false)
        XCTAssertEqual(second.countdownEnabled, false)
        XCTAssertEqual(second.weeklyGoalKm, 72)
        XCTAssertEqual(second.gpsAccuracy, .saving)
        XCTAssertEqual(second.alwaysOnReduced, false, "the always-on setting was not read back")
        XCTAssertEqual(second.zoneCoachTarget, 3)
    }

    /// A max heart rate the runner set by hand outranks the automatic refresh —
    /// and has to keep outranking it after the app has been closed.
    func testAHandSetMaxHeartRateStaysProtectedAcrossARelaunch() {
        let first = makeStore()
        first.zones = Self.derivedZones
        // What HRZonesView.setMax does.
        var manual = first.zones
        manual.maxHR = 178
        manual.overrides = nil
        manual.derivation = HRDerivation(maxSource: .manual, maxDate: nil, age: 38,
                                         restingHR: 48, restingSampleDays: 60)
        first.zones = manual
        XCTAssertFalse(first.zones.isAutomatic)
        RunStore.flushPendingWrites()

        let second = makeStore()
        XCTAssertEqual(second.zones.maxHR, 178)
        XCTAssertFalse(second.zones.isAutomatic,
                       "a hand-set max must still stop the automatic refresh after a relaunch")
        XCTAssertEqual(second.zones.derivation?.maxSource, .manual)
    }

    /// The resting pulse is what makes the zones Karvonen rather than a share
    /// of max. Losing it moved every boundary on the next launch.
    func testTheRestingPulseAndItsZonesSurviveARelaunch() {
        let first = makeStore()
        first.zones = Self.derivedZones
        let bounds = first.zones.bounds
        XCTAssertTrue(first.zones.usesReserve)
        RunStore.flushPendingWrites()

        let second = makeStore()
        XCTAssertEqual(second.zones.restingHR, 48)
        XCTAssertTrue(second.zones.usesReserve, "zones fell back to a share of max")
        XCTAssertEqual(second.zones.bounds, bounds, "the boundaries moved across a relaunch")
        XCTAssertNotNil(second.zones.derivation, "Settings can no longer say where these came from")
    }

    /// The zones-moved notice fires on the second derivation, not the first.
    /// It could never fire at all while the derivation was not persisted: the
    /// guard is `derivation != nil`, and every launch started at nil.
    func testAReloadedStoreKnowsItsZonesWereAlreadyDerived() {
        let first = makeStore()
        first.zones = Self.derivedZones
        RunStore.flushPendingWrites()

        let second = makeStore()
        XCTAssertNotNil(second.zones.derivation,
                        "without this the zone-change notice is unreachable in production")
        var moved = second.zones
        moved.maxHR = 191
        XCTAssertNotNil(HRZones.changeSummary(from: second.zones, to: moved))
    }

    /// A demo store is a fixed picture, not a window onto the real one.
    ///
    /// It used to read the shared settings and write them back, so a
    /// `-demo 1 -zones derived` run left its injected max heart rate in the app
    /// group and every later demo run inherited it — which is how the watch's
    /// simulated run came to sit in zone 5 from end to end. See CUR-31.
    func testADemoStoreNeitherReadsNorWritesTheSharedSettings() {
        let real = makeStore()
        real.zones = Self.derivedZones
        real.weeklyGoalKm = 99
        real.alwaysOnReduced = false
        RunStore.flushPendingWrites()

        let demo = RunStore(seeded: true, defaults: defaults, isDemo: true)
        XCTAssertEqual(demo.zones.maxHR, HRZones().maxHR, "demo inherited a real max HR")
        XCTAssertNil(demo.zones.derivation)
        XCTAssertEqual(demo.weeklyGoalKm, 55)
        XCTAssertTrue(demo.alwaysOnReduced)

        // And it must not have written its own defaults over the real ones.
        demo.weeklyGoalKm = 12
        demo.zones = HRZones(maxHR: 136)
        RunStore.flushPendingWrites()
        let reloaded = makeStore()
        XCTAssertEqual(reloaded.weeklyGoalKm, 99, "a demo run overwrote the real goal")
        XCTAssertEqual(reloaded.zones.maxHR, 187, "a demo run overwrote the real max HR")
    }

    private static var derivedZones: HRZones {
        HRZones(maxHR: 187, overrides: nil, restingHR: 48,
                derivation: HRDerivation(maxSource: .measured, maxDate: .now, age: 38,
                                         restingHR: 48, restingSampleDays: 60))
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
        XCTAssertEqual(store.latestBenchmark?.label, RecordEntry.Kind.tenK.label)
    }

    /// The banner used to look at 5 and 10 km only, so a first marathon — the
    /// most interesting record a log can gain — could never headline the
    /// screen (CUR-38).
    func testTheBannerLeadsWithAFirstMarathon() {
        let store = makeStore()
        store.runs = [
            run("Marathon", km: 42.2, minutes: 225, date: .now.addingTimeInterval(-86_400)),
            run("10K", km: 10, minutes: 50, date: .now.addingTimeInterval(-60 * 86_400),
                splits: Array(repeating: 300, count: 10)),
        ]
        XCTAssertEqual(store.latestBenchmark?.label, RecordEntry.Kind.marathon.label)
        XCTAssertNil(store.latestBenchmark?.delta, "a first marathon has nothing to beat")
    }

    /// A kilometre set on its own day is news and leads — the length rule only
    /// settles which of several benchmarks *one run* announces.
    func testAKilometreRecordOfItsOwnStillLeads() {
        let store = makeStore()
        store.runs = [
            run("Track session", km: 3, minutes: 12, date: .now,
                splits: [212, 240, 268]),
            run("10K", km: 10, minutes: 50, date: .now.addingTimeInterval(-60 * 86_400),
                splits: Array(repeating: 300, count: 10)),
        ]
        XCTAssertEqual(store.latestBenchmark?.label, RecordEntry.Kind.oneK.label)
    }

    /// …and the day a faster 10 K arrives, that is what it shows.
    func testAFasterBenchmarkTheNextDayTakesTheBanner() {
        let store = makeStore()
        store.runs = [
            run("Faster 10K", km: 10, minutes: 48, date: .now,
                splits: Array(repeating: 288, count: 10)),
            run("Marathon", km: 42.2, minutes: 225, date: .now.addingTimeInterval(-86_400)),
            run("10K", km: 10, minutes: 50, date: .now.addingTimeInterval(-60 * 86_400),
                splits: Array(repeating: 300, count: 10)),
        ]
        XCTAssertEqual(store.latestBenchmark?.label, RecordEntry.Kind.tenK.label)
        XCTAssertNotNil(store.latestBenchmark?.delta, "it beat the old 10 K, so say by how much")
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

    // MARK: - A recording that measured nothing

    func testARunWithoutDistanceIsNotFiled() {
        let store = makeStore()
        // The watch says "no distance, this run is not being saved" — and then
        // sent it to the phone, which filed it anyway. 0.00 km entries drag
        // every weekly pace average with them.
        store.add(run("Failed recording", km: 0, minutes: 0.5))
        XCTAssertTrue(store.runs.isEmpty)

        store.add(run("Real", km: 5, minutes: 25))
        XCTAssertEqual(store.runs.count, 1)
    }

    // MARK: - Deleting

    func testDeletingSeveralRunsAtOnceLeavesTheRest() {
        let store = makeStore()
        let day = 86_400.0
        let first = run("A", km: 5, minutes: 25, date: .now)
        let second = run("B", km: 8, minutes: 40, date: .now.addingTimeInterval(-day))
        let third = run("C", km: 12, minutes: 60, date: .now.addingTimeInterval(-2 * day))
        store.runs = [first, second, third]

        store.delete([first, third])
        XCTAssertEqual(store.runs.map(\.id), [second.id])
    }

    func testDeletingAMixedSelectionKeepsTheImportedRuns() {
        let store = makeStore()
        let mine = run("Currimus", km: 5, minutes: 25)
        let theirs = run("Fitness", km: 6, minutes: 30,
                         date: .now.addingTimeInterval(-86_400), imported: true)
        store.runs = [mine]
        store.importedRuns = [theirs]

        // Marking mode can hand over whatever is on screen; only what Currimus
        // owns may go, and the rest must survive the same call.
        store.delete([mine, theirs])
        XCTAssertTrue(store.runs.isEmpty)
        XCTAssertEqual(store.importedRuns.count, 1)
    }

    func testDeletingOnlyImportedRunsChangesNothing() {
        let store = makeStore()
        let mine = run("Currimus", km: 5, minutes: 25)
        store.runs = [mine]
        store.importedRuns = [run("Fitness", km: 6, minutes: 30, imported: true)]

        store.delete(store.importedRuns)
        XCTAssertEqual(store.runs.count, 1)
        XCTAssertEqual(store.importedRuns.count, 1)
    }

    func testHydratedZonesSurviveAHealthRefresh() {
        let store = makeStore()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var theirs = run("Fitness", km: 10, minutes: 50, date: start, imported: true)
        theirs.zoneSeconds = [0, 2400, 600, 0, 0]      // built from the trace
        store.importedRuns = [theirs]

        // What a refresh reads back is the workout's *summary*, which carries
        // no zone breakdown — the trace was never part of it. Without the
        // carry-over, every return to the foreground threw the zones away.
        var summary = theirs
        summary.zoneSeconds = [0, 0, 0, 0, 0]
        XCTAssertEqual(store.carryingHydratedZones(summary).zoneSeconds, [0, 2400, 600, 0, 0])
    }

    func testARefreshedRunKeepsItsOwnZonesWhenHealthHasThem() {
        let store = makeStore()
        var theirs = run("Fitness", km: 10, minutes: 50, imported: true)
        theirs.zoneSeconds = [0, 2400, 600, 0, 0]
        store.importedRuns = [theirs]

        // A summary that does carry zones is the newer truth and wins.
        var fresher = theirs
        fresher.zoneSeconds = [0, 1200, 1800, 0, 0]
        XCTAssertEqual(store.carryingHydratedZones(fresher).zoneSeconds, [0, 1200, 1800, 0, 0])
    }

    func testEverythingRebuiltFromHealthSurvivesARefresh() {
        let store = makeStore()
        var theirs = run("Fitness", km: 10, minutes: 50, imported: true)
        theirs.zoneSeconds = [0, 2400, 600, 0, 0]
        theirs.zoneDistanceKm = [0, 8, 2, 0, 0]
        theirs.splits = Array(repeating: 300, count: 10)
        theirs.gradeAdjustedSecPerKm = 295
        store.importedRuns = [theirs]

        // What a refresh reads back is the workout's summary: no zones, no
        // splits, no per-zone distance and no grade adjustment.
        var summary = run("Fitness", km: 10, minutes: 50, imported: true)
        summary.id = theirs.id
        let carried = store.carryingHydratedZones(summary)
        XCTAssertEqual(carried.zoneSeconds, [0, 2400, 600, 0, 0])
        XCTAssertEqual(carried.zoneDistanceKm, [0, 8, 2, 0, 0])
        XCTAssertEqual(carried.splits.count, 10)
        XCTAssertEqual(carried.gradeAdjustedSecPerKm, 295)
    }

    func testATreadmillRunIsNotWaitingForAGradeAdjustment() {
        let store = makeStore()
        // No route, so no gradients — ever. It used to sit in the rebuild
        // queue for good, eating the per-launch budget ahead of the imported
        // runs the zone-2 chart needs.
        var indoor = run("Treadmill", km: 10, minutes: 50, imported: true)
        indoor.isIndoor = true
        indoor.zoneDistanceKm = [0, 8, 2, 0, 0]
        indoor.gradeAdjustedSecPerKm = nil

        var outdoor = run("Road", km: 10, minutes: 50, imported: true)
        outdoor.zoneDistanceKm = [0, 8, 2, 0, 0]
        outdoor.gradeAdjustedSecPerKm = nil

        store.importedRuns = [indoor, outdoor]
        XCTAssertEqual(store.runsAwaitingRebuild, 1, "only the one that can still gain something")
    }

    func testARunHealthCannotEnrichStopsBeingOffered() {
        let store = makeStore()
        // A route but no heart-rate trace — a run somebody recorded without a
        // strap. Health holds the workout, answers in full, and there is still
        // no zone distance to be had. Offering a rebuild for ever would be a
        // promise the button cannot keep.
        var strapless = run("Strava", km: 10, minutes: 50, imported: true)
        strapless.zoneDistanceKm = nil
        store.importedRuns = [strapless]
        XCTAssertEqual(store.runsAwaitingRebuild, 1)

        store.markUnrebuildableForTesting(strapless.id)
        XCTAssertEqual(store.runsAwaitingRebuild, 0)
    }

    // MARK: - The first import (CUR-37)

    /// The state machine, without Health. A demo store answers every Health
    /// call with "nothing, immediately", which is precisely the shape of the
    /// path under test: the first launch has to end somewhere the runner can
    /// act on, whatever comes back.
    private func firstImportStore(seeded: Bool) -> RunStore {
        RunStore(seeded: seeded, defaults: defaults, isDemo: true)
    }

    private func waitForFirstImport(_ store: RunStore) async {
        for _ in 0..<300 {
            if store.firstImport?.isFinished == true { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("the first import never finished")
    }

    func testTheFirstImportEndsFinishedAndCountsWhatItFound() async {
        let store = firstImportStore(seeded: true)
        store.startFirstImport()
        await waitForFirstImport(store)

        XCTAssertEqual(store.firstImport?.stage, .finished)
        XCTAssertEqual(store.firstImport?.imported, store.allRuns.count)
        XCTAssertGreaterThan(store.firstImport?.imported ?? 0, 0)
    }

    /// The whole point of the screen's second state: a declined prompt and an
    /// empty Health log are indistinguishable, so both have to arrive as a
    /// finished import with nothing in it rather than as a spinner that stops.
    func testAnImportThatFindsNothingStillFinishes() async {
        let store = firstImportStore(seeded: false)
        store.startFirstImport()
        await waitForFirstImport(store)

        XCTAssertEqual(store.firstImport?.imported, 0)
        XCTAssertTrue(store.firstImport?.isFinished == true)
    }

    func testStartingTheFirstImportTwiceDoesNotRestartIt() async {
        let store = firstImportStore(seeded: true)
        store.startFirstImport()
        store.startFirstImport()
        await waitForFirstImport(store)
        XCTAssertEqual(store.firstImport?.imported, store.allRuns.count)
    }

    func testStoppingTheFirstImportLeavesItFinishedNotGone() {
        let store = firstImportStore(seeded: true)
        store.startFirstImport()
        store.stopFirstImport()

        // Stopping is "that is enough", not an undo: the sheet has to be able
        // to show a finished state and let the runner through.
        XCTAssertEqual(store.firstImport?.stage, .finished)
        XCTAssertEqual(store.firstImport?.imported, store.allRuns.count)
    }

    func testClearingTheFirstImportOnlyWorksOnceNothingIsRunning() async {
        let store = firstImportStore(seeded: true)
        store.startFirstImport()
        store.clearFirstImport()
        XCTAssertNotNil(store.firstImport, "cleared while the import was still running")

        await waitForFirstImport(store)
        store.clearFirstImport()
        XCTAssertNil(store.firstImport)
    }

    func testTheProgressFractionSurvivesAnEmptyLog() {
        XCTAssertEqual(RunStore.FirstImport(stage: .reading).fraction, 0)
        // No runs to fill in is not a division by zero and not a full bar
        // either — the bar only moves once there is something to count.
        XCTAssertEqual(RunStore.FirstImport(stage: .filling, done: 0, total: 0).fraction, 0)
        XCTAssertEqual(RunStore.FirstImport(stage: .filling, done: 3, total: 6).fraction, 0.5)
        XCTAssertEqual(RunStore.FirstImport(stage: .finished, done: 0, total: 0).fraction, 1)
    }

    // MARK: - One place per question

    func testAReconstructionOnlyEverFillsGaps() {
        var run = self.run("Own", km: 10, minutes: 50)
        run.zoneSeconds = [0, 2400, 600, 0, 0]
        run.splits = Array(repeating: 300, count: 10)

        // What the watch measured live wins over anything reassembled after
        // the fact; what it never had gets filled in.
        let rebuilt = Reconstruction(zoneSeconds: [3000, 0, 0, 0, 0],
                                     zoneDistanceKm: [0, 8, 2, 0, 0],
                                     splits: Array(repeating: 999, count: 10),
                                     gradeAdjustedSecPerKm: 290)
        let applied = rebuilt.applied(to: run)
        XCTAssertEqual(applied.zoneSeconds, [0, 2400, 600, 0, 0], "its own zones stand")
        XCTAssertEqual(applied.splits.first, 300, "its own splits stand")
        XCTAssertEqual(applied.zoneDistanceKm, [0, 8, 2, 0, 0], "and the gaps are filled")
        XCTAssertEqual(applied.gradeAdjustedSecPerKm, 290)
    }

    func testASidecarWrittenByAnEarlierBuildStillReads() throws {
        // The stored shape is flat and predates `Reconstruction`; files in
        // that shape are on real devices right now.
        let json = """
        {"altitude":[100,110],"zoneSeconds":[0,2400,600,0,0],"splits":[300,300],\
        "zoneDistanceKm":[0,8,2,0,0],"gradeAdjustedSecPerKm":290}
        """.replacingOccurrences(of: "\\\n", with: "")
        let samples = try JSONDecoder().decode(RunSamples.self, from: Data(json.utf8))
        XCTAssertEqual(samples.altitude, [100, 110])
        XCTAssertEqual(samples.rebuilt.zoneSeconds, [0, 2400, 600, 0, 0])
        XCTAssertEqual(samples.rebuilt.zoneDistanceKm, [0, 8, 2, 0, 0])
        XCTAssertEqual(samples.rebuilt.gradeAdjustedSecPerKm, 290)
        XCTAssertEqual(samples.rebuilt.splits?.count, 2)
    }

    func testASidecarRoundTripsThroughTheOldKeys() throws {
        let samples = RunSamples(altitude: [10, 20],
                                 rebuilt: Reconstruction(zoneSeconds: [1, 2, 3, 4, 5],
                                                         zoneDistanceKm: [1, 2, 3, 4, 5],
                                                         splits: [300],
                                                         gradeAdjustedSecPerKm: 295))
        let data = try JSONEncoder().encode(samples)
        let text = String(decoding: data, as: UTF8.self)
        // Written flat, so an older build could still read it back.
        XCTAssertTrue(text.contains("\"zoneDistanceKm\""), text)
        XCTAssertTrue(text.contains("\"gradeAdjustedSecPerKm\""), text)
        XCTAssertEqual(try JSONDecoder().decode(RunSamples.self, from: data), samples)
    }

    func testARebuildOnlyEverAddsToWhatTheSidecarAlreadyHolds() {
        // What a run recorded live: an altitude series and a route, no zones.
        let stored = Reconstruction(route: [Coordinate(lat: 47, lon: 11, elevation: 500, t: 0)])
        // What a later fetch from Health came back with — zones, and nothing
        // else, because the route query could not run.
        let fetched = Reconstruction(zoneSeconds: [0, 2400, 600, 0, 0])

        let merged = fetched.filling(from: stored)
        XCTAssertEqual(merged.zoneSeconds, [0, 2400, 600, 0, 0], "the new answer lands")
        XCTAssertEqual(merged.route?.count, 1, "and the old one is not written over")
    }

    func testAFreshAnswerWinsOverTheStoredOne() {
        let stored = Reconstruction(gradeAdjustedSecPerKm: 400)
        let fetched = Reconstruction(gradeAdjustedSecPerKm: 290)
        XCTAssertEqual(fetched.filling(from: stored).gradeAdjustedSecPerKm, 290)
    }

    // MARK: - Zones from another app's heart-rate trace

    /// Zones at max 190: 115 / 133 / 152 / 171.
    private var zones: HRZones { HRZones(maxHR: 190) }

    private func trace(_ readings: [(Int, TimeInterval)], from start: Date) -> [(bpm: Int, at: Date)] {
        readings.map { (bpm: $0.0, at: start.addingTimeInterval($0.1)) }
    }

    func testAHeartRateTraceBecomesTimeInZones() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        // Ten seconds apart: 120 (Z2), 120 (Z2), 160 (Z4), then the end.
        let samples = trace([(120, 0), (120, 10), (160, 20)], from: start)
        let seconds = HealthImport.zoneSeconds(from: samples, zones: zones,
                                               end: start.addingTimeInterval(30))
        XCTAssertEqual(seconds[1], 20, accuracy: 0.01, "two ten-second spans in zone 2")
        XCTAssertEqual(seconds[3], 10, accuracy: 0.01)
        XCTAssertEqual(seconds[0] + seconds[2] + seconds[4], 0, accuracy: 0.01)
    }

    func testAGapInTheTraceIsNotCountedAsTimeInTheLastZone() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        // The strap dropped for an hour between two readings.
        let samples = trace([(120, 0), (120, 3600)], from: start)
        let seconds = HealthImport.zoneSeconds(from: samples, zones: zones,
                                               end: start.addingTimeInterval(3660))
        XCTAssertEqual(seconds.reduce(0, +), 2 * HealthImport.maxSampleSpan, accuracy: 0.01,
                       "each reading stands for a minute at most, not for the silence after it")
    }

    func testATraceWithNoReadingsIsAllZeros() {
        let seconds = HealthImport.zoneSeconds(from: [], zones: zones, end: .now)
        XCTAssertEqual(seconds, [0, 0, 0, 0, 0])
    }

    // MARK: - Matching a run to its workout in Health

    func testAWorkoutStartingWithTheRunIsTheSameOuting() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let mine = run("Morning Run", km: 10, minutes: 50, date: start)
        XCTAssertTrue(HealthImport.isSameOuting(start: start, as: mine))
        // The watch stamps the run and begins the workout in the same breath,
        // so a few seconds of drift is all there ever is.
        XCTAssertTrue(HealthImport.isSameOuting(start: start.addingTimeInterval(3), as: mine))
        XCTAssertTrue(HealthImport.isSameOuting(start: start.addingTimeInterval(-3), as: mine))
    }

    func testANeighbouringWorkoutIsNotTheSameOuting() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let mine = run("Morning Run", km: 10, minutes: 50, date: start)
        // A second recording later the same morning must never be the one that
        // gets deleted — a wrong delete here is unrecoverable.
        XCTAssertFalse(HealthImport.isSameOuting(start: start.addingTimeInterval(600), as: mine))
        XCTAssertFalse(HealthImport.isSameOuting(start: start.addingTimeInterval(-600), as: mine))
    }
}
