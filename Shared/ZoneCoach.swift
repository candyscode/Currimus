import Foundation

/// Holds a runner in one heart-rate zone by feel alone.
///
/// The zone bar answers "where am I" for anyone who looks at it. Most of a run
/// is spent not looking — and an easy run drifts out of zone 2 slowly enough
/// that nobody notices until the run is over and the chart says so. This turns
/// the same information into something the wrist reports on its own: a nudge
/// while there is still time to correct, an alarm once the zone is gone.
///
/// Pure decision layer, no haptics and no clock of its own — `RunSession`
/// feeds it the tick and plays what it asks for, which is what makes the
/// cadence testable instead of something you can only feel on a wrist.
struct ZoneCoach {
    /// Share of a zone at each end that counts as "about to leave it". 15 % of
    /// a zone is a handful of beats — close enough to act on, far enough that
    /// acting still works.
    static let edgeBand = 0.15
    /// Repeat cadences. Fast pulses mean "lift the pace", slow ones "ease
    /// off", and the two must never be mistaken for each other at 5 a.m. with
    /// a jacket sleeve over the watch.
    static let speedUpInterval: TimeInterval = 3.5
    static let slowDownInterval: TimeInterval = 5
    /// The zone is gone: the alarm fires at once and, if the runner does not
    /// come back, again every minute. Once and never again would be a cue
    /// missed at exactly the moment it mattered.
    static let leftZoneInterval: TimeInterval = 60

    enum Cue: Equatable {
        /// In the bottom 15 % of the target zone — run a little faster.
        case speedUp
        /// In the top 15 % — ease off.
        case slowDown
        /// Out of the target zone altogether, and into this one.
        case leftZone(Int)
    }

    /// The zone the runner asked to be held in.
    var targetZone: Int

    /// The cue that last actually played, and when.
    ///
    /// Kept across a lapse, which is the whole point. It used to be cleared the
    /// moment a cue stopped being true, so a cue that lapsed for one tick and
    /// came back counted as *new* and fired at once — and a heart rate does not
    /// sit still on a zone boundary, it flutters across it. Losing zone 2 for a
    /// second, regaining it, losing it again bought three seconds of buzzing
    /// and a full-screen warning every other tick, which is how a vibration
    /// feature gets switched off for good.
    private var fired: (cue: Cue, at: TimeInterval)?
    /// Whether the target zone has been reached at all yet.
    private var hasArrived = false

    init(targetZone: Int) { self.targetZone = targetZone }

    /// The cue to play right now, or nil for silence.
    ///
    /// `zone` is nil until a heart rate arrives. No reading is not a zone —
    /// there are five, and "none yet" is the absence of one, not a sixth. It
    /// is also not the wrong zone: buzzing at someone because their strap has
    /// not connected is how a feature gets switched off for good.
    mutating func update(zone: Int?, position: Double, now: TimeInterval) -> Cue? {
        if zone == targetZone { hasArrived = true }
        guard let cue = pending(zone: zone, position: position) else { return nil }
        guard let fired else { return play(cue, at: now) }
        // Something genuinely different is said at once; anything else — the
        // same cue still true, or true again — waits for its own cadence.
        if interrupts(cue, playing: fired.cue) { return play(cue, at: now) }
        guard now - fired.at >= Self.interval(for: cue) else { return nil }
        return play(cue, at: now)
    }

    private mutating func play(_ cue: Cue, at now: TimeInterval) -> Cue {
        fired = (cue, now)
        return cue
    }

    /// Whether a cue is different enough from the one last played to cut that
    /// one's cadence short.
    ///
    /// A different *kind* always is: overcorrecting from the bottom of the zone
    /// straight through the top has to be said now, not four seconds from now.
    ///
    /// Two `leftZone` alarms are the same kind, and there the question is
    /// whether it got worse. Drifting from zone 3 to zone 4 with a target of 2
    /// is a new fact; falling back from 4 to 3 is the same alarm from a little
    /// nearer and waits its turn. Treating every change of zone as news meant a
    /// heart rate sitting on the 3/4 boundary alarmed on every other tick.
    private func interrupts(_ cue: Cue, playing previous: Cue) -> Bool {
        switch (cue, previous) {
        case (.leftZone(let now), .leftZone(let before)):
            return abs(now - targetZone) > abs(before - targetZone)
        default:
            return cue != previous
        }
    }

    private func pending(zone: Int?, position: Double) -> Cue? {
        guard let zone else { return nil }
        guard zone == targetZone else {
            // A zone cannot be *left* before it has been reached. The first
            // minutes of any run are spent climbing into it, and three seconds
            // of buzzing plus a full-screen warning for not being there yet is
            // nagging rather than coaching.
            return hasArrived ? .leftZone(zone) : nil
        }
        if position < Self.edgeBand { return .speedUp }
        if position > 1 - Self.edgeBand { return .slowDown }
        return nil
    }

    static func interval(for cue: Cue) -> TimeInterval {
        switch cue {
        case .speedUp: return speedUpInterval
        case .slowDown: return slowDownInterval
        case .leftZone: return leftZoneInterval
        }
    }
}

/// The full-screen warning raised when the target zone is lost — the same
/// treatment as a kilometre split, because it is the same kind of moment: one
/// thing to know, read at arm's length, gone again on its own.
struct ZoneWarning: Equatable {
    var zone: Int
    var targetZone: Int

    /// Whether the runner has to ease off (true) or push (false).
    var isTooHigh: Bool { zone > targetZone }
}
