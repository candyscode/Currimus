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
}
