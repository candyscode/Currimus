import XCTest

/// The recording arithmetic, exercised without HealthKit or a clock.
///
/// This is the code a run depends on and nothing could reach before: it lived
/// as private methods on a 540-line class welded to `HKWorkoutSession`.
final class RunMetricsTests: XCTestCase {

    /// Feeds `seconds` of running at a constant pace.
    private func run(_ metrics: inout RunMetrics, seconds: ClosedRange<Int>,
                     paceSecPerKm: Double, heartRate: Int = 150, zone: Int = 3) {
        for second in seconds {
            let t = Double(second)
            metrics.tick(elapsed: t, distanceKm: t / paceSecPerKm, heartRate: heartRate, zone: zone)
        }
    }

    // MARK: Rolling pace

    func testRollingPaceMatchesASteadyEffort() {
        var metrics = RunMetrics()
        run(&metrics, seconds: 1...600, paceSecPerKm: 300)
        XCTAssertEqual(metrics.rollingPace, 300, accuracy: 2)
    }

    func testRollingPaceSlowsAndThenBlanksWhileStandingStill() {
        var metrics = RunMetrics()
        run(&metrics, seconds: 1...600, paceSecPerKm: 300)
        let moving = metrics.rollingPace

        // Stopped at 2 km — the clock runs, the distance does not.
        for second in 601...900 {
            metrics.tick(elapsed: Double(second), distanceKm: 2.0, heartRate: 150, zone: 3)
        }
        XCTAssertGreaterThan(metrics.rollingPace, moving,
                             "a stopped runner must not keep reading like they are still moving")

        // Once the window holds nothing but standing still, there is no honest
        // pace left to show.
        for second in 901...1_300 {
            metrics.tick(elapsed: Double(second), distanceKm: 2.0, heartRate: 150, zone: 3)
        }
        XCTAssertEqual(metrics.rollingPace, 0)
    }

    // MARK: Splits

    func testKilometerSplitsCloseAtEachBoundary() {
        var metrics = RunMetrics()
        var reported: [RunMetrics.KilometerSplit] = []
        for second in 1...1_500 {
            let t = Double(second)
            if let split = metrics.tick(elapsed: t, distanceKm: t / 300, heartRate: 150, zone: 3) {
                reported.append(split)
            }
        }
        XCTAssertEqual(reported.map(\.km), [1, 2, 3, 4, 5])
        XCTAssertEqual(metrics.splits.count, 5)
        XCTAssertEqual(metrics.splits[0], 300, accuracy: 1)
        // A steady run is by definition at its own average.
        XCTAssertEqual(reported.last?.deltaVsAverage ?? 99, 0, accuracy: 1)
    }

    // MARK: Zones and heart rate

    func testZoneSecondsAndAverageHeartRateAccumulate() {
        var metrics = RunMetrics()
        run(&metrics, seconds: 1...60, paceSecPerKm: 300, heartRate: 150, zone: 3)
        run(&metrics, seconds: 61...120, paceSecPerKm: 300, heartRate: 170, zone: 4)
        XCTAssertEqual(metrics.zoneSeconds[2], 60)
        XCTAssertEqual(metrics.zoneSeconds[3], 60)
        XCTAssertEqual(metrics.averageHR, 160)
    }

    func testNoHeartRateMeansNoZoneTime() {
        var metrics = RunMetrics()
        run(&metrics, seconds: 1...60, paceSecPerKm: 300, heartRate: 0, zone: 0)
        XCTAssertEqual(metrics.zoneSeconds.reduce(0, +), 0)
        XCTAssertEqual(metrics.averageHR, 0)
    }

    // MARK: Altitude

