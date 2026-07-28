import XCTest

/// What the wrist is told, and when.
///
/// The cadence is the whole feature: a cue that never repeats is missed, one
/// that repeats every second is switched off within a kilometre. None of that
/// can be felt in a test, so it is asserted here instead — the coach is a pure
/// decision layer over a clock it is handed, precisely so this is possible.
final class ZoneCoachTests: XCTestCase {
    private func coach(target: Int = 2) -> ZoneCoach { ZoneCoach(targetZone: target) }

    // MARK: - Inside the zone

    func testMiddleOfTheZoneSaysNothing() {
        var coach = coach()
        XCTAssertNil(coach.update(zone: 2, position: 0.5, now: 0))
        XCTAssertNil(coach.update(zone: 2, position: 0.5, now: 60))
    }

    func testBottomOfTheZoneAsksForMorePace() {
        var coach = coach()
        XCTAssertEqual(coach.update(zone: 2, position: 0.10, now: 0), .speedUp)
    }

    func testTopOfTheZoneAsksToEaseOff() {
        var coach = coach()
        XCTAssertEqual(coach.update(zone: 2, position: 0.92, now: 0), .slowDown)
    }

    func testTheEdgeBandIsExactlyFifteenPercent() {
        var low = coach(), high = coach()
        XCTAssertNil(low.update(zone: 2, position: 0.15, now: 0), "0.15 is inside")
        XCTAssertNil(high.update(zone: 2, position: 0.85, now: 0), "0.85 is inside")
        XCTAssertEqual(low.update(zone: 2, position: 0.149, now: 1), .speedUp)
        XCTAssertEqual(high.update(zone: 2, position: 0.851, now: 1), .slowDown)
    }

    // MARK: - Cadence

    func testACueRepeatsOnItsOwnCadenceRatherThanEverySecond() {
        var coach = coach()
        XCTAssertEqual(coach.update(zone: 2, position: 0.1, now: 0), .speedUp)
        // Still low, but far too soon to buzz again.
        XCTAssertNil(coach.update(zone: 2, position: 0.1, now: 1))
        XCTAssertNil(coach.update(zone: 2, position: 0.1, now: 3))
        XCTAssertEqual(coach.update(zone: 2, position: 0.1, now: 3.5), .speedUp)
    }

    func testSlowDownRepeatsMoreSlowlyThanSpeedUp() {
        XCTAssertGreaterThan(ZoneCoach.interval(for: .slowDown),
                             ZoneCoach.interval(for: .speedUp))
    }

    func testAChangedCueFiresImmediatelyRatherThanWaitingItsTurn() {
        var coach = coach()
        XCTAssertEqual(coach.update(zone: 2, position: 0.1, now: 0), .speedUp)
        // Overcorrected straight through the zone — that has to be said now,
        // not four seconds from now.
        XCTAssertEqual(coach.update(zone: 2, position: 0.95, now: 1), .slowDown)
    }

    func testReturningToTheMiddleClearsTheCadence() {
        var coach = coach()
        XCTAssertEqual(coach.update(zone: 2, position: 0.1, now: 0), .speedUp)
        XCTAssertNil(coach.update(zone: 2, position: 0.5, now: 1))
        // Drifting low again is news, whatever the clock says.
        XCTAssertEqual(coach.update(zone: 2, position: 0.1, now: 2), .speedUp)
    }

    // MARK: - Losing the zone

    func testLeavingTheZoneRaisesTheAlarmAtOnce() {
        var coach = coach()
        XCTAssertEqual(coach.update(zone: 3, position: 0.3, now: 10), .leftZone(3))
    }

    func testTheAlarmRepeatsEveryMinuteWhileTheZoneIsStillLost() {
        var coach = coach()
        XCTAssertEqual(coach.update(zone: 3, position: 0.3, now: 0), .leftZone(3))
        XCTAssertNil(coach.update(zone: 3, position: 0.3, now: 30))
        XCTAssertEqual(coach.update(zone: 3, position: 0.3, now: 60), .leftZone(3))
    }

    func testDriftingIntoAnotherWrongZoneIsItsOwnAlarm() {
        var coach = coach()
        XCTAssertEqual(coach.update(zone: 3, position: 0.9, now: 0), .leftZone(3))
        XCTAssertEqual(coach.update(zone: 4, position: 0.1, now: 5), .leftZone(4))
    }

    func testNoHeartRateIsNotTheWrongZone() {
        var coach = coach()
        // There is no zone for "no reading yet" — there are five zones, and
        // this is the absence of one. Buzzing at someone because their strap
        // has not connected is how a feature gets switched off for good.
        XCTAssertNil(coach.update(zone: nil, position: 0.5, now: 0))
        XCTAssertNil(coach.update(zone: nil, position: 0.5, now: 120))
    }

    // MARK: - The warning itself

    func testTheWarningKnowsWhichWayToSendTheRunner() {
        XCTAssertTrue(ZoneWarning(zone: 3, targetZone: 2).isTooHigh)
        XCTAssertFalse(ZoneWarning(zone: 1, targetZone: 2).isTooHigh)
    }
}
