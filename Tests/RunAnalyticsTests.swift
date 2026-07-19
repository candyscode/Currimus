import XCTest

/// Unit tests for the analytics that power the iPhone screens: race
/// prediction, records, classification, grade-adjusted pace, trends, and the
/// watch ↔ phone sync codecs. No stubs — every feature is exercised end-to-end.
final class RunAnalyticsTests: XCTestCase {

    // MARK: Riegel prediction

    func testRiegelMatchesKnownExponent() {
        // 10K in 2992 s → marathon (42.195 km) with exponent 1.06.
        let t = RunAnalytics.riegel(knownTime: 2992, knownKm: 10, targetKm: 42.195)
        let expected = 2992 * pow(42.195 / 10, 1.06)
        XCTAssertEqual(t, expected, accuracy: 0.5)
        // A marathon must take longer than 4.2× the 10K time.
        XCTAssertGreaterThan(t, 2992 * 4.2)
    }

    func testRiegelIsMonotonicInDistance() {
        let half = RunAnalytics.riegel(knownTime: 2992, knownKm: 10, targetKm: 21.0975)
        let full = RunAnalytics.riegel(knownTime: 2992, knownKm: 10, targetKm: 42.195)
        XCTAssertLessThan(half, full)
    }

    func testPredictionUsesTenKPRAndFlagsUnderTraining() {
        // A 10K PR but no long runs → under-trained marathon estimate.
        let pr = Run(date: .now, name: "10K", distanceKm: 10, duration: 2992, avgHR: 170,
                     splits: Array(repeating: 299.2, count: 10))
        let race = Race(name: "M", distance: .marathon,
                        date: Calendar.current.date(byAdding: .day, value: 42, to: .now)!,
                        goalTime: 14340)
        let prediction = RunAnalytics.predict(race: race, runs: [pr])
        XCTAssertNotNil(prediction)
        XCTAssertEqual(prediction?.basisLabel, "10K PR")
        XCTAssertTrue(prediction?.underTrained ?? false)
        XCTAssertGreaterThan(prediction?.time ?? 0, 3 * 3600) // > 3h
    }

    // MARK: Records

    func testFastestWindowFindsBestConsecutiveKm() {
        // Splits with a fast 5-km stretch in the middle.
        let splits: [TimeInterval] = [340, 340, 300, 300, 300, 300, 300, 340, 340]
        let run = Run(date: .now, name: "r", distanceKm: 9, duration: splits.reduce(0,+),
                      avgHR: 150, splits: splits)
        XCTAssertEqual(try XCTUnwrap(RunAnalytics.fastestWindow(km: 5, runs: [run])), 1500, accuracy: 0.1)
        XCTAssertEqual(try XCTUnwrap(RunAnalytics.fastestWindow(km: 1, runs: [run])), 300, accuracy: 0.1)
        XCTAssertNil(RunAnalytics.fastestWindow(km: 12, runs: [run]))
    }

    func testPersonalBestsIncludeHalfFromLongEffort() {
        let long = Run(date: .now, name: "long", distanceKm: 22, duration: 22 * 330,
                       avgHR: 150, splits: Array(repeating: 330, count: 22))
        let prs = RunAnalytics.personalBests(runs: [long])
        XCTAssertNotNil(prs[21.0975])
        XCTAssertEqual(prs[21.0975]!, 330 * 21.0975, accuracy: 1)
        XCTAssertNil(prs[42.195]) // no marathon-length effort
    }

    // MARK: Classification

