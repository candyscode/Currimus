import XCTest

#if DEBUG
/// End-to-end run simulations: a whole run driven second-by-second through the
/// real `RunMetrics` pipeline, then checked for the things that only go wrong at
/// length — a dropped kilometre, a truncated profile, a quadratic slow-down, a
/// route that loses its start. Where `RunMetricsTests` exercises one signal at
/// a time, this exercises a marathon.
final class RunSimulationTests: XCTestCase {

    private func simulate(_ scenario: RunScenario) -> RunSimulator.Result {
        RunSimulator(scenario: scenario).run()
    }

    // MARK: - The long run records completely

    func testMarathonRecordsEveryKilometreSplit() {
        let r = simulate(.marathon)
        XCTAssertGreaterThanOrEqual(r.distanceKm, 42.195)
        // 42 whole kilometres cross the line; the 43rd never does.
        XCTAssertEqual(r.metrics.splits.count, 42, "a kilometre went unrecorded")
        XCTAssertEqual(r.reportedSplits.map(\.km), Array(1...42))
        // Every split is a plausible ~5:00, none missing or fused.
        XCTAssertTrue(r.metrics.splits.allSatisfy { (260...360).contains($0) },
                      "a split landed outside any sane pace: \(r.metrics.splits)")
        // Heart rate ran the whole time, so zone time accounts for every second.
        XCTAssertEqual(r.metrics.zoneSeconds.reduce(0, +), r.elapsed, accuracy: 2)
        XCTAssertTrue((140...175).contains(r.run.avgHR), "avgHR \(r.run.avgHR)")
    }

    func testMarathonKeepsProfileAndRouteBoundedWithoutLosingTheStart() {
        let r = simulate(.marathon)
        // Both series stay under their ceilings (decimation, not unbounded RAM).
        XCTAssertLessThanOrEqual(r.metrics.altitudeProfile.count, RunMetrics.altitudeCapacity + 1)
        XCTAssertLessThanOrEqual(r.metrics.coordinates.count, RunMetrics.routeCapacity + 1)
        // …and both still begin at the start of the run.
        XCTAssertEqual(r.metrics.altitudeProfile.first ?? 0, 260, accuracy: 2)
        XCTAssertEqual(r.run.route?.first?.t ?? -1, 1, "the GPX export lost its start line")
        XCTAssertGreaterThan(r.run.route?.count ?? 0, 100)
    }

    // MARK: - The ultra: still complete, still linear in time

    func testUltraKeepsAllFiftyKilometresAndItsClimb() {
        let r = simulate(.trailUltra)
        XCTAssertEqual(r.metrics.splits.count, 50, "the ultra dropped a kilometre")
        XCTAssertGreaterThan(r.metrics.climbMeters, 1000, "the climb was under-counted")
        XCTAssertGreaterThan(r.metrics.descentMeters, 300)
        XCTAssertGreaterThan(r.run.highPointMeters ?? 0, 1500)
        XCTAssertLessThanOrEqual(r.metrics.altitudeProfile.count, RunMetrics.altitudeCapacity + 1)
        XCTAssertLessThanOrEqual(r.metrics.coordinates.count, RunMetrics.routeCapacity + 1)
    }

    /// The guard against an accidental O(n²): a six-hour run must simulate in a
    /// blink. A per-tick scan over the whole run so far would turn this from
    /// tens of milliseconds into many seconds.
    func testASixHourRunStaysCheapPerSecond() {
        let r = simulate(.trailUltra)
        XCTAssertGreaterThan(r.ticks, 18_000, "expected a genuinely long run")
        XCTAssertLessThan(r.simSeconds, 1.5,
                          "simulating \(r.ticks) s took \(r.simSeconds) s — pipeline may be super-linear")
    }

    // MARK: - Edge shapes

    func testTreadmillHasDistanceButNeitherRouteNorElevation() {
        let r = simulate(.treadmill)
        XCTAssertGreaterThanOrEqual(r.distanceKm, 10)
        XCTAssertEqual(r.metrics.splits.count, 10)
        XCTAssertNil(r.run.route, "a run with no GPS invented a route")
        XCTAssertNil(r.run.altitudeSamples, "a run with no GPS invented elevation")
        XCTAssertEqual(r.metrics.climbMeters, 0)
        XCTAssertEqual(r.metrics.descentMeters, 0)
    }

    func testGPSDropoutLeavesAGapButKeepsBothEnds() {
        let r = simulate(.gpsDropout)
        let route = r.run.route ?? []
        XCTAssertFalse(route.isEmpty)
        XCTAssertEqual(route.first?.t ?? -1, 1, "the start of the route was lost")
        XCTAssertGreaterThan(route.last?.t ?? 0, 1500, "the route ended at the dropout")
        // Nothing recorded while the signal was gone (well inside the window).
        XCTAssertFalse(route.contains { (950...1450).contains($0.t) },
                       "a fix was recorded during the GPS dropout")
        // The run itself is unaffected: distance and splits come from pace.
        XCTAssertEqual(r.metrics.splits.count, 8)
    }

