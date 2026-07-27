import XCTest

/// The rules behind "next time".
///
/// A screen that finds something to correct after every run is a screen people
/// stop reading, so most of these assert *silence* — that the hint stays out
/// of the way until there is a real margin to talk about.
final class RunHintsTests: XCTestCase {
    private func run(km: Double = 10, pacePerKm: TimeInterval = 300,
                     cadence: Int? = 170, trail: Bool = false) -> Run {
        Run(date: .now, type: trail ? .trail : .quick, name: "Run",
            distanceKm: km, duration: km * pacePerKm, avgHR: 150,
            cadenceSpm: cadence)
    }

    // MARK: - The expectation itself

    func testTheExpectedCadenceRisesWithPace() {
        let jog = RunHints.expectedCadence(forPaceSecPerKm: 420)
        let steady = RunHints.expectedCadence(forPaceSecPerKm: 300)
        let fast = RunHints.expectedCadence(forPaceSecPerKm: 240)
        XCTAssertLessThan(jog, steady)
        XCTAssertLessThan(steady, fast)
    }

    func testTheExpectationIsBoundedAtBothEnds() {
        // A walk-pace shuffle is not asked for elite turnover, and a 2:30 /km
        // sprint does not raise the bar past where the anchors stop.
        XCTAssertEqual(RunHints.expectedCadence(forPaceSecPerKm: 900), 158, accuracy: 0.01)
        XCTAssertEqual(RunHints.expectedCadence(forPaceSecPerKm: 150), 182, accuracy: 0.01)
    }

    func testTheExpectationInterpolatesBetweenAnchors() {
        // Half way between 6:00 (162) and 5:00 (168).
        XCTAssertEqual(RunHints.expectedCadence(forPaceSecPerKm: 330), 165, accuracy: 0.01)
    }

    // MARK: - When the hint fires

    func testAShortStrideAtASteadyPaceEarnsTheHint() throws {
        // 5:00 /km expects ~168; 155 is well under it.
        let hint = try XCTUnwrap(RunHints.cadence(for: run(pacePerKm: 300, cadence: 155)))
        XCTAssertEqual(hint.kind, .cadence)
        XCTAssertTrue(hint.body.contains("155"), hint.body)
        // The target is five per cent above what they actually ran, not a
        // textbook number they have no route to.
        XCTAssertTrue(hint.body.contains("163"), hint.body)
    }

    func testACadenceInsideTheToleranceSaysNothing() {
        // 5:00 /km expects 168, tolerance 5 — 164 is close enough to leave be.
        XCTAssertNil(RunHints.cadence(for: run(pacePerKm: 300, cadence: 164)))
    }

    func testAGoodCadenceSaysNothing() {
        XCTAssertNil(RunHints.cadence(for: run(pacePerKm: 300, cadence: 176)))
    }

    func testTheSameCadenceIsFineSlowAndShortFast() {
        // 162 is on the mark at 6:00 /km and short at 4:00 /km — which is the
        // whole reason the expectation moves with pace.
        XCTAssertNil(RunHints.cadence(for: run(pacePerKm: 360, cadence: 162)))
        XCTAssertNotNil(RunHints.cadence(for: run(pacePerKm: 240, cadence: 162)))
    }

    // MARK: - When it stays quiet

    func testARunWithoutACadenceReadingSaysNothing() {
        XCTAssertNil(RunHints.cadence(for: run(cadence: nil)))
        XCTAssertNil(RunHints.cadence(for: run(cadence: 0)))
    }

    func testAJogAroundTheBlockIsNotJudged() {
        XCTAssertNil(RunHints.cadence(for: run(km: 1.5, pacePerKm: 300, cadence: 150)))
    }

    func testTrailRunsAreLeftAlone() {
        // Cadence on a mountain is set by the ground, not by the runner.
        XCTAssertTrue(RunHints.all(for: run(pacePerKm: 420, cadence: 140, trail: true)).isEmpty)
    }

    func testARoadRunWithNothingToSayProducesNoSection() {
        XCTAssertTrue(RunHints.all(for: run(pacePerKm: 300, cadence: 178)).isEmpty)
    }
}
