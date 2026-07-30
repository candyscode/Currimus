import XCTest
import SwiftUI

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

    func testPredictionPrefersTheClosestBenchmarkBelowTheRace() throws {
        // A half and a 5 K, both recent. For a marathon the half is by far the
        // better witness — it used to be asked last, after the 5 K.
        let half = Run(date: .now, name: "half", distanceKm: 21.1, duration: 21.1 * 300,
                       avgHR: 165, splits: [])
        let fiveK = Run(date: .now, name: "5k", distanceKm: 5, duration: 5 * 250,
                        avgHR: 175, splits: Array(repeating: 250, count: 5))
        let race = Race(name: "M", distance: .marathon,
                        date: Calendar.current.date(byAdding: .day, value: 42, to: .now)!,
                        goalTime: 14340)
        let prediction = try XCTUnwrap(RunAnalytics.predict(race: race, runs: [half, fiveK]))
        XCTAssertEqual(prediction.basisLabel, "Half")
        XCTAssertFalse(prediction.isStale)
    }

    func testPredictionPrefersRecentFormOverAnOldPersonalBest() throws {
        let old = Run(date: .now.addingTimeInterval(-300 * 86_400), name: "fast 10k",
                      distanceKm: 10, duration: 2400, avgHR: 175,
                      splits: Array(repeating: 240, count: 10))
        let recent = Run(date: .now.addingTimeInterval(-10 * 86_400), name: "10k",
                         distanceKm: 10, duration: 3000, avgHR: 165,
                         splits: Array(repeating: 300, count: 10))
        let race = Race(name: "M", distance: .marathon,
                        date: Calendar.current.date(byAdding: .day, value: 42, to: .now)!,
                        goalTime: 14340)
        let prediction = try XCTUnwrap(RunAnalytics.predict(race: race, runs: [old, recent]))
        // The old run is faster and still a PR; the recent one describes the
        // runner who will actually start the race.
        XCTAssertFalse(prediction.isStale)
        XCTAssertGreaterThan(prediction.time,
                             RunAnalytics.riegel(knownTime: 2400, knownKm: 10, targetKm: 42.195,
                                                 exponent: 1.08))
    }

    func testAPredictionWithNothingRecentSaysSo() throws {
        let old = Run(date: .now.addingTimeInterval(-300 * 86_400), name: "10k",
                      distanceKm: 10, duration: 2992, avgHR: 170,
                      splits: Array(repeating: 299.2, count: 10))
        let race = Race(name: "M", distance: .marathon,
                        date: Calendar.current.date(byAdding: .day, value: 42, to: .now)!,
                        goalTime: 14340)
        let prediction = try XCTUnwrap(RunAnalytics.predict(race: race, runs: [old]))
        XCTAssertTrue(prediction.isStale)
        XCTAssertEqual(prediction.basisDate, old.date)
    }

    func testTheMarathonIsScaledMorePessimisticallyThanTheHalf() {
        // Riegel's 1.06 stretched from 10 K to 42 K is famously optimistic;
        // the last ten kilometres are a fuelling problem, not a scaling one.
        XCTAssertEqual(RunAnalytics.exponent(fromKm: 10, toKm: 42.195), 1.08)
        XCTAssertEqual(RunAnalytics.exponent(fromKm: 10, toKm: 21.0975), 1.06)
        // From a half, the gap is small enough for the original exponent.
        XCTAssertEqual(RunAnalytics.exponent(fromKm: 21.0975, toKm: 42.195), 1.06)
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
        XCTAssertEqual(prediction?.basisLabel, "10K")
        XCTAssertTrue(prediction?.underTrained ?? false)
        XCTAssertGreaterThan(prediction?.time ?? 0, 3 * 3600) // > 3h
    }

    // MARK: What the training says

    private func trainingRun(_ km: Double, pace: TimeInterval, daysAgo: Int) -> Run {
        Run(date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!,
            name: "run", distanceKm: km, duration: km * pace, avgHR: 150)
    }

    /// Eight weeks of running, four times a week.
    private func eightWeeks(kmPerRun: Double, pace: TimeInterval) -> [Run] {
        (0..<32).map { trainingRun(kmPerRun, pace: pace, daysAgo: $0 * 7 / 4) }
    }

    func testTheTrainingPredictionReadsVolumeAndPace() throws {
        // 4 × 15 km a week at 5:00 /km — 60 km a week.
        let prediction = try XCTUnwrap(
            RunAnalytics.trainingPrediction(runs: eightWeeks(kmPerRun: 15, pace: 300)))
        XCTAssertEqual(prediction.weeklyKm, 60, accuracy: 1)
        XCTAssertEqual(prediction.meanPaceSecPerKm, 300, accuracy: 1)
        XCTAssertFalse(prediction.isExtrapolated, "60 km a week at 5:00 is inside the fitted range")
        // 3:19:43 by hand, which is what a runner holding 5:00 /km across
        // 60 km a week is worth in this model. Assert the band, not the second.
        XCTAssertEqual(prediction.time, 11_983, accuracy: 60)
    }

    func testMoreVolumeAtTheSamePacePredictsAFasterMarathon() throws {
        let modest = try XCTUnwrap(
            RunAnalytics.trainingPrediction(runs: eightWeeks(kmPerRun: 10, pace: 300)))
        let serious = try XCTUnwrap(
            RunAnalytics.trainingPrediction(runs: eightWeeks(kmPerRun: 25, pace: 300)))
        XCTAssertLessThan(serious.time, modest.time)
    }

    func testTrainingOutsideTheStudysRangeSaysSo() throws {
        // 20 km a week is a long way under what the study covered.
        let thin = try XCTUnwrap(
            RunAnalytics.trainingPrediction(runs: eightWeeks(kmPerRun: 5, pace: 330)))
        XCTAssertTrue(thin.isExtrapolated)
    }

    func testTooFewRunsIsNotATrainingBlock() {
        let sparse = (0..<4).map { trainingRun(10, pace: 300, daysAgo: $0 * 7) }
        XCTAssertNil(RunAnalytics.trainingPrediction(runs: sparse))
    }

    func testTheMarathonLeadsWithTheMoreCautiousOfTheTwo() throws {
        // A sharp 10 K and thin training: Riegel is optimistic, Tanda is not,
        // and the screen must not lead with the flattering one.
        var runs = eightWeeks(kmPerRun: 6, pace: 330)
        runs.append(Run(date: .now, name: "10K", distanceKm: 10, duration: 2400, avgHR: 175,
                        splits: Array(repeating: 240, count: 10)))
        let race = Race(name: "M", distance: .marathon,
                        date: Calendar.current.date(byAdding: .day, value: 42, to: .now)!,
                        goalTime: 14340)
        let prediction = try XCTUnwrap(RunAnalytics.predict(race: race, runs: runs))
        let training = try XCTUnwrap(prediction.fromTraining)
        XCTAssertGreaterThan(training.time, prediction.time)
        XCTAssertEqual(prediction.headline, training.time)
    }

    func testAHalfMarathonIsNotAskedOfTheMarathonModel() throws {
        let runs = eightWeeks(kmPerRun: 15, pace: 300)
        let race = Race(name: "H", distance: .half,
                        date: Calendar.current.date(byAdding: .day, value: 42, to: .now)!,
                        goalTime: 7200)
        let prediction = try XCTUnwrap(RunAnalytics.predict(race: race, runs: runs))
        XCTAssertNil(prediction.fromTraining, "Tanda's model is fitted on the marathon")
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

    /// A run out of Apple Health has no splits, so the rolling window finds
    /// nothing in it — it has to hold a record on its distance and time alone.
    func testImportedRunWithoutSplitsStillHoldsARecord() {
        let imported = Run(date: .now, name: "Strava", distanceKm: 10, duration: 2800,
                           avgHR: 0, splits: [], imported: true)
        XCTAssertNil(RunAnalytics.fastestWindow(km: 10, runs: [imported]))

        let holder = RunAnalytics.bestEffortHolder(km: 10, runs: [imported])
        XCTAssertEqual(holder?.run.id, imported.id)
        XCTAssertEqual(try XCTUnwrap(holder?.seconds), 2800, accuracy: 1)
    }

    /// The scaled reading is a fallback, never a promotion: a genuine window
    /// inside a run has to win when it is faster.
    func testRealWindowBeatsScaledEstimate() {
        let splits: [TimeInterval] = [340, 340, 280, 280, 280, 280, 280, 340, 340, 340]
        let recorded = Run(date: .now, name: "own", distanceKm: 10,
                           duration: splits.reduce(0, +), avgHR: 150, splits: splits)
        let window = try? XCTUnwrap(RunAnalytics.fastestWindow(km: 5, runs: [recorded]))
        let holder = RunAnalytics.bestEffortHolder(km: 5, runs: [recorded])
        XCTAssertEqual(try XCTUnwrap(holder?.seconds), try XCTUnwrap(window), accuracy: 0.1)
        XCTAssertLessThan(try XCTUnwrap(holder?.seconds), recorded.paceSecPerKm * 5)
    }

    /// Average pace over a marathon says something about a half and nothing
    /// worth claiming about a kilometre.
    func testLongRunDoesNotSetShortBenchmarks() {
        let marathon = Run(date: .now, name: "M", distanceKm: 42.2, duration: 42.2 * 330,
                           avgHR: 150, splits: [], imported: true)
        let prs = RunAnalytics.personalBests(runs: [marathon])
        XCTAssertNotNil(prs[42.195])
        XCTAssertNotNil(prs[21.0975])
        XCTAssertNil(prs[1])
        XCTAssertNil(prs[5])
        XCTAssertNil(prs[10])
    }

    /// A run that falls short of the benchmark must not be filed as one.
    func testShortRunIsNotABenchmark() {
        let short = Run(date: .now, name: "s", distanceKm: 4.6, duration: 4.6 * 300,
                        avgHR: 150, splits: [], imported: true)
        XCTAssertNil(RunAnalytics.bestEffortHolder(km: 5, runs: [short]))
    }

    func testPersonalBestsIncludeHalfFromLongEffort() {
        let long = Run(date: .now, name: "long", distanceKm: 22, duration: 22 * 330,
                       avgHR: 150, splits: Array(repeating: 330, count: 22))
        let prs = RunAnalytics.personalBests(runs: [long])
        XCTAssertNotNil(prs[21.0975])
        XCTAssertEqual(prs[21.0975]!, 330 * 21.0975, accuracy: 1)
        XCTAssertNil(prs[42.195]) // no marathon-length effort
    }

    // MARK: Grade-adjusted pace

    private func trailRun(km: Double, pace: TimeInterval, climb: Double?) -> Run {
        Run(date: .now, type: .trail, name: "t", distanceKm: km, duration: km * pace,
            avgHR: 150, climbMeters: climb, descentMeters: climb.map { $0 * 0.5 })
    }

    /// A short jog and a long mountain day are not equal evidence. Weighting
    /// by distance is what "average pace across these runs" means.
    func testGradeAdjustedSummaryIsWeightedByDistance() {
        let short = trailRun(km: 2, pace: 600, climb: 100)
        let long = trailRun(km: 30, pace: 400, climb: 1000)
        let summary = try? XCTUnwrap(RunAnalytics.gradeAdjustedSummary(runs: [short, long]))
        let expectedRaw = (short.duration + long.duration) / 32
        XCTAssertEqual(try XCTUnwrap(summary?.raw), expectedRaw, accuracy: 0.5)
        // The unweighted mean of the two paces would be 500; the long run has
        // to dominate.
        XCTAssertLessThan(try XCTUnwrap(summary?.raw), 450)
    }

    /// Runs with no elevation recorded make the adjustment the identity, so
    /// including them only dilutes the difference the row exists to show.
    func testGradeAdjustedSummarySkipsRunsWithoutClimb() {
        let flat = trailRun(km: 10, pace: 400, climb: nil)
        XCTAssertNil(RunAnalytics.gradeAdjustedSummary(runs: [flat]))

        let climbed = trailRun(km: 10, pace: 400, climb: 500)
        let summary = try? XCTUnwrap(RunAnalytics.gradeAdjustedSummary(runs: [flat, climbed]))
        XCTAssertEqual(try XCTUnwrap(summary?.raw), 400, accuracy: 0.5)
        XCTAssertLessThan(try XCTUnwrap(summary?.adjusted), 400)   // climbing explains the pace
    }

    // MARK: Grade-adjusted pace, from the gradients themselves

    func testFlatGroundCostsExactlyWhatItSays() {
        XCTAssertEqual(RunAnalytics.gradeCostFactor(0), 1.0, accuracy: 0.001)
    }

    func testClimbingCostsMoreAndDescendingLess() {
        // A 10 % climb is far dearer than the flat; a gentle descent is
        // cheaper — which is the shape Minetti measured.
        XCTAssertGreaterThan(RunAnalytics.gradeCostFactor(0.10), 1.5)
        XCTAssertLessThan(RunAnalytics.gradeCostFactor(-0.10), 1.0)
        // And a steep descent stops being a bargain again.
        XCTAssertGreaterThan(RunAnalytics.gradeCostFactor(-0.40),
                             RunAnalytics.gradeCostFactor(-0.20))
    }

    func testTheCurveIsClampedToWhatWasActuallyMeasured() {
        XCTAssertEqual(RunAnalytics.gradeCostFactor(0.9), RunAnalytics.gradeCostFactor(0.45))
        XCTAssertEqual(RunAnalytics.gradeCostFactor(-0.9), RunAnalytics.gradeCostFactor(-0.45))
    }

    func testAFlatRouteIsItsOwnGradeAdjustedPace() throws {
        // Fifteen minutes at 5:00 /km on the level.
        let route = straightRoute(seconds: 900)
        let gap = try XCTUnwrap(RunAnalytics.gradeAdjustedPace(route: route, duration: 900))
        XCTAssertEqual(gap, 300, accuracy: 6)
    }

    func testAClimbIsWorthAFasterPaceOnTheFlat() throws {
        // The same 5:00 /km, but 8 % uphill throughout: the effort was worth
        // considerably more than 5:00 on the level.
        let climbing = straightRoute(seconds: 900).map {
            Coordinate(lat: $0.lat, lon: $0.lon,
                       elevation: $0.t * (1000.0 / 300.0) * 0.08, t: $0.t)
        }
        let gap = try XCTUnwrap(RunAnalytics.gradeAdjustedPace(route: climbing, duration: 900))
        XCTAssertLessThan(gap, 300 / 1.4)
    }

    func testATreadmillRunIsMeasuredFromItsDistanceSamples() throws {
        // No GPS at all: ten minutes, a kilometre every five, easy for the
        // first half and hard for the second.
        let trace: [RunAnalytics.DistancePoint] =
            stride(from: 0, through: 600, by: 30).map { (km: Double($0) / 300, at: TimeInterval($0)) }
        let heartRate: [(bpm: Int, at: TimeInterval)] =
            stride(from: 0, through: 600, by: 10).map { (bpm: $0 < 300 ? 125 : 160, at: TimeInterval($0)) }

        let distance = try XCTUnwrap(
            RunAnalytics.zoneDistanceKm(trace: trace, heartRate: heartRate, zones: testZones))
        XCTAssertEqual(distance[1], 1.0, accuracy: 0.05)
        XCTAssertEqual(distance[3], 1.0, accuracy: 0.05)

        // And its splits, so an indoor run can hold a record like any other.
        let splits = RunAnalytics.splits(trace: trace)
        XCTAssertEqual(splits.count, 2)
        XCTAssertEqual(splits[0], 300, accuracy: 5)
    }

    func testWithoutATrackThereIsNoGradientToRead() {
        XCTAssertNil(RunAnalytics.gradeAdjustedPace(route: [], duration: 900))
    }

    // MARK: Cardiac drift

    private func easyRun(_ pace: TimeInterval, hr: Int, daysAgo: Int) -> Run {
        Run(date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!,
            name: "easy", distanceKm: 10, duration: 10 * pace, avgHR: hr,
            splits: Array(repeating: pace, count: 10),
            zoneSeconds: [60, 3000, 300, 0, 0])
    }

    func testReferencePaceIsTheRunnersOwnMedian() {
        let runs = [330.0, 350, 360, 370, 380].enumerated().map {
            easyRun($0.element, hr: 150, daysAgo: $0.offset * 7)
        }
        // Median of the five is 360, and it snaps to the nearest five seconds.
        XCTAssertEqual(try XCTUnwrap(RunAnalytics.referencePace(runs: runs)), 360, accuracy: 0.1)
    }

    func testReferencePaceNeedsEnoughSteadyRuns() {
        let runs = [easyRun(330, hr: 150, daysAgo: 0), easyRun(340, hr: 150, daysAgo: 7)]
        XCTAssertNil(RunAnalytics.referencePace(runs: runs))
    }

    /// A slow runner used to see nothing here at all: the reference was
    /// pinned at 5:30 and none of their runs came within twenty seconds.
    func testDriftIsFoundForARunnerNowhereNearFiveThirty() {
        let runs = (0..<6).map { easyRun(420 + Double($0 % 2) * 5, hr: 160 - $0, daysAgo: $0 * 7) }
        let reference = try? XCTUnwrap(RunAnalytics.referencePace(runs: runs))
        XCTAssertEqual(try XCTUnwrap(reference), 425, accuracy: 5)
        XCTAssertNil(RunAnalytics.hrAtPace(runs: runs, referencePaceSec: 330))
        XCTAssertNotNil(RunAnalytics.hrAtPace(runs: runs,
                                              referencePaceSec: try XCTUnwrap(reference)))
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

    // MARK: Zone-2 pace

    /// Zones at max 190 without a resting rate: 115 / 133 / 152 / 171, so
    /// zone 2 is 116–133 bpm.
    private var testZones: HRZones { HRZones(maxHR: 190) }

    private func zoneRun(_ seconds: [TimeInterval], avgHR: Int = 0,
                         km: Double = 10, duration: TimeInterval = 3000,
                         perZoneKm: [Double]? = nil, date: Date = .now) -> Run {
        Run(date: date, name: "run", distanceKm: km, duration: duration,
            avgHR: avgHR, zoneSeconds: seconds, zoneDistanceKm: perZoneKm)
    }

    // MARK: … reconstructed from a route and a heart-rate trace

    /// A straight line east at the equator, one point per second, at a
    /// constant 5:00 /km — 3.333 m per second.
    private func straightRoute(seconds: Int, metresPerSecond: Double = 1000.0 / 300.0) -> [Coordinate] {
        // One degree of longitude at the equator is 111.32 km.
        let degreesPerMetre = 1 / 111_320.0
        return (0...seconds).map { t in
            Coordinate(lat: 0, lon: Double(t) * metresPerSecond * degreesPerMetre,
                       elevation: 0, t: TimeInterval(t))
        }
    }

    func testDistancePerZoneIsPairedBackFromTheRouteAndTheTrace() throws {
        // Ten minutes: the first five in zone 2 (125 bpm), the last five in
        // zone 4 (160 bpm), at a steady 5:00 /km throughout.
        let route = straightRoute(seconds: 600)
        let trace: [(bpm: Int, at: TimeInterval)] =
            stride(from: 0, through: 600, by: 10).map { (bpm: $0 < 300 ? 125 : 160, at: TimeInterval($0)) }
        let distance = try XCTUnwrap(
            RunAnalytics.zoneDistanceKm(route: route, heartRate: trace, zones: testZones))
        XCTAssertEqual(distance[1], 1.0, accuracy: 0.05, "five minutes at 5:00 /km is a kilometre")
        XCTAssertEqual(distance[3], 1.0, accuracy: 0.05)
        XCTAssertEqual(distance[0] + distance[2] + distance[4], 0, accuracy: 0.001)
    }

    func testAGapInTheTrackIsNotAttributedToAnyZone() throws {
        // Two minutes of running, a five-minute pause, two more minutes.
        var route = straightRoute(seconds: 120)
        let resumed = straightRoute(seconds: 120).map {
            Coordinate(lat: 0, lon: $0.lon + 0.01, elevation: 0, t: $0.t + 420)
        }
        route.append(contentsOf: resumed)
        let trace: [(bpm: Int, at: TimeInterval)] =
            stride(from: 0, through: 540, by: 10).map { (bpm: 125, at: TimeInterval($0)) }
        let distance = try XCTUnwrap(
            RunAnalytics.zoneDistanceKm(route: route, heartRate: trace, zones: testZones))
        // Four minutes of actual running, not four minutes plus a kilometre of
        // teleportation across the pause.
        XCTAssertEqual(distance[1], 0.8, accuracy: 0.05)
    }

    func testARunWithoutOneHalfOrTheOtherCannotBeMeasured() {
        let route = straightRoute(seconds: 300)
        XCTAssertNil(RunAnalytics.zoneDistanceKm(route: route, heartRate: [], zones: testZones))
        XCTAssertNil(RunAnalytics.zoneDistanceKm(route: [], heartRate: [(bpm: 125, at: 0)],
                                                 zones: testZones))
    }

    func testSplitsAreRecoveredFromTheRoute() {
        // A little over fifteen minutes at 5:00 /km, so the third kilometre
        // mark is genuinely crossed rather than landed on.
        let splits = RunAnalytics.splits(fromRoute: straightRoute(seconds: 920))
        XCTAssertEqual(splits.count, 3)
        for split in splits {
            XCTAssertEqual(split, 300, accuracy: 6, "each kilometre took five minutes")
        }
    }

    func testARecoveredSplitFindsTheFastKilometreInsideALongerRun() throws {
        // Two kilometres at 5:00, then one at 4:00 — the fastest kilometre is
        // the last one, and a whole-run average would never show it.
        var route = straightRoute(seconds: 600)
        let handover = route[route.count - 1]
        let fast = straightRoute(seconds: 260, metresPerSecond: 1000.0 / 240.0).map {
            Coordinate(lat: 0, lon: handover.lon + $0.lon, elevation: 0, t: handover.t + $0.t)
        }
        route.append(contentsOf: fast.dropFirst())
        let splits = RunAnalytics.splits(fromRoute: route)
        XCTAssertGreaterThanOrEqual(splits.count, 3)
        XCTAssertEqual(splits[0], 300, accuracy: 6)
        XCTAssertEqual(splits[1], 300, accuracy: 6)
        XCTAssertEqual(splits[2], 240, accuracy: 8, "the fast kilometre, found inside the run")
    }

    // MARK: … measured, when the run recorded it

    func testAMeasuredRunContributesOnlyItsZoneTwoPortion() throws {
        // 40 minutes and 8 km of the run were zone 2; the rest was harder.
        let run = zoneRun([0, 2400, 1200, 0, 0], km: 12, duration: 3600,
                          perZoneKm: [0, 8, 4, 0, 0])
        let effort = try XCTUnwrap(RunAnalytics.effort(of: run, inZone: 2, zones: testZones))
        XCTAssertEqual(effort.km, 8, accuracy: 0.001)
        XCTAssertEqual(effort.seconds, 2400, accuracy: 0.001)
        // 5:00 /km in zone 2, against 5:00 for the whole run only by accident
        // — what matters is that the zone-3 kilometres are not in it.
        XCTAssertEqual(effort.pace, 300, accuracy: 0.5)
    }

    func testAMeasuredRunWithNoZoneTwoInItContributesNothing() {
        let run = zoneRun([0, 0, 1800, 1200, 0], km: 10, duration: 3000,
                          perZoneKm: [0, 0, 6, 4, 0])
        XCTAssertNil(RunAnalytics.effort(of: run, inZone: 2, zones: testZones))
    }

    func testAFewSecondsInAZoneIsNotAContribution() {
        // Passing through zone 2 on the way to zone 4 is not zone-2 running.
        let run = zoneRun([0, 20, 0, 2980, 0], km: 10, duration: 3000,
                          perZoneKm: [0, 0.05, 0, 9.95, 0])
        XCTAssertNil(RunAnalytics.effort(of: run, inZone: 2, zones: testZones))
    }

    // MARK: … approximated, when it did not

    func testARunThatWasNotMeasuredDoesNotCountAtAll() {
        // 70 % of its time in zone 2, but no per-zone distance: it used to
        // count whole, at the pace of the *whole* run — an estimate sitting on
        // a chart that cannot show its own uncertainty.
        let easy = zoneRun([200, 2100, 700, 0, 0])
        XCTAssertNil(RunAnalytics.effort(of: easy, inZone: 2, zones: testZones))
        // It is still counted as having been there, so the screen can say how
        // many runs it left out.
        XCTAssertTrue(RunAnalytics.spentTime(easy, inZone: 2))
        XCTAssertFalse(RunAnalytics.spentTime(easy, inZone: 5))
    }

    func testAnUnmeasurableRunIsReportedRatherThanSilentlyDropped() throws {
        let now = Date()
        let measured = zoneRun([0, 3000, 0, 0, 0], km: 10, duration: 3000,
                               perZoneKm: [0, 10, 0, 0, 0], date: now)
        let treadmill = zoneRun([0, 2400, 600, 0, 0], km: 8, duration: 3000, date: now)
        let months = RunAnalytics.monthlyZonePace(runs: [measured, treadmill], zone: 2,
                                                  zones: testZones, months: 1, now: now)
        let month = try XCTUnwrap(months.last)
        XCTAssertEqual(month.runs, 1)
        XCTAssertEqual(month.unmeasured, 1)
        XCTAssertEqual(try XCTUnwrap(month.pace), 300, accuracy: 0.5)
    }

    // MARK: … and aggregated by month

    func testTheMonthlyZonePaceIsTimeOverDistanceNotAMeanOfMeans() throws {
        let now = Date()
        // One long easy run at 5:00 and one short one at 6:00 in the same
        // month: 30 km in 9600 s → 5:20, not the 5:30 a mean of the two gives.
        let long = zoneRun([0, 6000, 0, 0, 0], km: 20, duration: 6000,
                           perZoneKm: [0, 20, 0, 0, 0], date: now)
        let short = zoneRun([0, 3600, 0, 0, 0], km: 10, duration: 3600,
                            perZoneKm: [0, 10, 0, 0, 0], date: now)
        let months = RunAnalytics.monthlyZonePace(runs: [long, short], zone: 2,
                                                  zones: testZones, months: 1, now: now)
        let month = try XCTUnwrap(months.last)
        XCTAssertEqual(try XCTUnwrap(month.pace), 320, accuracy: 0.5)
        XCTAssertEqual(month.runs, 2)
        XCTAssertEqual(month.km, 30, accuracy: 0.001)
        XCTAssertEqual(month.unmeasured, 0)
    }

    func testAMonthWithoutEasyRunningIsAGapNotAZero() {
        let hard = zoneRun([0, 100, 400, 2100, 400])
        let months = RunAnalytics.monthlyZonePace(runs: [hard], zone: 2,
                                                  zones: testZones, months: 1)
        XCTAssertNil(months.last?.pace)
        XCTAssertEqual(months.last?.runs, 0)
    }

    // MARK: … and read as a trend

    func testTheTrendComparesBothEndsRatherThanTwoLonePoints() throws {
        // A line that improves steadily, with one freak month at each end.
        let series: [TimeInterval?] = [400, 350, 348, 344, 340, 300]
        let change = try XCTUnwrap(RunAnalytics.trendChange(series, window: 3))
        // Mean of the first three (366) against the last three (328).
        XCTAssertEqual(change, -38, accuracy: 0.5)
    }

    func testATooShortLineHasNoTrendToReport() {
        XCTAssertNil(RunAnalytics.trendChange([300, nil, 310]))
        XCTAssertNil(RunAnalytics.trendChange([nil, nil, nil, nil]))
    }

    // MARK: What the screens actually print

    func testOneOfSomethingIsNotPlural() {
        XCTAssertEqual(Format.plural(1, "run", "runs"), "1 run")
        XCTAssertEqual(Format.plural(0, "run", "runs"), "0 runs")
        XCTAssertEqual(Format.plural(2, "day", "days"), "2 days")
    }

    func testARunWithoutHeartRateNamesNoZone() {
        // Zone 0 does not exist; a run that never saw a heart rate simply has
        // no zone to name, and the line stops rather than inventing one.
        let blind = Run(date: .now, name: "Easy", distanceKm: 10, duration: 3000, avgHR: 0)
        let text = LogRowText(run: blind, prTag: nil)
        XCTAssertFalse(text.detail.contains("Z0"), text.detail)
        XCTAssertFalse(text.detail.contains("Z"), text.detail)

        let measured = Run(date: .now, name: "Easy", distanceKm: 10, duration: 3000,
                           avgHR: 140, zoneSeconds: [0, 2400, 600, 0, 0])
        XCTAssertTrue(LogRowText(run: measured, prTag: nil).detail.contains("Z2"))
    }

    func testAPaceOfNothingIsNotAPace() {
        // A stopped runner, or one before the first GPS fix.
        XCTAssertEqual(Format.pace(0), "–:––")
        XCTAssertEqual(Format.pace(-5), "–:––")
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
        // Every field added later must be optional, or old logs stop decoding.
        XCTAssertFalse(run.isImported)
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
    // MARK: Heart-rate zones

    func testZonesFallBackToPercentOfMaxWithoutRestingHR() {
        let zones = HRZones(maxHR: 190)
        // The design's ladder at max 190.
        XCTAssertEqual(zones.bounds, [115, 133, 152, 171])
        XCTAssertFalse(zones.usesReserve)
    }

    func testZonesUseHeartRateReserveWhenRestingIsKnown() {
        let zones = HRZones(maxHR: 190, restingHR: 50)
        // Karvonen: 50 + 140 x [0.6, 0.7, 0.8, 0.9]
        XCTAssertEqual(zones.bounds, [134, 148, 162, 176])
        XCTAssertTrue(zones.usesReserve)
        // Reserve zones sit higher than the plain share of max — that is the
        // whole point, and it must not silently invert.
        XCTAssertGreaterThan(zones.bounds[0], HRZones(maxHR: 190).bounds[0])
    }

    func testTwoRunnersSharingMaxButNotRestingGetDifferentZones() {
        let fit = HRZones(maxHR: 190, restingHR: 42)
        let unfit = HRZones(maxHR: 190, restingHR: 68)
        XCTAssertNotEqual(fit.bounds, unfit.bounds)
        XCTAssertLessThan(fit.bounds[0], unfit.bounds[0])
    }

    func testManualOverridesBeatEveryDerivation() {
        var zones = HRZones(maxHR: 190, restingHR: 50)
        zones.overrides = [120, 140, 160, 175]
        XCTAssertEqual(zones.bounds, [120, 140, 160, 175])
        XCTAssertFalse(zones.usesReserve)
    }

    func testImplausibleRestingHRIsIgnoredRatherThanTrusted() {
        // A resting pulse at or above max would produce nonsense boundaries.
        XCTAssertEqual(HRZones(maxHR: 190, restingHR: 200).bounds, HRZones(maxHR: 190).bounds)
        XCTAssertEqual(HRZones(maxHR: 190, restingHR: 10).bounds, HRZones(maxHR: 190).bounds)
    }

    func testZonesStayAutomaticUntilTheRunnerDecidesOtherwise() {
        XCTAssertTrue(HRZones(maxHR: 190).isAutomatic)

        var overridden = HRZones(maxHR: 190)
        overridden.overrides = [120, 140, 160, 175]
        XCTAssertFalse(overridden.isAutomatic, "a hand-set boundary is a decision")

        var handSetMax = HRZones(maxHR: 190)
        handSetMax.derivation = HRDerivation(maxSource: .manual)
        XCTAssertFalse(handSetMax.isAutomatic, "so is a hand-set max")

        var derived = HRZones(maxHR: 190)
        derived.derivation = HRDerivation(maxSource: .measured)
        XCTAssertTrue(derived.isAutomatic, "one Currimus derived itself stays its own")
    }

    func testAZoneChangeIsReportedByTheBoundaryThatMovedFurthest() throws {
        let before = HRZones(maxHR: 190)                    // 115 / 133 / 152 / 171
        let after = HRZones(maxHR: 190, restingHR: 50)      // 134 / 148 / 162 / 176
        let summary = try XCTUnwrap(HRZones.changeSummary(from: before, to: after))
        // Z1 moved 19 bpm, more than any other boundary — that is the news.
        XCTAssertTrue(summary.contains("Zone 1"), summary)
        XCTAssertTrue(summary.contains("134"), summary)
        XCTAssertTrue(summary.contains("115"), summary)
    }

    func testUnchangedZonesAreNotWorthANotice() {
        let zones = HRZones(maxHR: 190, restingHR: 50)
        XCTAssertNil(HRZones.changeSummary(from: zones, to: zones))
        // A max that moved without moving a single boundary is possible with
        // hand-set overrides, and is still worth one line.
        var pinned = HRZones(maxHR: 190)
        pinned.overrides = [120, 140, 160, 175]
        var raised = pinned
        raised.maxHR = 195
        XCTAssertNotNil(HRZones.changeSummary(from: pinned, to: raised))
    }

    func testZoneLookupStaysConsistentWithReserveBounds() {
        let zones = HRZones(maxHR: 190, restingHR: 50)
        XCTAssertEqual(zones.zone(for: 100), 1)
        XCTAssertEqual(zones.zone(for: 134), 1)   // upper edge of Z1
        XCTAssertEqual(zones.zone(for: 135), 2)
        XCTAssertEqual(zones.zone(for: 180), 5)
    }

    func testTanakaBeatsTheNaiveAgeFormula() {
        // 208 - 0.7 x 40 = 180, where 220 - age would claim 180 too, but at 25
        // the two diverge and Tanaka is the calibrated one.
        XCTAssertEqual(HeartRateProfile.tanaka(age: 40), 180)
        XCTAssertEqual(HeartRateProfile.tanaka(age: 25), 191)
        XCTAssertNil(HeartRateProfile.tanaka(age: 4))
    }

    func testDerivationExplainsItselfInPlainLanguage() {
        let derivation = HRDerivation(maxSource: .measured, maxDate: .now, age: 38,
                                      restingHR: 52, restingSampleDays: 60)
        XCTAssertTrue(derivation.maxExplanation.contains("Highest heart rate"))
        let text = derivation.zoneExplanation(usesReserve: true)
        XCTAssertTrue(text.contains("52 bpm"))
        XCTAssertTrue(text.contains("60-day"))
    }

    func testWatchSettingsCarryRestingHRAndGPSAccuracy() throws {
        let s = WatchSettings(pacerTargetSecPerKm: 315, pacerDefaultDistanceKm: 10,
                              kilometerAlert: true, countdownEnabled: false,
                              maxHR: 188, zoneBounds: nil,
                              restingHR: 48, gpsAccuracy: .balanced)
        let back = try JSONDecoder().decode(WatchSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.restingHR, 48)
        XCTAssertEqual(back.gpsAccuracy, .balanced)
    }

    func testOlderWatchPayloadWithoutTheNewFieldsStillDecodes() throws {
        let legacy = """
        {"pacerTargetSecPerKm":315,"kilometerAlert":true,"countdownEnabled":true,"maxHR":190}
        """.data(using: .utf8)!
        let back = try JSONDecoder().decode(WatchSettings.self, from: legacy)
        XCTAssertEqual(back.maxHR, 190)
        XCTAssertNil(back.restingHR)
        XCTAssertNil(back.gpsAccuracy)
    }

    func testGPSAccuracyTradesPrecisionForBatteryMonotonically() {
        // Each step down must ask for coarser fixes and fewer of them.
        XCTAssertLessThan(GPSAccuracy.balanced.desiredAccuracy, GPSAccuracy.saving.desiredAccuracy)
        XCTAssertLessThan(GPSAccuracy.high.distanceFilter, GPSAccuracy.balanced.distanceFilter)
        XCTAssertLessThan(GPSAccuracy.balanced.distanceFilter, GPSAccuracy.saving.distanceFilter)
        XCTAssertEqual(GPSAccuracy.high.distanceFilter, 0)
    }

    // MARK: Always-On palette

    private func rgba(_ color: Color) -> [CGFloat] {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a]
        #else
        return []
        #endif
    }

    func testReducedScreenStepsTheNumbersBackWithoutLosingThem() {
        let live = RunPalette(dimmed: false)
        let dim = RunPalette(dimmed: true)
        XCTAssertEqual(rgba(live.hero), rgba(Theme.ink))
        XCTAssertEqual(rgba(live.value), rgba(Theme.ink))

        // With the wrist down something has to visibly give, or the mode reads
        // as broken — but the hero is what gets glanced at, so it gives least.
        XCTAssertLessThan(rgba(dim.hero)[0], rgba(live.hero)[0])
        XCTAssertLessThan(rgba(dim.value)[0], rgba(dim.hero)[0])
        // …and stays well clear of the muted greys the frame is drawn in.
        XCTAssertGreaterThan(rgba(dim.hero)[0], rgba(dim.label)[0])
        XCTAssertGreaterThan(rgba(dim.value)[0], rgba(dim.label)[0])
    }

    func testReducedScreenStepsSecondaryInkBack() {
        let live = RunPalette(dimmed: false)
        let dim = RunPalette(dimmed: true)
        // Every supporting colour must get darker, never brighter.
        for (a, b) in [(live.secondary, dim.secondary), (live.label, dim.label), (live.track, dim.track)] {
            let (bright, dark) = (rgba(a), rgba(b))
            XCTAssertGreaterThan(bright[0], dark[0], "reduced colour must be darker")
        }
    }

    func testReducedSignalDropsToTheDesignsFiftyFivePercent() {
        XCTAssertEqual(rgba(RunPalette(dimmed: true).signal)[3], 0.55, accuracy: 0.01)
        XCTAssertEqual(rgba(RunPalette(dimmed: false).signal)[3], 1.0, accuracy: 0.01)
    }

    func testActiveZoneFillFollowsTheDesignPerState() {
        XCTAssertEqual(RunPalette(dimmed: false).activeZoneFill, 0.30, accuracy: 0.001)
        XCTAssertEqual(RunPalette(dimmed: true).activeZoneFill, 0.28, accuracy: 0.001)
    }

    func testReducedScreenOnlyEngagesWhenTheSettingIsOn() {
        // Wrist down but switched off → no extra reduction from Currimus.
        XCTAssertFalse(RunPalette.resolve(systemDimmed: true, enabled: false).dimmed)
        XCTAssertTrue(RunPalette.resolve(systemDimmed: true, enabled: true).dimmed)
        // Wrist up is never reduced, whatever the setting says.
        XCTAssertFalse(RunPalette.resolve(systemDimmed: false, enabled: true).dimmed)
        XCTAssertFalse(RunPalette.resolve(systemDimmed: false, enabled: false).dimmed)
    }

    func testAlwaysOnSettingSyncsToTheWatchAndDefaultsToOn() throws {
        XCTAssertTrue(WatchSettings().alwaysOnReduced ?? true, "default must be on")
        let sent = WatchSettings(maxHR: 190, alwaysOnReduced: false)
        let back = try JSONDecoder().decode(WatchSettings.self, from: JSONEncoder().encode(sent))
        XCTAssertEqual(back.alwaysOnReduced, false)
        // An older watch build sends no such field; the watch must then keep
        // its own value rather than read nil as "off".
        let legacy = """
        {"pacerTargetSecPerKm":315,"kilometerAlert":true,"countdownEnabled":true,"maxHR":190}
        """.data(using: .utf8)!
        XCTAssertNil(try JSONDecoder().decode(WatchSettings.self, from: legacy).alwaysOnReduced)
    }
}
