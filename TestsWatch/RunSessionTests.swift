import XCTest

/// What `RunSession` does around the arithmetic.
///
/// The per-second maths is `RunMetrics`, driven headlessly through every awkward
/// scenario in `RunSimulationTests`. None of that reaches this file. What is
/// tested here is the shell: the run that comes out at the end, the phase
/// machine, what survives from one run into the next, and the pacer's two lines
/// of forecasting.
///
/// Everything is driven through `debugJumpScenario`, which plays a `RunScenario`
/// second by second with no timer and no randomness — the same scenarios the
/// headless simulator asserts on. A `begin()` would start a real 1 Hz timer and
/// make every assertion below a race.
@MainActor
final class RunSessionTests: XCTestCase {

    private func session(coaching zone: Int? = nil) -> RunSession {
        let session = RunSession()
        session.zones = HRZones(maxHR: 190)
        session.zoneCoachTarget = zone
        return session
    }

    /// A finished road run, played to its end.
    private func finishedMarathon() -> (session: RunSession, run: Run, startedAt: Date) {
        let session = session()
        let before = Date.now
        session.debugJumpScenario(.marathon)
        return (session, session.end(), before)
    }

    // MARK: - The run that comes out at the end

    /// `end()` assembles fifteen fields out of four sources. This is the one
    /// place where a mistake becomes a wrong entry in the runner's log.
    func testAFinishedRunCarriesWhatWasRecorded() {
        let (session, run, _) = finishedMarathon()

        XCTAssertEqual(run.type, .quick)
        XCTAssertEqual(run.duration, session.elapsed, accuracy: 0.001)
        XCTAssertEqual(run.distanceKm, 42.195, accuracy: 0.3)
        XCTAssertEqual(run.splits.count, 42, "one split per completed kilometre")
        XCTAssertEqual(run.avgHR, session.averageHR)
        XCTAssertGreaterThan(run.avgHR, 0)
        XCTAssertNotNil(run.route)
        XCTAssertTrue(run.hasUsableDistance)
        XCTAssertNil(run.imported)
        XCTAssertNil(run.isIndoor)
    }

    /// The distance is filed to two decimals, which is what the log prints.
    /// Rounding at the door rather than at each of the six places that read it.
    func testTheFiledDistanceIsRoundedOnce() {
        let (_, run, _) = finishedMarathon()
        XCTAssertEqual(run.distanceKm, (run.distanceKm * 100).rounded() / 100)
    }

    /// The start time is the wall clock, not `now - elapsed`.
    ///
    /// `elapsed` excludes pauses, so deriving the start from it walked the start
    /// time of every paused run forward — by exactly the length of the pauses.
    /// A three-hour marathon with a ten-minute stop was filed as having begun
    /// ten minutes after it did.
    func testTheStartTimeIsWhenTheRunStartedNotWhenItsClockSaysSo() {
        let (session, run, startedAt) = finishedMarathon()
        XCTAssertEqual(run.date.timeIntervalSince(startedAt), 0, accuracy: 2,
                       "the run began when it began")
        // And emphatically not the other reading, which for a marathon is three
        // and a half hours out.
        XCTAssertGreaterThan(abs(run.date.timeIntervalSince(.now - session.elapsed)),
                             session.elapsed / 2)
    }

    /// Time and ground in each zone both come out, and both describe the run.
    /// The distance half is what makes "pace in zone 2" a measurement.
    func testZoneTimeAndZoneDistanceBothSurviveTheFinish() {
        let (_, run, _) = finishedMarathon()
        XCTAssertEqual(run.zoneSeconds.count, 5)
        XCTAssertEqual(run.zoneSeconds.reduce(0, +), run.duration, accuracy: run.duration * 0.02)

        let perZone = try? XCTUnwrap(run.zoneDistanceKm)
        XCTAssertEqual(perZone?.count, 5)
        XCTAssertEqual(perZone?.reduce(0, +) ?? 0, run.distanceKm, accuracy: 0.5,
                       "every kilometre belongs to the zone it was run in")
    }

