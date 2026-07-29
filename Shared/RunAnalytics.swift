import Foundation

/// Pure functions over `[Run]` — race prediction, personal records, trends,
/// grade-adjusted pace. Kept free of UI and storage so it is fully unit-tested.
enum RunAnalytics {

    // MARK: - Riegel race prediction

    /// Riegel's endurance model: T₂ = T₁ · (D₂/D₁)^exponent. Widely used, and
    /// honest for nearby distances. Callers present the result as an estimate.
    ///
    /// Riegel's exponent is 1.06, fitted on races within reach of each other.
    /// Stretched from 10 K to a marathon it is famously optimistic — the last
    /// ten kilometres are not a scaling problem, they are a fuelling and
    /// durability problem. 1.08 over that gap is the widely used correction,
    /// and it is the difference between a number a runner can plan around and
    /// one that flatters them.
    static func exponent(fromKm: Double, toKm: Double) -> Double {
        toKm > 30 && fromKm <= 12 ? 1.08 : 1.06
    }

    static func riegel(knownTime: TimeInterval, knownKm: Double, targetKm: Double,
                       exponent: Double = 1.06) -> TimeInterval {
        guard knownKm > 0, knownTime > 0 else { return 0 }
        return knownTime * pow(targetKm / knownKm, exponent)
    }

    /// The PR the prediction is based on, and the predicted finish for a race.
    struct Prediction {
        var time: TimeInterval
        var basisLabel: String       // e.g. "10K PR"
        /// When the effort it rests on was run. A prediction built on a race
        /// from last autumn is a statement about last autumn.
        var basisDate: Date
        /// True when the longest run is far short of the race — the estimate
        /// is then especially optimistic and we say so.
        var underTrained: Bool
        /// True when nothing recent qualified and the basis is an old effort.
        var isStale: Bool
    }

    /// How long an effort still counts as describing current form.
    static let predictionWindowDays = 120

    /// Predict a race finish from the best evidence the log holds: the closest
    /// benchmark below the race, run recently if anything recent qualifies.
    static func predict(race: Race, runs: [Run], now: Date = .now) -> Prediction? {
        // The closest benchmark *below* the race, not the shortest one
        // available: a half says far more about a marathon than a 5 K does,
        // and it used to be asked last. Riegel's error grows with the gap it
        // has to bridge, so the gap is made as small as the log allows.
        let candidates: [(km: Double, label: String)] = [
            (21.0975, "Half"), (10, "10K"), (5, "5K"),
        ].filter { $0.km < race.distance.km * 0.95 }

        // Recent form first. A personal best from a year ago is a fact about
        // last year; if anything in the last few months reaches the distance,
        // that is the better witness even when it is slower.
        let cutoff = Calendar.current.date(byAdding: .day, value: -predictionWindowDays, to: now) ?? now
        let recent = runs.filter { $0.date >= cutoff }

        guard let basis = best(from: recent, candidates: candidates)
                ?? best(from: runs, candidates: candidates) else { return nil }
        let isStale = basis.holder.run.date < cutoff

        let time = riegel(knownTime: basis.holder.seconds, knownKm: basis.km,
                          targetKm: race.distance.km,
                          exponent: exponent(fromKm: basis.km, toKm: race.distance.km))
        let longest = runs.map(\.distanceKm).max() ?? 0
        let underTrained = longest < race.distance.km * 0.6
        return Prediction(
            time: time,
            basisLabel: isStale ? "\(basis.label) PR" : basis.label,
            basisDate: basis.holder.run.date,
            underTrained: underTrained,
            isStale: isStale
        )
    }

    private static func best(from runs: [Run],
                             candidates: [(km: Double, label: String)])
        -> (km: Double, label: String, holder: (run: Run, seconds: TimeInterval))? {
        for candidate in candidates {
            if let holder = bestEffortHolder(km: candidate.km, runs: runs) {
                return (candidate.km, candidate.label, holder)
            }
        }
        return nil
    }

    // MARK: - Personal records

    /// The benchmark distances the Records screen and the prediction work in.
    static let benchmarkDistances: [Double] = [1, 5, 10, 21.0975, 42.195]

    /// How far short of a benchmark a run may fall and still count as one.
    /// Proportional, so a 4.6 km run is not a 5 K while a 20.7 km one is still
    /// a half.
    private static func tolerance(_ km: Double) -> Double { min(km * 0.02, 0.4) }

