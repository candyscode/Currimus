import Foundation

/// Pure functions over `[Run]` — race prediction, personal records, trends,
/// grade-adjusted pace. Kept free of UI and storage so it is fully unit-tested.
enum RunAnalytics {

    // MARK: - Riegel race prediction

    /// Riegel's endurance model: T₂ = T₁ · (D₂/D₁)^1.06.
    /// Widely used, and honest for nearby distances; extrapolating a 10K to a
    /// marathon is optimistic (endurance a short race never shows). Callers
    /// should present the result as an estimate.
    static func riegel(knownTime: TimeInterval, knownKm: Double, targetKm: Double,
                       exponent: Double = 1.06) -> TimeInterval {
        guard knownKm > 0, knownTime > 0 else { return 0 }
        return knownTime * pow(targetKm / knownKm, exponent)
    }

    /// The PR the prediction is based on, and the predicted finish for a race.
    struct Prediction {
        var time: TimeInterval
        var basisLabel: String       // e.g. "10K PR"
        /// True when the longest run is far short of the race — the estimate
        /// is then especially optimistic and we say so.
        var underTrained: Bool
    }

    /// Predict a race finish. Prefers the 10K PR (as the design does), else the
    /// best shorter benchmark available.
    static func predict(race: Race, runs: [Run]) -> Prediction? {
        let prs = personalBests(runs: runs)
        // Prefer 10K, then 5K, then half — a benchmark shorter than the race.
        let candidates: [(km: Double, label: String)] = [
            (10, "10K PR"), (5, "5K PR"), (21.0975, "Half PR"),
        ]
        guard let basis = candidates.first(where: { c in
            prs[c.km] != nil && c.km < race.distance.km * 1.2
        }), let known = prs[basis.km] else { return nil }

        let time = riegel(knownTime: known, knownKm: basis.km, targetKm: race.distance.km)
        let longest = runs.map(\.distanceKm).max() ?? 0
        let underTrained = longest < race.distance.km * 0.6
        return Prediction(time: time, basisLabel: basis.label, underTrained: underTrained)
    }

    // MARK: - Personal records

    /// Best time (s) for the classic benchmark distances, keyed by km.
    /// 1/5/10 km use the fastest rolling window inside any run; half/marathon
    /// require an actual effort of at least that distance.
    static func personalBests(runs: [Run]) -> [Double: TimeInterval] {
        var best: [Double: TimeInterval] = [:]
        for windowKm in [1.0, 5.0, 10.0] {
            if let t = fastestWindow(km: Int(windowKm), runs: runs) {
                best[windowKm] = t
            }
        }
        for dist in [21.0975, 42.195] {
            let efforts = runs.filter { $0.distanceKm >= dist - 0.4 }
            // Scale the actual time to the exact distance for a fair benchmark.
            if let t = efforts.map({ $0.paceSecPerKm * dist }).min() {
                best[dist] = t
            }
        }
        return best
    }

    /// The run holding the fastest `km`-window, with that window's time.
    ///
    /// Callers used to find this by sorting runs with `fastestWindow` *inside*
    /// the comparator, which recomputes the window O(n log n) times. One pass
    /// is enough.
    static func fastestWindowHolder(km: Int, runs: [Run]) -> (run: Run, seconds: TimeInterval)? {
        runs.compactMap { run in
            fastestWindow(km: km, runs: [run]).map { (run: run, seconds: $0) }
        }
        .min { $0.seconds < $1.seconds }
    }

    /// Fastest continuous `km`-kilometer window across all runs, using per-km
    /// splits (min sum of `km` consecutive splits).
    static func fastestWindow(km: Int, runs: [Run]) -> TimeInterval? {
        var best: TimeInterval?
        for run in runs where run.splits.count >= km {
            var window = run.splits.prefix(km).reduce(0, +)
            var minWindow = window
            for i in km..<run.splits.count {
                window += run.splits[i] - run.splits[i - km]
                minWindow = min(minWindow, window)
            }
            best = min(best ?? minWindow, minWindow)
        }
        return best
    }