    /// Climb, descent and the high point are whole metres, and the high point
    /// is the highest sample rather than the last one.
    func testATrailRunFilesItsClimbAsWholeMetres() {
        let session = session()
        session.debugJumpScenario(.trailUltra)
        let run = session.end()

        XCTAssertEqual(run.type, .trail)
        let climb = (try? XCTUnwrap(run.climbMeters)) ?? 0
        XCTAssertGreaterThan(climb, 500)
        XCTAssertEqual(climb, climb.rounded(), "whole metres")
        XCTAssertEqual((run.descentMeters ?? -1).rounded(), run.descentMeters ?? -1)
        XCTAssertEqual(run.highPointMeters, session.altitudeProfile.max()?.rounded())
        XCTAssertNotNil(run.altitudeSamples)
    }

    /// A treadmill run has no track, and the fields that need one stay empty
    /// rather than being filled with zeroes that would read as measurements.
    func testATreadmillRunFilesNoRouteAndNoGradeAdjustment() {
        let session = session()
        session.debugJumpScenario(.treadmill)
        let run = session.end()

        XCTAssertGreaterThan(run.distanceKm, 1)
        XCTAssertNil(run.route, "nothing was tracked, so nothing is claimed")
        XCTAssertNil(run.altitudeSamples)
        XCTAssertNil(run.gradeAdjustedSecPerKm, "a gradient needs a track")
    }

    /// The flat-equivalent pace is worked out at the finish, from the run's own
    /// gradients — not left to the rule of thumb the iPhone falls back on.
    func testARunWithATrackFilesItsOwnGradeAdjustment() {
        let session = session()
        session.debugJumpScenario(.trailUltra)
        let run = session.end()
        let measured = (try? XCTUnwrap(run.gradeAdjustedSecPerKm)) ?? 0
        XCTAssertGreaterThan(measured, 0)
        XCTAssertLessThan(measured, run.paceSecPerKm,
                          "climbing on the flat would have been faster")
        XCTAssertTrue(RunAnalytics.hasMeasuredGradeAdjustment(run))
    }

    /// Cadence is a missing measurement, not a zero, when nothing counted steps.
    /// A simulated run has no pedometer.
    func testNoStepsMeansNoCadenceRatherThanZero() {
        let (session, run, _) = finishedMarathon()
        XCTAssertEqual(session.steps, 0)
        XCTAssertNil(run.cadenceSpm)
        XCTAssertNil(session.cadenceSpm)
    }

    /// A recording that measured no distance is not a run. It used to be sent
    /// to the phone anyway, which made the watch's own "this is not being
    /// saved" a false statement and filled the log with 0.00 km entries.
    func testARecordingThatMeasuredNothingIsNotARun() {
        let session = session()
        let run = session.end()   // never started, so nothing was measured
        XCTAssertFalse(run.hasUsableDistance)
        XCTAssertEqual(run.distanceKm, 0)
    }

    // MARK: - The phase machine

    func testPausingAndResumingOnlyWorkFromTheStateThatAllowsIt() {
        let session = session()
        XCTAssertEqual(session.phase, .idle)

        // Nothing to pause yet.
        session.pause()
        XCTAssertEqual(session.phase, .idle)
        session.resume()
        XCTAssertEqual(session.phase, .idle)

        session.debugJumpScenario(.marathon, toKm: 1)
        XCTAssertEqual(session.phase, .running)

        session.pause()
        XCTAssertEqual(session.phase, .paused)
        // Pausing twice is not resuming.
        session.pause()
        XCTAssertEqual(session.phase, .paused)
        session.resume()
        XCTAssertEqual(session.phase, .running)
    }

    func testTheCountdownCanBeSkippedOnlyWhileItIsRunning() {
        let session = session()
        session.debugJumpScenario(.marathon, toKm: 1)
        XCTAssertEqual(session.phase, .running)
        // A tap on a running screen pauses; it must not be read as a skip.
        session.skipCountdown()
        XCTAssertEqual(session.phase, .running)
    }

    /// A refusal is a phase, and leaving it clears the issues with it —
    /// otherwise the next run opens carrying the last one's complaint.
    func testResetLeavesABlockedRunWithoutItsComplaint() {
        let session = session()
        session.debugBlock(.healthDenied)
        XCTAssertEqual(session.phase, .blocked(.healthDenied))

        session.debugRaiseIssue(.noDistance)
        XCTAssertFalse(session.issues.isEmpty)

        session.reset()
        XCTAssertEqual(session.phase, .idle)
        XCTAssertTrue(session.issues.isEmpty)
    }

    func testFinishingLeavesTheSessionInItsSummaryPhase() {
        let session = session()
        session.debugJumpScenario(.marathon, toKm: 2)
        _ = session.end()
        XCTAssertEqual(session.phase, .finished)
    }