    func testClassificationCoversEachType() {
        let long = Run(date: .now, name: "l", distanceKm: 20, duration: 20*350, avgHR: 148,
                       splits: Array(repeating: 350, count: 20),
                       zoneSeconds: [1, 60, 20, 1, 0])
        XCTAssertEqual(long.classification, .long)

        let tempo = Run(date: .now, name: "t", distanceKm: 10, duration: 10*318, avgHR: 165,
                        splits: Array(repeating: 318, count: 10),
                        zoneSeconds: [40, 120, 300, 440, 80])
        XCTAssertEqual(tempo.classification, .tempo)

        let intervals = Run(date: .now, name: "i", distanceKm: 9, duration: 9*300, avgHR: 168,
                            splits: [334, 270, 334, 270, 334, 270, 334, 270, 300],
                            zoneSeconds: [40, 120, 200, 340, 240])
        XCTAssertEqual(intervals.classification, .intervals)

        let easy = Run(date: .now, name: "e", distanceKm: 8, duration: 8*360, avgHR: 140,
                       splits: Array(repeating: 360, count: 8),
                       zoneSeconds: [200, 1800, 700, 60, 0])
        XCTAssertEqual(easy.classification, .easy)

        var trail = easy; trail.type = .trail
        XCTAssertEqual(trail.classification, .trail)
    }

    // MARK: Grade-adjusted pace

    func testGradeAdjustedPaceIsFasterUphill() {
        let flat = Run(date: .now, name: "f", distanceKm: 10, duration: 3000, avgHR: 150,
                       climbMeters: 0, descentMeters: 0)
        let hilly = Run(date: .now, name: "h", distanceKm: 10, duration: 3000, avgHR: 150,
                        climbMeters: 400, descentMeters: 400)
        // Same raw time, but the hilly run's flat-equivalent pace is faster.
        XCTAssertLessThan(RunAnalytics.gradeAdjustedPace(hilly),
                          RunAnalytics.gradeAdjustedPace(flat))
    }

    // MARK: Trends

    func testWeeklyAvgPaceExcludesTrail() {
        let road = Run(date: .now, name: "road", distanceKm: 10, duration: 3000, avgHR: 150,
                       splits: Array(repeating: 300, count: 10))
        var trail = road; trail.type = .trail; trail.duration = 4500
        let series = RunAnalytics.weeklyAvgPace(runs: [road, trail], weeks: 1, roadOnly: true)
        XCTAssertEqual(series.last!!, 300, accuracy: 0.5) // trail excluded
    }

    // MARK: Sync codecs

    func testWatchSettingsRoundTrips() throws {
        let s = WatchSettings(pacerTargetSecPerKm: 315, pacerDefaultDistanceKm: 10,
                              kilometerAlert: true, countdownEnabled: false,
                              maxHR: 188, zoneBounds: [114, 132, 151, 170])
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(WatchSettings.self, from: data)
        XCTAssertEqual(s, back)
    }

    func testRunDecodesLegacyJSONWithoutNewFields() throws {
        // A run encoded before altitudeSamples/route existed must still decode.
        let legacy = """
        {"id":"\(UUID().uuidString)","date":0,"type":"quick","name":"Old",
         "distanceKm":10,"duration":3000,"avgHR":150,"splits":[],"zoneSeconds":[0,0,0,0,0]}
        """.data(using: .utf8)!
        let run = try JSONDecoder().decode(Run.self, from: legacy)
        XCTAssertEqual(run.distanceKm, 10)
        XCTAssertNil(run.altitudeSamples)
        XCTAssertNil(run.route)
    }

    func testRunRoundTripsWithRouteAndAltitude() throws {
        let run = Run(date: .now, name: "r", distanceKm: 5, duration: 1500, avgHR: 150,
                      altitudeSamples: [100, 110, 105],
                      route: [Coordinate(lat: 48.0, lon: 7.8, elevation: 100, t: 0)])
        let data = try JSONEncoder().encode(run)
        let back = try JSONDecoder().decode(Run.self, from: data)
        XCTAssertEqual(back.route?.count, 1)
        XCTAssertEqual(back.altitudeSamples?.count, 3)
    }

    // MARK: Race

    func testRaceRequiredPaceAndDays() {
        let date = Calendar.current.date(byAdding: .day, value: 10, to: Calendar.current.startOfDay(for: .now))!
        let race = Race(name: "M", distance: .marathon, date: date, goalTime: 14340)
        XCTAssertEqual(race.daysUntil(), 10)
        XCTAssertEqual(race.requiredPace, 14340 / 42.195, accuracy: 0.01)
    }
}