    func testClimbIgnoresJitterButCountsRealAscent() {
        var metrics = RunMetrics()
        // Standing still, the altitude wobbling by a metre.
        for (index, altitude) in [100.0, 101, 100, 99.5, 100.5, 100].enumerated() {
            metrics.ingestAltitude(altitude, verticalAccuracy: 5, at: Double(index) * 10)
        }
        XCTAssertEqual(metrics.climbMeters, 0)
        XCTAssertEqual(metrics.descentMeters, 0)

        // Then 50 m up and 30 m back down, at a runnable 0.25 m/s.
        var altitude = 100.0
        var second = 60.0
        for _ in 0..<200 { altitude += 0.25; second += 1
            metrics.ingestAltitude(altitude, verticalAccuracy: 5, at: second) }
        XCTAssertEqual(metrics.climbMeters, 50, accuracy: 4)
        for _ in 0..<120 { altitude -= 0.25; second += 1
            metrics.ingestAltitude(altitude, verticalAccuracy: 5, at: second) }
        XCTAssertEqual(metrics.climbMeters, 50, accuracy: 4)
        XCTAssertEqual(metrics.descentMeters, 30, accuracy: 4)
    }

    /// The CUR-40 regression, and the reason the whole algorithm changed.
    ///
    /// A thousand metres of climbing, sampled once a second with the ±3 m of
    /// noise a real altitude signal carries. The old rule — "any step over
    /// 1.5 m is climb" — read this as 1 200 to 1 250 m, which is exactly what a
    /// field test against Apple Fitness showed. Five per cent is the budget.
    func testNoiseDoesNotInflateAThousandMetreDay() {
        var metrics = RunMetrics()
        var generator = SystemRandomNumberGenerator()
        var truth = 400.0
        // Up 1 000 m at 0.25 m/s, then back down again.
        for second in 0..<8_000 {
            truth += second < 4_000 ? 0.25 : -0.25
            let noisy = truth + Double.random(in: -3...3, using: &generator)
            metrics.ingestAltitude(noisy, verticalAccuracy: 5, at: Double(second))
        }
        XCTAssertEqual(metrics.climbMeters, 1_000, accuracy: 50)
        XCTAssertEqual(metrics.descentMeters, 1_000, accuracy: 50)
    }

    /// Rolling terrain, where a filter that rounds off summits loses its money.
    ///
    /// Twenty times up 60 m and down 10 m: every reversal is a place where a
    /// low-pass under-reads the peak and over-reads the trough, and the losses
    /// add up over a day rather than cancelling. Hence a light filter and a
    /// hysteresis band doing most of the work.
    func testRollingTerrainDoesNotBleedHeightAtEveryReversal() {
        var metrics = RunMetrics()
        var altitude = 500.0
        var second = 0.0
        for _ in 0..<20 {
            for _ in 0..<240 { altitude += 0.25; second += 1
                metrics.ingestAltitude(altitude, verticalAccuracy: 5, at: second) }
            for _ in 0..<40 { altitude -= 0.25; second += 1
                metrics.ingestAltitude(altitude, verticalAccuracy: 5, at: second) }
        }
        XCTAssertEqual(metrics.climbMeters, 1_200, accuracy: 60)   // 5 %
        // The 10 m drops read short, and that is the trade being made: a leg
        // only two hysteresis bands tall loses most of a band to the filter's
        // lag at each end. It costs a fifth of the *small* legs and five per
        // cent of the day, which is the right way round for a climb figure.
        XCTAssertEqual(metrics.descentMeters, 160, accuracy: 40)
    }

