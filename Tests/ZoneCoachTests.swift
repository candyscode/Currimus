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

    /// A cue that lapses and comes back is the same cue, not news.
    ///
    /// This test used to assert the opposite — "drifting low again is news,
    /// whatever the clock says" — and that was the bug behind CUR-30. A heart
    /// rate does not sit still on the 15 % line, it flutters across it, so
    /// "whatever the clock says" meant a cue every other tick. Drifting low
    /// again *is* news; it is news at the cue's own cadence.
    func testACueThatLapsedForATickDoesNotStartOver() {
        var coach = coach()
        XCTAssertEqual(coach.update(zone: 2, position: 0.1, now: 0), .speedUp)
        XCTAssertNil(coach.update(zone: 2, position: 0.5, now: 1))
        XCTAssertNil(coach.update(zone: 2, position: 0.1, now: 2),
                     "fluttering across the band edge must not re-fire")
        // Once its own cadence has passed it says so again, lapse or no lapse.
        XCTAssertEqual(coach.update(zone: 2, position: 0.1, now: 3.5), .speedUp)
    }

    /// Correcting properly and drifting back minutes later is a fresh cue.
    func testDriftingLowAgainMuchLaterStillSpeaks() {
        var coach = coach()
        XCTAssertEqual(coach.update(zone: 2, position: 0.1, now: 0), .speedUp)
        XCTAssertNil(coach.update(zone: 2, position: 0.5, now: 60))
        XCTAssertEqual(coach.update(zone: 2, position: 0.1, now: 600), .speedUp)
    }

    /// The one that mattered: three seconds of buzzing plus a full-screen
    /// warning must not restart every time the zone is briefly regained.
    func testTheAlarmDoesNotRestartOnAOneTickReturnToTheZone() {
        var coach = coach()
        XCTAssertNil(coach.update(zone: 2, position: 0.5, now: 0))
        XCTAssertEqual(coach.update(zone: 3, position: 0.5, now: 1), .leftZone(3))
        for second in stride(from: 2.0, through: 20.0, by: 2) {
            XCTAssertNil(coach.update(zone: 2, position: 0.5, now: second),
                         "back inside the zone says nothing")
            XCTAssertNil(coach.update(zone: 3, position: 0.5, now: second + 1),
                         "and losing it again inside the minute is the same alarm")
        }
        XCTAssertEqual(coach.update(zone: 3, position: 0.5, now: 61), .leftZone(3))
    }

    /// Nor may it restart because the heart rate crossed a boundary between two
    /// zones that are *both* wrong.
    func testFlutteringBetweenTwoWrongZonesIsOneAlarm() {
        var coach = coach()
        XCTAssertNil(coach.update(zone: 2, position: 0.5, now: 0))
        XCTAssertEqual(coach.update(zone: 4, position: 0.5, now: 1), .leftZone(4))
        // Nearer the target than the alarm that already played: same alarm.
        XCTAssertNil(coach.update(zone: 3, position: 0.5, now: 2))
        XCTAssertNil(coach.update(zone: 4, position: 0.5, now: 3))
        XCTAssertNil(coach.update(zone: 3, position: 0.5, now: 4))
    }

    // MARK: - Losing the zone

    func testLeavingTheZoneRaisesTheAlarmAtOnce() {
        var coach = coach()
        // Arrived in zone 2 first, as every run does.
        XCTAssertNil(coach.update(zone: 2, position: 0.5, now: 5))
        XCTAssertEqual(coach.update(zone: 3, position: 0.3, now: 10), .leftZone(3))
    }

    func testTheWarmUpIsNotTreatedAsLeavingTheZone() {
        var coach = coach()
        // The first minutes of a run are spent climbing into the zone. Three
        // seconds of buzzing and a full-screen warning for not being there yet
        // is nagging, not coaching.
        XCTAssertNil(coach.update(zone: 1, position: 0.4, now: 0))
        XCTAssertNil(coach.update(zone: 1, position: 0.6, now: 60))
        XCTAssertNil(coach.update(zone: 1, position: 0.9, now: 120))
        // Reached it — and dropping out of it now is worth saying.
        XCTAssertNil(coach.update(zone: 2, position: 0.5, now: 180))
        XCTAssertEqual(coach.update(zone: 1, position: 0.9, now: 240), .leftZone(1))
    }

    func testTheAlarmRepeatsEveryMinuteWhileTheZoneIsStillLost() {
        var coach = coach()
        XCTAssertNil(coach.update(zone: 2, position: 0.5, now: -5))
        XCTAssertEqual(coach.update(zone: 3, position: 0.3, now: 0), .leftZone(3))
        XCTAssertNil(coach.update(zone: 3, position: 0.3, now: 30))
        XCTAssertEqual(coach.update(zone: 3, position: 0.3, now: 60), .leftZone(3))
    }

    func testDriftingIntoAnotherWrongZoneIsItsOwnAlarm() {
        var coach = coach()
        XCTAssertNil(coach.update(zone: 2, position: 0.5, now: -5))
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