    func testHeartRateGapDoesNotCorruptZonesOrTheAverage() {
        let r = simulate(.heartRateGap)
        // 121 s (600…720 inclusive) carried no reading, so they add no zone time.
        XCTAssertEqual(r.metrics.zoneSeconds.reduce(0, +), r.elapsed - 121, accuracy: 2)
        // The average is over real readings only, not dragged toward zero.
        XCTAssertGreaterThan(r.run.avgHR, 140)
        XCTAssertEqual(r.metrics.splits.count, 6)
    }

    func testAStandstillDoesNotCorruptDistanceOrInventSplits() {
        let r = simulate(.stopAndGo)
        // 1500 s total, 121 stopped → ~1379 s moving at ~5:00/km ≈ 4.6 km.
        XCTAssertEqual(r.distanceKm, 4.6, accuracy: 0.4)
        XCTAssertEqual(r.metrics.splits.count, 4, "the standstill added or dropped a split")
        // No split is absurdly long from folding the stop into a kilometre.
        XCTAssertTrue(r.metrics.splits.allSatisfy { $0 < 500 }, "\(r.metrics.splits)")
    }

    func testNegativeSplitRunsTheSecondHalfFaster() {
        let r = simulate(.marathonNegativeSplit)
        let splits = r.metrics.splits
        XCTAssertEqual(splits.count, 42)
        let firstHalf = splits[0..<21].reduce(0, +) / 21
        let secondHalf = splits[21..<42].reduce(0, +) / 21
        XCTAssertLessThan(secondHalf, firstHalf - 5, "the negative split was not faster late")
    }

    func testWalkRunFoldsTheBreaksIntoSteadyKilometrePaces() {
        let r = simulate(.walkRun)
        XCTAssertGreaterThanOrEqual(r.distanceKm, 8)
        XCTAssertEqual(r.metrics.splits.count, 8)
        // A ~6-minute kilometre spans a whole 4:1 run/walk cycle, so each one
        // folds a run and a walk together and lands between the two paces (330
        // and 690) — near ~370, not at either extreme, and uniform km to km.
        XCTAssertTrue(r.metrics.splits.allSatisfy { (340...420).contains($0) },
                      "a walk break was mis-folded into a split: \(r.metrics.splits)")
        XCTAssertLessThan(r.run.splitSpread, 30, "short cycles should even out across kilometres")
        XCTAssertGreaterThanOrEqual(r.metrics.rollingPace, 0)
    }

    func testAPausedRunIgnoresThePauseButTheTrackKeepsTheGap() {
        let r = simulate(.pausedLongRun)
        XCTAssertEqual(r.metrics.splits.count, 15)
        // The run clock is moving time: ~15 km at ~5:15 ≈ 4700 s, not ~5000
        // with the five-minute pause folded in.
        XCTAssertLessThan(r.elapsed, 5000, "the pause was counted as running time")
        XCTAssertEqual(r.distanceKm, 15, accuracy: 0.2)
        // The track carries the pause as a ~300 s gap rather than a teleport —
        // the failure the wall-clock route timestamps exist to prevent.
        let route = r.run.route ?? []
        let gaps = zip(route, route.dropFirst()).map { $1.t - $0.t }
        XCTAssertGreaterThan(gaps.max() ?? 0, 250, "the pause left no gap in the GPX timeline")
    }

    func testBatterySaverKeepsDistanceWholeWhileTheRouteGoesSparse() {
        let r = simulate(.batterySaver)
        // Distance and splits come from pace, so sparse GPS must not thin them.
        XCTAssertGreaterThanOrEqual(r.distanceKm, 10)
        XCTAssertEqual(r.metrics.splits.count, 10)
        // The route survives — just coarser: fixes land far apart, not every 5 s.
        let route = r.run.route ?? []
        XCTAssertGreaterThan(route.count, 0, "battery-saver lost its route entirely")
        let gaps = zip(route, route.dropFirst()).map { $1.t - $0.t }
        let avgGap = gaps.reduce(0, +) / Double(max(gaps.count, 1))
        XCTAssertGreaterThan(avgGap, 10, "battery-saver fixes were not sparse")
    }

    // MARK: - Reproducibility (a "test set" must mean the same thing twice)

    func testTheSameScenarioProducesTheSameRun() {
        let a = simulate(.marathon)
        let b = simulate(.marathon)
        XCTAssertEqual(a.metrics, b.metrics, "the simulation is not deterministic")
        XCTAssertEqual(a.distanceKm, b.distanceKm)
        XCTAssertEqual(a.run.splits, b.run.splits)
    }
}
#endif
