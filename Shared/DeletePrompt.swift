import Foundation

/// How a delete is phrased. Lives beside the model rather than beside the
/// screens, for the same reason `LogRowText` does: it is text derived from a
/// `[Run]` and nothing else, and text that makes a claim to the user belongs
/// somewhere a test can read it. It could not be, in `iOS/` — the test target
/// compiles `Tests` and `Shared`, so nothing in `iOS/` is reachable from a
/// test at all.
/// One place decides how a delete is phrased, because the log, the selection
/// mode and the run detail all ask the same question and must ask it the same
/// way — including the part people actually need to know, which is that this
/// reaches Apple Health.
enum DeletePrompt {
    static func title(_ runs: [Run]) -> String {
        runs.count == 1
            ? String(localized: "Delete this run?")
            : String(localized: "Delete \(runs.count) runs?")
    }

    /// Why a run another app recorded cannot be deleted here. Named plainly,
    /// because "not possible" without a reason reads as a bug in Currimus.
    ///
    /// Deliberately without naming the source. `sourceRevision.source.name` is
    /// the app's name only for third-party apps — for a workout Apple's own
    /// Workout app recorded it is the *device* name, and "delete it in Andi's
    /// Apple Watch" sends someone to a watch when the answer is the Fitness app
    /// on their phone. A sentence that is right for Strava and wrong for the
    /// Apple Watch is worse than one that names nothing and points at Fitness,
    /// which works either way.
    static func importedExplanation(_ run: Run) -> String {
        String(localized: "This run was recorded outside Currimus, and Apple Health only lets the app that recorded a run delete it. Remove it there, or in the Fitness app, and it will disappear from Currimus on the next refresh.")
    }

    static func message(_ runs: [Run]) -> String {
        let km = Format.km(runs.reduce(0) { $0 + $1.distanceKm }, decimals: 1)
        if let run = runs.first, runs.count == 1 {
            let day = run.date.formatted(.dateTime.day().month(.wide))
            return String(localized: "\(Format.km(run.distanceKm)) km, \(day). Every total and record is recalculated without it, and the workout is removed from Apple Health.")
        }
        return String(localized: "\(runs.count) runs, \(km) km in total. Every total and record is recalculated without them, and their workouts are removed from Apple Health.")
    }
}