    // MARK: - Grade-adjusted pace

    /// Flat-equivalent pace (s/km). Climbing makes you slower, so the
    /// grade-adjusted pace is *faster* than the raw pace. Approximation:
    /// ~0.40 s added per metre climbed, ~0.18 s given back per metre descended
    /// (downhill helps, but less than uphill hurts). Coarse without
    /// per-segment grade — presented as an estimate.
    static let climbCostPerMeter = 0.40
    static let descentGainPerMeter = 0.18

    static func gradeAdjustedPace(_ run: Run) -> TimeInterval {
        guard run.distanceKm > 0.05 else { return 0 }
        let climb = run.climbMeters ?? 0
        let descent = run.descentMeters ?? 0
        let flatTime = run.duration - climb * climbCostPerMeter + descent * descentGainPerMeter
        return max(flatTime, 0) / run.distanceKm
    }

    // MARK: - Trends

    /// Average pace (s/km) per ISO week for the last `weeks`, oldest first.
    /// nil weeks (no runs) are dropped from the polyline but reserve their slot.
    static func weeklyAvgPace(runs: [Run], weeks: Int, roadOnly: Bool = true,
                              now: Date = .now) -> [TimeInterval?] {
        let cal = Calendar.runWeek
        let source = roadOnly ? runs.filter { !$0.isTrail } : runs
        return (0..<weeks).reversed().map { offset -> TimeInterval? in
            guard let weekDate = cal.date(byAdding: .weekOfYear, value: -offset, to: now) else { return nil }
            let inWeek = source.filter { cal.isDate($0.date, equalTo: weekDate, toGranularity: .weekOfYear) }
            guard !inWeek.isEmpty else { return nil }
            let km = inWeek.reduce(0) { $0 + $1.distanceKm }
            let time = inWeek.reduce(0) { $0 + $1.duration }
            return km > 0 ? time / km : nil
        }
    }

    /// Average climb rate (m/h) per week for the last `weeks`, trail only.
    static func weeklyClimbRate(runs: [Run], weeks: Int, now: Date = .now) -> [Double?] {
        let cal = Calendar.runWeek
        let trail = runs.filter { $0.isTrail }
        return (0..<weeks).reversed().map { offset -> Double? in
            guard let weekDate = cal.date(byAdding: .weekOfYear, value: -offset, to: now) else { return nil }
            let inWeek = trail.filter { cal.isDate($0.date, equalTo: weekDate, toGranularity: .weekOfYear) }
            let climb = inWeek.reduce(0.0) { $0 + ($1.climbMeters ?? 0) }
            let hours = inWeek.reduce(0.0) { $0 + $1.duration } / 3600
            guard hours > 0.01 else { return nil }
            return climb / hours
        }
    }

    /// Cardiac drift: average HR near a reference pace, and the change between
    /// the older and the more recent half of those runs. Heuristic — needs a
    /// handful of runs near the pace to be meaningful.
    static func hrAtPace(runs: [Run], referencePaceSec: TimeInterval,
                         tolerance: TimeInterval = 20) -> (avg: Int, delta: Int)? {
        let matches = runs
            .filter { !$0.isTrail && $0.avgHR > 0 && abs($0.paceSecPerKm - referencePaceSec) <= tolerance }
            .sorted { $0.date < $1.date }
        guard matches.count >= 2 else { return nil }
        let recent = matches.suffix(max(matches.count / 2, 1))
        let older = matches.prefix(max(matches.count / 2, 1))
        let recentAvg = recent.reduce(0) { $0 + $1.avgHR } / recent.count
        let olderAvg = older.reduce(0) { $0 + $1.avgHR } / older.count
        return (recentAvg, recentAvg - olderAvg)
    }
}