    /// Changing altitude source mid-run must not bank the gap between them.
    ///
    /// Barometric and GPS altitude disagree by tens of metres — they are not
    /// measured against the same reference — so a run that starts on one and
    /// switches to the other has a step in its series, and a step is exactly
    /// what the leg tracker counts as climb. `RunSession` waits for the
    /// barometer rather than switching, and drops the tracking state if it has
    /// to fall back anyway. This is that drop.
    func testChangingAltitudeSourceDoesNotCountTheGapAsClimb() {
        var metrics = RunMetrics()
        // Half a minute on one source, climbing gently.
        for second in 0..<30 {
            metrics.ingestAltitude(600 + Double(second) * 0.25, verticalAccuracy: 5, at: Double(second))
        }
        let climbed = metrics.climbMeters

        // The other source reads the same hillside 40 m lower.
        metrics.resetAltitudeTracking()
        for second in 30..<120 {
            metrics.ingestAltitude(567 + Double(second) * 0.25, verticalAccuracy: 5, at: Double(second))
        }
        // The 40 m step is neither climb nor descent; the climbing on either
        // side of it still counts.
        XCTAssertEqual(metrics.descentMeters, 0, accuracy: 1, "the step is not a descent")
        XCTAssertEqual(metrics.climbMeters, climbed + 22.5, accuracy: 4)
    }

    /// Standing still for half an hour is not a climb, however noisy the sensor.
    func testStandingStillClimbsNothing() {
        var metrics = RunMetrics()
        var generator = SystemRandomNumberGenerator()
        for second in 0..<1_800 {
            metrics.ingestAltitude(820 + Double.random(in: -3...3, using: &generator),
                                   verticalAccuracy: 5, at: Double(second))
        }
        // A real barometer is an order of magnitude quieter than the ±3 m fed
        // in here — that is GPS-grade noise, i.e. the fallback path's worst day.
        XCTAssertLessThan(metrics.climbMeters, 10)
        XCTAssertLessThan(metrics.descentMeters, 10)
    }

    /// The number on the wrist must not sit still while the runner is climbing:
    /// the leg in progress counts, and it does not double-count when it closes.
    func testClimbInProgressIsAlreadyCounted() {
        var metrics = RunMetrics()
        for second in 0..<200 {
            metrics.ingestAltitude(500 + Double(second) * 0.5, verticalAccuracy: 5, at: Double(second))
        }
        let midClimb = metrics.climbMeters
        XCTAssertEqual(midClimb, 100, accuracy: 4)

        // Crest and descend: the leg closes, and the total does not jump.
        for second in 200..<320 {
            metrics.ingestAltitude(600 - Double(second - 200) * 0.5, verticalAccuracy: 5, at: Double(second))
        }
        XCTAssertEqual(metrics.climbMeters, midClimb, accuracy: 5)
        XCTAssertEqual(metrics.descentMeters, 60, accuracy: 6)
    }

    /// The other half of CUR-40: a descent followed by a genuine ascent has to
    /// start counting again. On the field-test run it never did.
    func testAscentAfterADescentCountsAgain() {
        var metrics = RunMetrics()
        var altitude = 1_600.0
        var second = 0.0
        for _ in 0..<1_200 { altitude -= 0.3; second += 1
            metrics.ingestAltitude(altitude, verticalAccuracy: 5, at: second) }
        XCTAssertEqual(metrics.descentMeters, 360, accuracy: 5)
        XCTAssertLessThan(metrics.climbMeters, 3)

        // Ten minutes back up.
        for _ in 0..<600 { altitude += 0.3; second += 1
            metrics.ingestAltitude(altitude, verticalAccuracy: 5, at: second)
            metrics.tick(elapsed: second, distanceKm: second / 600, heartRate: 150, zone: 3) }
        XCTAssertEqual(metrics.climbMeters, 180, accuracy: 5)
        // …and the live rate says so, over the last minute.
        XCTAssertEqual(metrics.climbRatePerHour, 1_080, accuracy: 60)
    }

    func testUnusableAccuracyIsDiscarded() {
        var metrics = RunMetrics()
        metrics.ingestAltitude(100, verticalAccuracy: -1, at: 0)      // invalid fix
        metrics.ingestAltitude(500, verticalAccuracy: 40, at: 10)     // too vague
        XCTAssertTrue(metrics.altitudeProfile.isEmpty)
        XCTAssertEqual(metrics.climbMeters, 0)

        metrics.ingestCoordinate(latitude: 48, longitude: 7, altitude: 100,
                                 horizontalAccuracy: 120, at: 20)
        XCTAssertTrue(metrics.coordinates.isEmpty)
    }

