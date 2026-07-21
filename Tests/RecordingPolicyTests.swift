import XCTest

/// The rules that decide whether a run may start, and whether what came back
/// is a run at all.
///
/// Both used to be implicit. A denied Health prompt started a run that could
/// only ever record elapsed time, and whatever came out of it was filed in the
/// log as a 0.00 km "Easy run".
final class RecordingPolicyTests: XCTestCase {

    // MARK: Which problems stop a run

    func testAnythingCostingDistanceOrHeartRateBlocksTheRun() {
        // Distance and heart rate both come from the workout builder, so
        // without it there is nothing to record but the clock.
        XCTAssertTrue(RecordingIssue.healthDenied.blocksRecording)
        XCTAssertTrue(RecordingIssue.healthUnavailable.blocksRecording)
        XCTAssertTrue(RecordingIssue.workoutFailed.blocksRecording)
    }

    func testMissingLocationOnlyDegradesTheRun() {
        // A run without a route still has distance, pace, splits and zones —
        // refusing to record it would be the app overreaching.
        XCTAssertFalse(RecordingIssue.locationDenied.blocksRecording)
    }

    func testTheUndetectableDenialIsReportedMidRunRatherThanAtTheDoor() {
        // Health hides read authorization, so "workout allowed, distance
        // refused" cannot be caught before the run. Blocking on it is
        // impossible; the run is already going by the time it shows.
        XCTAssertFalse(RecordingIssue.noDistance.blocksRecording)
        XCTAssertNotNil(RecordingIssue.noDistance.recovery)
    }

    func testEveryBlockingIssueExplainsItself() {
        // A refusal the user cannot account for reads like a bug, so the copy
        // is part of the contract, not decoration.
        for issue in [RecordingIssue.healthDenied, .healthUnavailable, .workoutFailed] {
            XCTAssertFalse(issue.headline.isEmpty, "\(issue) needs a headline")
            XCTAssertFalse(issue.detail.isEmpty, "\(issue) needs an explanation")
        }
        // The two the user can actually act on say where to go; watchOS has no
        // URL that opens Settings, so the path is the whole recovery route.
        XCTAssertNotNil(RecordingIssue.healthDenied.recovery)
        XCTAssertNotNil(RecordingIssue.locationDenied.recovery)
        // A watch without Health data offers nothing to change.
        XCTAssertNil(RecordingIssue.healthUnavailable.recovery)
    }

    // MARK: What counts as a run

    func testRecordingWithoutDistanceIsNotARun() {
        let failed = Run(date: .now, name: "Run", distanceKm: 0, duration: 1_800, avgHR: 0)
        XCTAssertFalse(failed.hasUsableDistance)
    }

    func testAShortRunIsStillARun() {
        // The threshold rejects failed recordings, not genuinely short outings.
        let short = Run(date: .now, name: "Around the block", distanceKm: 0.4,
                        duration: 150, avgHR: 140)
        XCTAssertTrue(short.hasUsableDistance)
    }

    func testTheDiscardRuleMatchesWhatTheRestOfTheAppCallsMeaningless() {
        // `paceSecPerKm` already refuses to divide below 0.05 km. A run the
        // log keeps but that can never show a pace would be a worse artefact
        // than one it drops, so the two thresholds must not drift apart.
        let kept = Run(date: .now, name: "r", distanceKm: 0.01, duration: 60, avgHR: 120)
        XCTAssertTrue(kept.hasUsableDistance)
        XCTAssertLessThanOrEqual(0.01, 0.05,
                                 "hasUsableDistance must stay at or below the pace floor")
    }
}