    // MARK: - What one run must not carry into the next

    /// The warning belongs to the run that raised it.
    ///
    /// A tiny second leg on purpose: long enough for the reset to run, short
    /// enough that no cue of its own could fire and mask a reset that did not
    /// happen.
    func testANewRunStartsWithoutTheLastRunsWarning() {
        let session = session(coaching: 2)
        session.debugJumpScenario(.marathon, toKm: 1)
        session.zoneWarning = ZoneWarning(zone: 4, targetZone: 2)
        _ = session.end()

        session.debugJumpScenario(.marathon, toKm: 0.01)
        XCTAssertNil(session.zoneWarning, "the last run's warning is not this run's news")
    }

    /// A second run is coached, and coached at the same point as the first.
    ///
    /// The comment on `resetMetrics` describes a coach carried over from the
    /// previous run bringing its clock with it: `lastFired` sitting half an hour
    /// in the *future* of a run that has just started, so the cadence never
    /// elapses. This asserts the outcome that matters — the second run is
    /// coached, at the same second the first one was.
    ///
    /// Worth knowing, because I checked: deleting the line in `resetMetrics`
    /// that rebuilds the coach does **not** make this fail. A stale coach
    /// recovers as soon as the runner passes back through the target zone,
    /// because a cue of a different *kind* interrupts the cadence outright
    /// (`ZoneCoach.interrupts`) — and every run climbs through its target zone
    /// on the way up. So that line is defensive rather than load-bearing, and no
    /// honest test proves otherwise. It stays because relying on that rescue
    /// would be relying on a detail of another type.
    ///
    /// Observed through `zoneWarning`, the one cue that reaches a published
    /// property. The marathon scenario ramps from 82 bpm to 158, climbing into
    /// zone 2 and straight out the top of it — the sequence that raises the
    /// alarm at all.
    func testASecondRunIsCoachedAtTheSamePointAsTheFirst() {
        let first = session(coaching: 2)
        first.debugJumpScenario(.marathon, toKm: 1)
        XCTAssertNotNil(first.zoneWarning,
                        "precondition: leaving the target zone is announced")

        let session = session(coaching: 2)
        session.debugJumpScenario(.marathon, toKm: 1)
        _ = session.end()
        session.debugJumpScenario(.marathon, toKm: 1)
        XCTAssertNotNil(session.zoneWarning,
                        "the second run must be coached too, not sat out in silence")
    }

    /// Coaching only happens if it was switched on. Off is silent.
    func testWithoutATargetZoneNothingIsCoached() {
        let session = session(coaching: nil)
        session.debugJumpScenario(.marathon, toKm: 6)
        XCTAssertNil(session.zoneWarning)
    }

    /// Scenario playback coaches at all.
    ///
    /// It did not: `scenarioSecond` never asked the coach anything, while the
    /// demo simulation next door did. CUR-6 says the cues run in the simulator
    /// because no simulated wrist has a pulse — that was only true of the other
    /// simulation, so the one path that plays a *known* heart-rate trace was the
    /// one path where the coaching could not be watched.
    func testScenarioPlaybackRunsTheCoachingToo() {
        let session = session(coaching: 2)
        session.debugJumpScenario(.marathon, toKm: 2)
        XCTAssertNotNil(session.zoneWarning,
                        "a scenario is the one place a cue can be checked against a known trace")
    }

    /// A second run starts from zero on every counter the screens read.
    ///
    /// Driven up a mountain rather than along a road: the trail scenario climbs
    /// steadily, so five kilometres of it are unmistakably more than one. The
    /// road scenario's altitude is a gentle sine, and its accumulated climb is
    /// not monotonic in distance at all — a bad witness for "did this restart".
    func testASecondRunDoesNotInheritTheFirstOnesNumbers() {
        let session = session()
        session.debugJumpScenario(.trailUltra, toKm: 5)
        let first = session.end()
        XCTAssertGreaterThan(first.distanceKm, 4)
        XCTAssertGreaterThan(first.climbMeters ?? 0, 0)

        session.debugJumpScenario(.trailUltra, toKm: 1)
        XCTAssertLessThan(session.distanceKm, 2, "distance restarted")
        XCTAssertLessThan(session.elapsed, first.duration)
        XCTAssertEqual(session.splits.count, 1)
        XCTAssertLessThan(session.climbMeters, first.climbMeters ?? 0, "climb restarted")
        XCTAssertLessThan(session.zoneSeconds.reduce(0, +),
                          first.zoneSeconds.reduce(0, +), "zone time restarted")
    }