    func testClimbRateReflectsTheRecentWindow() {
        var metrics = RunMetrics()
        // 600 m of climbing over an hour, plus the seconds ticking past.
        for second in stride(from: 0, through: 3_600, by: 10) {
            metrics.ingestAltitude(100 + Double(second) / 6, verticalAccuracy: 5, at: Double(second))
            metrics.tick(elapsed: Double(second), distanceKm: Double(second) / 600,
                         heartRate: 150, zone: 3)
        }
        XCTAssertEqual(metrics.climbRatePerHour, 600, accuracy: 30)
    }

    /// The window is a minute, not ten (CUR-40): stop climbing and the rate has
    /// to fall away inside a minute rather than carry the last climb for ten.
    func testClimbRateForgetsTheLastClimbWithinAMinute() {
        var metrics = RunMetrics()
        var second = 0.0
        // Four minutes of steady 900 m/h.
        for _ in 0..<240 {
            metrics.ingestAltitude(500 + second / 4, verticalAccuracy: 5, at: second)
            metrics.tick(elapsed: second, distanceKm: second / 400, heartRate: 150, zone: 3)
            second += 1
        }
        XCTAssertEqual(metrics.climbRatePerHour, 900, accuracy: 60)

        // Then two minutes of flat.
        for _ in 0..<120 {
            metrics.ingestAltitude(560, verticalAccuracy: 5, at: second)
            metrics.tick(elapsed: second, distanceKm: second / 400, heartRate: 150, zone: 3)
            second += 1
        }
        XCTAssertEqual(metrics.climbRatePerHour, 0, accuracy: 1)
    }

    // MARK: Capacity — the regression this file exists for

    func testDecimationKeepsBothEnds() {
        XCTAssertEqual(RunMetrics.decimated([1, 2, 3, 4, 5]), [1, 3, 5])
        XCTAssertEqual(RunMetrics.decimated([1, 2, 3, 4]), [1, 3, 4])
        XCTAssertEqual(RunMetrics.decimated([1, 2]), [1, 2])
        XCTAssertEqual(RunMetrics.decimated([1]), [1])
        XCTAssertEqual(RunMetrics.decimated([Int]()), [])
    }

    func testLongRunKeepsItsStartInTheAltitudeProfile() {
        var metrics = RunMetrics()
        // Four hours, climbing steadily from 100 m to 244 m.
        for second in stride(from: 0, through: 14_400, by: 1) {
            metrics.ingestAltitude(100 + Double(second) / 100, verticalAccuracy: 5, at: Double(second))
        }
        XCTAssertLessThanOrEqual(metrics.altitudeProfile.count, RunMetrics.altitudeCapacity + 1)
        // The old ring buffer dropped from the front, so a marathon's profile
        // started somewhere in the middle of the run. It starts at the start.
        XCTAssertEqual(metrics.altitudeProfile.first ?? 0, 100, accuracy: 1)
        XCTAssertGreaterThan(metrics.altitudeProfile.last ?? 0, 240)
    }

    func testLongRunKeepsItsStartInTheGPSTrack() {
        var metrics = RunMetrics()
        // Long enough to blow past the route ceiling several times over.
        for second in stride(from: 0, through: 30_000, by: 1) {
            metrics.ingestCoordinate(latitude: 48 + Double(second) / 100_000, longitude: 7,
                                     altitude: 100, horizontalAccuracy: 5, at: Double(second))
        }
        XCTAssertLessThanOrEqual(metrics.coordinates.count, RunMetrics.routeCapacity + 1)
        XCTAssertEqual(metrics.coordinates.first?.t ?? -1, 0,
                       "the GPX export must still have a start line")
        XCTAssertEqual(metrics.coordinates.first?.lat ?? 0, 48, accuracy: 1e-9)
        XCTAssertGreaterThan(metrics.coordinates.last?.t ?? 0, 29_000)
    }
}
