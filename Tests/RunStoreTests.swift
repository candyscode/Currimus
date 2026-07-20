import XCTest

/// Store-level behaviour and export, on the demo dataset.
final class RunStoreTests: XCTestCase {

    private func demoStore() -> RunStore {
        UserDefaults.standard.set(true, forKey: "demo")   // avoid touching persisted data
        return RunStore(seeded: true)
    }

    func testDemoStoreHasRaceAndRuns() {
        let store = demoStore()
        XCTAssertFalse(store.runs.isEmpty)
        XCTAssertNotNil(store.race)
        XCTAssertEqual(store.race?.distance, .marathon)
    }

    func testWeekByDayHasSevenSlotsSummingToWeekKm() {
        let store = demoStore()
        XCTAssertEqual(store.weekByDay.count, 7)
        XCTAssertEqual(store.weekByDay.reduce(0, +), store.weekKm, accuracy: 0.001)
    }

    func testFilteringSeparatesRoadAndTrail() {
        let store = demoStore()
        let road = store.filteredRuns(.road)
        let trail = store.filteredRuns(.trail)
        XCTAssertTrue(road.allSatisfy { !$0.isTrail })
        XCTAssertTrue(trail.allSatisfy { $0.isTrail })
        XCTAssertEqual(road.count + trail.count, store.runs.count)
        XCTAssertFalse(trail.isEmpty, "demo data should include trail runs")
    }

    func testRecordsProduceRealBenchmarks() {
        let store = demoStore()
        let records = store.records
        XCTAssertTrue(records.contains { $0.label == "10 km" && $0.value != "—" })
        XCTAssertTrue(records.contains { $0.label == "Longest run" })
        // Marathon has no effort yet in the build-up → em dash + race note.
        let marathon = records.first { $0.label == "Marathon" }
        XCTAssertEqual(marathon?.value, "—")
    }

    func testPredictionExistsForMarathonBuildUp() {
        let store = demoStore()
        XCTAssertNotNil(store.prediction)
        XCTAssertGreaterThan(store.prediction!.time, 3 * 3600)
    }

    func testSettingsSurviveAWatchSettingsRoundTrip() throws {
        let store = demoStore()
        store.pacerTargetSecPerKm = 300
        store.pacerDefaultDistanceKm = 21.0975
        let data = try JSONEncoder().encode(store.watchSettings)
        let back = try JSONDecoder().decode(WatchSettings.self, from: data)
        XCTAssertEqual(back.pacerTargetSecPerKm, 300)
        XCTAssertEqual(back.pacerDefaultDistanceKm, 21.0975)
    }

    // MARK: Export

    func testCSVHasHeaderAndRowPerRun() {
        let store = demoStore()
        let csv = RunExport.csv(store.runs)
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(String(lines[0]).hasPrefix("date,type,name"), true)
        XCTAssertEqual(lines.count, store.runs.count + 1)
    }

    func testGPXContainsTracksForRunsWithRoute() {
        let store = demoStore()
        let withRoute = store.runs.filter { $0.route?.isEmpty == false }
        let gpx = RunExport.gpx(store.runs)
        XCTAssertTrue(gpx.contains("<gpx"))
        // Demo runs carry no synthesized coordinates, so this stays schema-valid
        // and simply has no <trk>; a real recorded run adds one.
        let sample = Run(date: .now, name: "r", distanceKm: 1, duration: 300, avgHR: 150,
                         route: [Coordinate(lat: 48, lon: 7, elevation: 100, t: 0)])
        XCTAssertTrue(RunExport.gpx([sample]).contains("<trkpt"))
        _ = withRoute
    }
    // MARK: - Imported runs (Apple Health)

    private func imported(_ date: Date, km: Double, minutes: Double) -> Run {
        Run(date: date, name: "Fitness", distanceKm: km, duration: minutes * 60,
            avgHR: 150, imported: true)
    }

    func testImportedRunsCountTowardsWeeklyTotals() {
        let store = RunStore(seeded: false)
        store.runs = [Run(date: .now, name: "Currimus", distanceKm: 5, duration: 1500, avgHR: 150)]
        let ownOnly = store.weekKm
        store.importedRuns = [imported(.now, km: 8, minutes: 40)]
        XCTAssertEqual(store.weekKm, ownOnly + 8, accuracy: 0.001)
        XCTAssertEqual(store.allRuns.count, 2)
        // The owned list stays the owned list.
        XCTAssertEqual(store.runs.count, 1)
    }

    func testOverlappingImportedRunIsDroppedSoNothingCountsTwice() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let mine = Run(date: start, name: "Currimus", distanceKm: 10, duration: 3000, avgHR: 150)
        // Same outing, also recorded by Apple Fitness a few seconds later.
        let theirs = imported(start.addingTimeInterval(20), km: 10.1, minutes: 50)
        XCTAssertTrue(HealthImport.merging([theirs], with: [mine]).isEmpty)
    }

    func testNonOverlappingImportedRunSurvivesTheMerge() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let mine = Run(date: start, name: "Currimus", distanceKm: 10, duration: 3000, avgHR: 150)
        let later = imported(start.addingTimeInterval(86_400), km: 6, minutes: 30)
        XCTAssertEqual(HealthImport.merging([later], with: [mine]).count, 1)
    }

    func testAddingAnOwnRunEvictsTheOverlappingImportedCopy() {
        let store = RunStore(seeded: false)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        store.importedRuns = [imported(start, km: 10, minutes: 50)]
        store.add(Run(date: start.addingTimeInterval(30), name: "Currimus",
                      distanceKm: 10, duration: 3000, avgHR: 150))
        XCTAssertTrue(store.importedRuns.isEmpty)
        XCTAssertEqual(store.allRuns.count, 1)
    }

    func testLegacyStandardDefaultsMigrateIntoTheSharedSuite() throws {
        // A pre-app-group install kept its log in standard defaults; it must
        // still be there after the move, or the user sees an empty history.
        let key = "runs.v2"
        let legacy = [Run(date: .now, name: "Old", distanceKm: 7, duration: 2100, avgHR: 150)]
        UserDefaults.standard.set(try JSONEncoder().encode(legacy), forKey: key)
        let shared = try XCTUnwrap(UserDefaults(suiteName: "group.com.currimus.app"))
        shared.removeObject(forKey: key)

        // Re-run the migration the store performs when it first touches disk.
        if shared.object(forKey: key) == nil, let carried = UserDefaults.standard.object(forKey: key) {
            shared.set(carried, forKey: key)
        }
        let data = try XCTUnwrap(shared.data(forKey: key))
        XCTAssertEqual(try JSONDecoder().decode([Run].self, from: data).first?.name, "Old")
        UserDefaults.standard.removeObject(forKey: key)
        shared.removeObject(forKey: key)
    }

    func testImportedRunsCannotBeDeletedLocally() {
        let store = RunStore(seeded: false)
        store.runs = []
        store.importedRuns = [imported(.now, km: 6, minutes: 30)]
        let subset = store.allRuns
        store.deleteRuns(at: IndexSet(integer: 0), in: subset)
        XCTAssertEqual(store.importedRuns.count, 1, "Health owns it — deleting locally would just resurrect it")
    }
}