    /// How far past a benchmark a run may reach and still be scaled onto it.
    /// 2.5 is the value that keeps a marathon counting as evidence for a half
    /// — a runner does cover the distance on the way — while stopping the same
    /// marathon from filing its average pace as a 1 K or 5 K record, which
    /// would be true arithmetic and a worthless number.
    private static let scaledReach = 2.5

    /// Best time (s) for the classic benchmark distances, keyed by km.
    static func personalBests(runs: [Run]) -> [Double: TimeInterval] {
        var best: [Double: TimeInterval] = [:]
        for km in benchmarkDistances {
            if let holder = bestEffortHolder(km: km, runs: runs) {
                best[km] = holder.seconds
            }
        }
        return best
    }

    /// The run holding the best time over `km`, and that time.
    ///
    /// A run can hold one two ways. The fastest rolling window inside it is
    /// the better evidence, but it needs per-kilometre splits — and only runs
    /// Currimus recorded itself have those. A run read out of Apple Health
    /// arrives as one distance and one duration, so all it can offer is the
    /// whole run scaled to the benchmark.
    ///
    /// Both are considered and the faster wins, so an estimate can never
    /// displace a real PR — it only fills a row that would otherwise read
    /// "—". Without this, someone arriving with years of Strava history saw an
    /// empty Records screen and no race prediction, because none of it carries
    /// splits.
    ///
    /// The scaled reading is capped at `scaledReach`× the benchmark: average
    /// pace over a marathon is fair evidence for a half, and says nothing
    /// worth filing about a kilometre.
    static func bestEffortHolder(km: Double, runs: [Run]) -> (run: Run, seconds: TimeInterval)? {
        runs.compactMap { run -> (run: Run, seconds: TimeInterval)? in
            var best: TimeInterval?
            if km <= 10, let window = fastestWindow(km: Int(km), runs: [run]) {
                best = window
            }
            if run.distanceKm >= km - tolerance(km), run.distanceKm <= km * scaledReach {
                let scaled = run.paceSecPerKm * km
                best = min(best ?? scaled, scaled)
            }
            return best.map { (run: run, seconds: $0) }
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

    /// Raw and flat-equivalent pace across a set of runs.
    ///
    /// Weighted by distance, because averaging pace *values* treats a 4 km jog
    /// and a 30 km mountain day as equal evidence. Total time over total
    /// distance is what "average pace across these runs" actually means.
    ///
    /// Only runs that recorded climb count. Without elevation the adjustment
    /// is the identity, so every flat or GPS-less run used to drag the
    /// difference between the two numbers toward zero — and that difference is
    /// the entire point of showing them.
    static func gradeAdjustedSummary(runs: [Run]) -> (raw: TimeInterval, adjusted: TimeInterval)? {
        let climbed = runs.filter { ($0.climbMeters ?? 0) > 0 && $0.distanceKm > 0.05 }
        let km = climbed.reduce(0) { $0 + $1.distanceKm }
        guard km > 0 else { return nil }
        let time = climbed.reduce(0) { $0 + $1.duration }
        let flatTime = climbed.reduce(0.0) { $0 + gradeAdjustedPace($1) * $1.distanceKm }
        return (raw: time / km, adjusted: flatTime / km)
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

    /// What one run contributes to a zone's pace: the time it spent there and
    /// the ground it covered there.
    struct ZoneEffort: Equatable {
        var seconds: TimeInterval
        var km: Double
        /// True when this came from the run's own per-zone record rather than
        /// from treating the whole run as belonging to the zone.
        var isMeasured: Bool

        var pace: TimeInterval { km > 0.05 ? seconds / km : 0 }
    }

    /// A run's contribution to one zone, or nil if it made none.
    ///
    /// Two sources, in order of trust:
    ///
    /// 1. **Measured.** Runs recorded since Currimus started keeping per-zone
    ///    distance carry the seconds *and* the kilometres they spent in each
    ///    zone, so the answer is exact: the zone-2 portion of a run counts,
    ///    the rest of it does not.
    /// 2. **Approximated.** Older runs, and any run whose per-zone distance is
    ///    missing, only know how long they spent in each zone. There the unit
    ///    has to be the whole run: one that spent the majority of its time in
    ///    the zone counts entirely, at its overall pace. That flatters the
    ///    number slightly — the harder minutes of a mostly-easy run are in it
    ///    — which is why the measured path exists.
    ///
    /// A run another app recorded has real zone seconds once its detail screen
    /// has been opened (Health is asked for the heart-rate trace then); until
    /// that happens it is placed by its average heart rate, which is the best
    /// available and is wrong for interval sessions. Without any heart rate at
    /// all it contributes nothing rather than being guessed at.
    static func effort(of run: Run, inZone zone: Int, zones: HRZones) -> ZoneEffort? {
        guard zone >= 1, zone <= 5, run.hasUsableDistance else { return nil }

        if let perZone = run.zoneDistanceKm, perZone.count == 5 {
            let km = perZone[zone - 1]
            let seconds = run.zoneSeconds[zone - 1]
            guard km > 0.2, seconds > 30 else { return nil }
            return ZoneEffort(seconds: seconds, km: km, isMeasured: true)
        }

        let total = run.zoneSeconds.reduce(0, +)
        let belongs: Bool
        if total > 0 {
            belongs = run.zoneSeconds[zone - 1] / total >= 0.5
        } else if run.avgHR > 0 {
            belongs = zones.zone(for: run.avgHR) == zone
        } else {
            belongs = false
        }
        guard belongs else { return nil }
        return ZoneEffort(seconds: run.duration, km: run.distanceKm, isMeasured: false)
    }

    /// One month of running in a zone: the pace, and how much it rests on.
    struct ZoneMonth: Equatable {
        var month: Date
        /// nil when nothing was run in that zone that month — a gap in the
        /// line rather than a zero.
        var pace: TimeInterval?
        var km: Double
        var runs: Int
        /// True while any part of the month is still an approximation.
        var isApproximate: Bool
    }

    /// Pace in one heart-rate zone, month by month, oldest first.
    ///
    /// Months rather than weeks: an easy-run pace at a fixed heart rate moves
    /// over a training block, not over seven days, and a month gathers enough
    /// runs that one bad Tuesday does not become a data point.
    ///
    /// Aggregated as total time over total distance, so a month with four easy
    /// runs is not outweighed by a month with one — the same way the overall
    /// pace above it is computed.
    static func monthlyZonePace(runs: [Run], zone: Int, zones: HRZones,
                                months: Int, roadOnly: Bool = true,
                                now: Date = .now) -> [ZoneMonth] {
        let calendar = Calendar.current
        let source = roadOnly ? runs.filter { !$0.isTrail } : runs
        return (0..<months).reversed().compactMap { offset -> ZoneMonth? in
            guard let date = calendar.date(byAdding: .month, value: -offset, to: now),
                  let start = calendar.dateInterval(of: .month, for: date)?.start else { return nil }
            let efforts = source
                .filter { calendar.isDate($0.date, equalTo: date, toGranularity: .month) }
                .compactMap { effort(of: $0, inZone: zone, zones: zones) }
            let km = efforts.reduce(0) { $0 + $1.km }
            let seconds = efforts.reduce(0) { $0 + $1.seconds }
            return ZoneMonth(
                month: start,
                pace: km > 0.2 ? seconds / km : nil,
                km: km,
                runs: efforts.count,
                isApproximate: efforts.contains { !$0.isMeasured }
            )
        }
    }

    /// The change across a series, smoothed at both ends.
    ///
    /// Comparing the first present point to the last made the headline swing
    /// on two single months — and on a sparse line those two can be a lone run
    /// each. Averaging `window` points at each end says what actually moved.
    /// nil when there is not enough of a line to say anything.
    static func trendChange(_ values: [TimeInterval?], window: Int = 3) -> TimeInterval? {
        let present = values.compactMap { $0 }
        guard present.count >= 4 else { return nil }
        let size = min(window, present.count / 2)
        let first = present.prefix(size).reduce(0, +) / Double(size)
        let last = present.suffix(size).reduce(0, +) / Double(size)
        return last - first
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

    /// The pace to measure cardiac drift at — the runner's own steady pace,
    /// rather than a number chosen in advance.
    ///
    /// The median of their easy and long runs: the efforts they repeat most,
    /// which is the only condition under which "same pace, lower heart rate"
    /// means anything. The reference used to be a fixed 5:30, so anyone who
    /// does not happen to run 5:30 read "—" under the heading "Same effort,
    /// less work" forever, with no way to tell whether that was their data or
    /// a broken screen.
    ///
    /// Rounded to five seconds so the label names a pace a runner would say
    /// out loud, and so the band the runs are matched against is the same one
    /// the label advertises.
    static func referencePace(runs: [Run]) -> TimeInterval? {
        let steady = runs
            .filter { !$0.isTrail && $0.avgHR > 0 && $0.paceSecPerKm > 0 }
            .filter { $0.classification == .easy || $0.classification == .long }
            .map(\.paceSecPerKm)
            .sorted()
        // Four is the point where a median stops being one arbitrary run.
        guard steady.count >= 4 else { return nil }
        return (steady[steady.count / 2] / 5).rounded() * 5
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
