import Foundation

/// What the run says about how it was run, rather than how fast.
///
/// Distance, pace and heart rate describe the effort; nothing in the log has
/// ever described the *running*. This is where that goes — one hint for now,
/// room for more, and a shape that will take an AI-written one later without
/// the detail screen changing: a hint is a title, a body, and the reason it
/// fired, and the screen renders whatever the list contains.
///
/// The rules are deliberately reluctant. A screen that finds something to
/// correct after every single run is a screen people stop reading, so a hint
/// has to clear a real margin before it says anything at all.
struct RunHint: Identifiable, Equatable {
    enum Kind: String { case cadence }

    var kind: Kind
    var title: String
    var body: String

    var id: String { kind.rawValue }
}

enum RunHints {
    /// Every hint this run has earned, best first. Empty is the common case
    /// and the screen shows nothing at all for it.
    ///
    /// Trail is out: cadence on a mountain is set by the ground — switchbacks,
    /// rock, a 20 % pitch — and telling someone to take quicker steps up a
    /// scramble is advice about a run they did not do.
    static func all(for run: Run) -> [RunHint] {
        guard !run.isTrail else { return [] }
        return [cadence(for: run)].compactMap { $0 }
    }

    // MARK: - Cadence

    /// The step rate a run at this pace would usually sit at.
    ///
    /// There is no single right number. The famous "180" came from watching
    /// elites race, and studies of recreational runners find preferred
    /// cadences spread widely at any given ability — so this is not a target,
    /// it is the floor below which a stride is probably reaching out in front
    /// of the runner instead of landing under them. Cadence rises with speed,
    /// hence the ramp: roughly 158 at a 7:00/km jog, 168 at 5:00/km, 178 near
    /// 4:00/km, and it stops climbing at 182 because that is elite territory
    /// and no one needs to be told they are short of it.
    static func expectedCadence(forPaceSecPerKm pace: TimeInterval) -> Double {
        let anchors: [(pace: TimeInterval, spm: Double)] = [
            (420, 158),   // 7:00 /km
            (360, 162),   // 6:00 /km
            (300, 168),   // 5:00 /km
            (240, 178),   // 4:00 /km
            (200, 182),   // 3:20 /km
        ]
        if pace >= anchors[0].pace { return anchors[0].spm }
        if pace <= anchors[anchors.count - 1].pace { return anchors[anchors.count - 1].spm }
        for index in 1..<anchors.count {
            let (fastPace, fastSpm) = anchors[index]
            let (slowPace, slowSpm) = anchors[index - 1]
            guard pace >= fastPace else { continue }
            let share = (slowPace - pace) / (slowPace - fastPace)
            return slowSpm + share * (fastSpm - slowSpm)
        }
        return anchors[anchors.count - 1].spm
    }

    /// How far below the expected rate a run has to sit before this is worth
    /// saying. Cadence wanders by a couple of steps between runs on its own.
    static let cadenceTolerance: Double = 5

    /// The one hint that exists so far.
    ///
    /// The evidence it rests on: raising cadence 5–10 % without changing pace
    /// shortens the stride and drops the energy the knee has to absorb per
    /// step by roughly a fifth to a third (Heiderscheit et al., 2011, and the
    /// cadence-retraining work since). It is the cheapest change in running
    /// form there is — nothing to buy, nothing to relearn.
    static func cadence(for run: Run) -> RunHint? {
        guard let cadence = run.cadenceSpm, cadence > 0,
              run.hasUsableDistance, run.paceSecPerKm > 0,
              // A kilometre of jogging says nothing about anyone's form.
              run.distanceKm >= 2 else { return nil }
        let expected = expectedCadence(forPaceSecPerKm: run.paceSecPerKm)
        guard Double(cadence) < expected - cadenceTolerance else { return nil }

        // Five per cent of what they actually did, not the textbook number:
        // the change has to be reachable on the next run to be worth writing.
        let target = Int((Double(cadence) * 1.05).rounded())
        return RunHint(
            kind: .cadence,
            title: String(localized: "Try shorter, quicker steps"),
            body: String(localized: "You held \(cadence) steps a minute at \(Format.pace(run.paceSecPerKm)) /km. Aiming for about \(target) — five per cent quicker — shortens the stride without changing the pace, so the foot lands under you instead of out in front. That is where most of the impact your knees absorb comes from. It helps to imagine running on a slippery path: short, light, frequent steps.")
        )
    }
}
