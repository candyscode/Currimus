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

    func testClimbIgnoresGPSJitterButCountsRealAscent() {
        var metrics = RunMetrics()
        // Standing still, GPS altitude wobbling by a metre.
        for (index, altitude) in [100.0, 101, 100, 99.5, 100.5, 100].enumerated() {
            metrics.ingestAltitude(altitude, verticalAccuracy: 5, at: Double(index) * 10)
        }
        XCTAssertEqual(metrics.climbMeters, 0)
        XCTAssertEqual(metrics.descentMeters, 0)

        metrics.ingestAltitude(150, verticalAccuracy: 5, at: 100)
        XCTAssertEqual(metrics.climbMeters, 50, accuracy: 0.001)

        metrics.ingestAltitude(120, verticalAccuracy: 5, at: 200)
        XCTAssertEqual(metrics.descentMeters, 30, accuracy: 0.001)
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
