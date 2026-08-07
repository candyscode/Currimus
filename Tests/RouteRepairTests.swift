import XCTest
import CoreLocation

/// The decisions behind putting a lost GPS track back onto a workout in Apple
/// Health (CUR-44).
///
/// The sweep itself needs a HealthKit store with our own workouts in it, which
/// no simulator has. What is testable is everything it turns on: which runs are
/// worth asking about, and what the stored track becomes on the way to
/// `insertRouteData` — which rejects a location HealthKit does not like, and
/// does so asynchronously, i.e. silently.
final class RouteRepairTests: XCTestCase {
    private func run(_ ageDays: Double, duration: TimeInterval = 1800,
                     imported: Bool? = nil, recovered: Bool? = nil) -> Run {
        var run = Run(date: .now.addingTimeInterval(-ageDays * 86_400),
                      name: "Run", distanceKm: 6, duration: duration, avgHR: 150,
                      imported: imported)
        run.recovered = recovered
        return run
    }

    private func track(_ count: Int, spacing: TimeInterval = 10) -> [Coordinate] {
        (0..<count).map {
            Coordinate(lat: 48.13 + Double($0) * 0.0001, lon: 11.58,
                       elevation: 520 + Double($0), t: Double($0) * spacing)
        }
    }

    // MARK: - Which runs get asked about

    func testOnlyOurOwnRecentUnsettledRunsAreCandidates() {
        let mine = run(1)
        let theirs = run(1, imported: true)
        let stand_in = run(1, recovered: true)
        let ancient = run(90)
        let settled = run(2)
        let candidates = RouteRepair.candidates(
            from: [mine, theirs, stand_in, ancient, settled],
            settled: [settled.id]
        )
        XCTAssertEqual(candidates.map(\.id), [mine.id])
    }

    /// A run that has just finished is still being written to Health — the
    /// route is saved after the workout, and asking in that window would report
    /// a route missing that is seconds from arriving, then write a second one.
    func testARunThatJustEndedIsLeftAlone() {
        let fresh = Run(date: .now.addingTimeInterval(-60), name: "Run",
                        distanceKm: 2, duration: 55, avgHR: 150)
        XCTAssertTrue(RouteRepair.candidates(from: [fresh], settled: []).isEmpty)
    }

    func testNewestFirstAndCappedToOneBatch() {
        let runs = (1...20).map { run(Double($0)) }
        let candidates = RouteRepair.candidates(from: runs.shuffled(), settled: [])
        XCTAssertEqual(candidates.count, RouteRepair.batch)
        XCTAssertEqual(candidates.map(\.date), candidates.map(\.date).sorted(by: >))
        XCTAssertEqual(candidates.first?.id, runs.first?.id, "the newest run is repaired first")
    }

    // MARK: - What HealthKit is handed

    /// Timestamps are the run's start plus each point's own wall-clock offset,
    /// so a run with a pause in it keeps the gap the pause left — the same
    /// stamps the GPX export writes.
    func testLocationsCarryTheRunsOwnClock() {
        let run = run(1)
        let points = RouteRepair.locations(for: run, track: track(4))
        XCTAssertEqual(points.count, 4)
        XCTAssertEqual(points[0].timestamp, run.date)
        XCTAssertEqual(points[3].timestamp.timeIntervalSince(run.date), 30, accuracy: 0.001)
        XCTAssertEqual(points.map(\.timestamp), points.map(\.timestamp).sorted(),
                       "HealthKit rejects a route whose points go backwards in time")
    }

    /// `insertRouteData` refuses a location with a negative accuracy, and the
    /// stored track carries none of its own — every point in it cleared the
    /// live filter, so that limit is what gets stated back.
    func testLocationsCarryAnAccuracyHealthKitWillAccept() {
        let points = RouteRepair.locations(for: run(1), track: track(3))
        for point in points {
            XCTAssertGreaterThan(point.horizontalAccuracy, 0)
            XCTAssertLessThanOrEqual(point.horizontalAccuracy, RunMetrics.usableHorizontalAccuracy)
            XCTAssertGreaterThan(point.verticalAccuracy, 0)
        }
    }

    func testLocationsKeepPositionAndAltitude() {
        let stored = track(2)
        let points = RouteRepair.locations(for: run(1), track: stored)
        XCTAssertEqual(points[1].coordinate.latitude, stored[1].lat, accuracy: 1e-9)
        XCTAssertEqual(points[1].coordinate.longitude, stored[1].lon, accuracy: 1e-9)
        XCTAssertEqual(points[1].altitude, stored[1].elevation, accuracy: 1e-9)
    }

    // MARK: - When to stop asking

    func testOnlyAnAnsweredRunIsSettled() {
        XCTAssertTrue(RouteRepair.Outcome.present.settled)
        XCTAssertTrue(RouteRepair.Outcome.repaired(points: 120).settled)
        XCTAssertFalse(RouteRepair.Outcome.skipped("no workout of ours").settled,
                       "a run Health could not answer for must be asked about again")
    }
}
