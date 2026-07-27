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

    private var lastCue: Cue?
    private var lastFired: TimeInterval?

    init(targetZone: Int) { self.targetZone = targetZone }

    /// The cue to play right now, or nil for silence.
    ///
    /// `zone` is 0 until a heart rate arrives — no reading is not the same as
    /// the wrong zone, and buzzing at someone because their strap has not
    /// connected yet is how a feature gets switched off for good.
    mutating func update(zone: Int, position: Double, now: TimeInterval) -> Cue? {
        let cue = pending(zone: zone, position: position)
        defer { lastCue = cue }
        guard let cue else {
            lastFired = nil
            return nil
        }
        // A cue that has just changed fires immediately; one that is still
        // true repeats on its own cadence, so standing at the bottom of the
        // zone keeps telling the runner without buzzing every single second.
        guard cue == lastCue, let lastFired else {
            self.lastFired = now
            return cue
        }
        guard now - lastFired >= Self.interval(for: cue) else { return nil }
        self.lastFired = now
        return cue
    }

    private func pending(zone: Int, position: Double) -> Cue? {
        guard zone > 0 else { return nil }
        guard zone == targetZone else { return .leftZone(zone) }
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