    /// Switching the target zone rebuilds the coach rather than retuning one
    /// that still holds the old zone's cadence.
    func testChangingTheTargetZoneTakesEffectWithoutARestart() {
        let session = session(coaching: 2)
        session.debugJumpScenario(.marathon, toKm: 1)
        session.zoneCoachTarget = 4
        XCTAssertEqual(session.zoneCoachTarget, 4)
        // Turning it off must leave nothing behind that could still fire.
        session.zoneCoachTarget = nil
        session.debugJumpScenario(.marathon, toKm: 1)
        XCTAssertNil(session.zoneWarning)
    }

    // MARK: - What the run screen reads

    /// Zone 0 is "no reading yet", not zone 1. The bar draws it as an unlit
    /// track, and the coach is handed the absence rather than a wrong zone.
    func testNoHeartRateIsZoneZeroAndNotZoneOne() {
        let session = session()
        XCTAssertEqual(session.heartRate, 0)
        XCTAssertEqual(session.currentZone, 0)
        // Note the trap this guards: the zones themselves answer 1 for a
        // reading of nothing, because 0 is below every boundary.
        XCTAssertEqual(session.zones.zone(for: 0), 1)
    }

    func testAveragePaceNeedsEnoughGroundToBeAPace() {
        let session = session()
        XCTAssertEqual(session.averagePace, 0, "no distance is not a pace")
        session.debugJumpScenario(.marathon, toKm: 2)
        XCTAssertEqual(session.averagePace, session.elapsed / session.distanceKm,
                       accuracy: 0.01)
    }

    func testCadenceWaitsForEnoughOfARunToDivideBy() {
        let session = session()
        session.debugJumpScenario(.marathon, toKm: 0.05)   // well under a minute
        XCTAssertLessThan(session.elapsed, 60)
        XCTAssertNil(session.cadenceSpm)
    }

    // MARK: - The pacer's two lines of arithmetic

    /// Behind schedule is positive, ahead is negative — the sign the gauge and
    /// the caption both read.
    func testScheduleDeltaIsPositiveWhenBehindTarget() {
        let session = session()
        session.pacerTarget = 300
        session.debugJumpScenario(.pacerOnTarget, toKm: 3)

        let expected = session.elapsed - session.distanceKm * session.pacerTarget
        XCTAssertEqual(session.scheduleDelta, expected, accuracy: 0.001)
        // On target, by construction, so neither far ahead nor far behind.
        XCTAssertLessThan(abs(session.scheduleDelta), 90)
    }

    /// The forecast is "if you hold target pace from here", not "at the pace you
    /// are running". Written down because it is a choice, and reading it as the
    /// other one would make a runner think the remaining kilometres were being
    /// projected from their current effort.
    func testTheFinishForecastAssumesTargetPaceForWhatIsLeft() {
        let session = session()
        session.pacerTarget = 300
        session.debugJumpScenario(.pacerOnTarget, toKm: 4)

        let target = try? XCTUnwrap(session.pacerDistanceKm)
        let forecast = try? XCTUnwrap(session.finishForecast)
        let remaining = (target ?? 0) - session.distanceKm
        XCTAssertEqual(forecast ?? 0, session.elapsed + remaining * session.pacerTarget,
                       accuracy: 0.001)
    }

    /// No target distance means no finish to forecast — an open-ended pacer run
    /// must not invent one.
    func testAnOpenEndedPacerRunHasNoFinishToForecast() {
        let session = session()
        session.pacerTarget = 300
        session.pacerDistanceKm = nil
        XCTAssertNil(session.finishForecast)
    }

    /// Pace delta is blank rather than wrong before there is a rolling pace.
    func testPaceDeltaSaysNothingBeforeThereIsAPace() {
        let session = session()
        session.pacerTarget = 300
        XCTAssertEqual(session.rollingPace, 0)
        XCTAssertEqual(session.paceDelta, 0, "not −300")
    }

    // MARK: - Phase steps for the pacer setup

    func testThePacerIsSetUpInTwoSteps() {
        let session = session()
        session.setupPacer()
        XCTAssertEqual(session.phase, .pacerPace)
        XCTAssertEqual(session.type, .pacer)
        session.confirmPacerPace()
        XCTAssertEqual(session.phase, .pacerDistance)
    }
}
