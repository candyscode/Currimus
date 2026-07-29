import XCTest

/// The rules behind "next time".
///
/// A screen that finds something to correct after every run is a screen people
/// stop reading, so most of these assert *silence* — that the hint stays out
/// of the way until there is a real margin to talk about.
final class RunHintsTests: XCTestCase {
    private func run(km: Double = 10, pacePerKm: TimeInterval = 300,
                     cadence: Int? = 170, trail: Bool = false,
                     daysAgo: Int = 0) -> Run {
        Run(date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!,
            type: trail ? .trail : .quick, name: "Run",
            distanceKm: km, duration: km * pacePerKm, avgHR: 150,
            cadenceSpm: cadence)
    }

    /// Enough comparable runs for "your usual" to mean something.
    private func history(cadence: Int, pacePerKm: TimeInterval = 300, count: Int = 10) -> [Run] {
        (1...count).map { run(pacePerKm: pacePerKm, cadence: cadence, daysAgo: $0 * 7) }
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
        let hint = try XCTUnwrap(RunHints.shortStride(for: run(pacePerKm: 300, cadence: 155), in: []))
        XCTAssertEqual(hint.kind, .cadence)
        XCTAssertTrue(hint.body.contains("155"), hint.body)
        // The target is five per cent above what they actually ran, not a
        // textbook number they have no route to.
        XCTAssertTrue(hint.body.contains("163"), hint.body)
    }

    func testACadenceInsideTheToleranceSaysNothing() {
        // 5:00 /km expects 168, tolerance 5 — 164 is close enough to leave be.
        XCTAssertNil(RunHints.shortStride(for: run(pacePerKm: 300, cadence: 164), in: []))
    }

    func testAGoodCadenceSaysNothing() {
        XCTAssertNil(RunHints.shortStride(for: run(pacePerKm: 300, cadence: 176), in: []))
    }

    func testTheSameCadenceIsFineSlowAndShortFast() {
        // 162 is on the mark at 6:00 /km and short at 4:00 /km — which is the
        // whole reason the expectation moves with pace.
        XCTAssertNil(RunHints.shortStride(for: run(pacePerKm: 360, cadence: 162), in: []))
        XCTAssertNotNil(RunHints.shortStride(for: run(pacePerKm: 240, cadence: 162), in: []))
    }

    // MARK: - When it stays quiet

    func testARunWithoutACadenceReadingSaysNothing() {
        XCTAssertNil(RunHints.shortStride(for: run(cadence: nil), in: []))
        XCTAssertNil(RunHints.shortStride(for: run(cadence: 0), in: []))
    }

    func testAJogAroundTheBlockIsNotJudged() {
        XCTAssertNil(RunHints.shortStride(for: run(km: 1.5, pacePerKm: 300, cadence: 150), in: []))
    }

    func testTrailRunsAreLeftAlone() {
        // Cadence on a mountain is set by the ground, not by the runner.
        XCTAssertTrue(RunHints.all(for: run(pacePerKm: 420, cadence: 140, trail: true), in: []).isEmpty)
    }

    func testARoadRunWithNothingToSayProducesNoSection() {
        XCTAssertTrue(RunHints.all(for: run(pacePerKm: 300, cadence: 178), in: []).isEmpty)
    }

    // MARK: - Said once, not after every run

    func testTheStrideHintOnlySpeaksOnTheMostRecentRunThatEarnsIt() {
        let older = run(pacePerKm: 300, cadence: 155, daysAgo: 10)
        let newer = run(pacePerKm: 300, cadence: 155, daysAgo: 2)
        let log = [older, newer]
        // A habit is not a fact about Tuesday: the newest run carries it, and
        // opening one from a fortnight ago is not another lecture.
        XCTAssertNotNil(RunHints.shortStride(for: newer, in: log))
        XCTAssertNil(RunHints.shortStride(for: older, in: log))
    }

    func testARunFollowedOnlyByGoodOnesStillSpeaks() {
        let short = run(pacePerKm: 300, cadence: 155, daysAgo: 10)
        let fixed = run(pacePerKm: 300, cadence: 176, daysAgo: 2)
        XCTAssertNotNil(RunHints.shortStride(for: short, in: [short, fixed]))
    }

    // MARK: - Short for this runner

    func testADropAgainstTheRunnersOwnUsualIsWorthSaying() throws {
        // Someone who normally holds 170 at this pace, on a day they held 160.
        let today = run(pacePerKm: 300, cadence: 160)
        let hint = try XCTUnwrap(RunHints.shorterThanUsual(for: today, in: history(cadence: 170)))
        XCTAssertEqual(hint.kind, .cadenceDrop)
        XCTAssertTrue(hint.body.contains("160"), hint.body)
        XCTAssertTrue(hint.body.contains("170"), hint.body)
    }

    func testALongStridedRunnerHoldingTheirOwnNormalIsLeftAlone() {
        // 158 is under the table's floor, and it is exactly what this runner
        // always does — the personal hint stays quiet. (The stride hint still
        // has its say, once, which is the point of having two.)
        let today = run(pacePerKm: 300, cadence: 158)
        XCTAssertNil(RunHints.shorterThanUsual(for: today, in: history(cadence: 158)))
    }

    func testWithoutEnoughComparableRunsThereIsNoUsual() {
        let today = run(pacePerKm: 300, cadence: 160)
        XCTAssertNil(RunHints.shorterThanUsual(for: today, in: history(cadence: 170, count: 4)))
        // Runs at a different pace are not comparable, however many there are.
        XCTAssertNil(RunHints.shorterThanUsual(for: today,
                                               in: history(cadence: 170, pacePerKm: 420)))
    }
}
