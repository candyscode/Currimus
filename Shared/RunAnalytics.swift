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

    // MARK: - What the training says

    /// A marathon time predicted from training rather than from a race, after
    /// Tanda (2011): the mean weekly distance and the mean training pace of
    /// the eight weeks before it.
    ///
    /// This is the other half of the truth. Riegel reads one hard effort and
    /// knows nothing about whether the runner has done the work; two runners
    /// with the same 10 K and 40 km a week between them do not finish a
    /// marathon together.
    struct TrainingPrediction: Equatable {
        var time: TimeInterval
        var weeklyKm: Double
        var meanPaceSecPerKm: TimeInterval
        /// How many weeks the block actually spans, up to `trainingWindowWeeks`.
        /// Carried so the sentence on screen can name the period it read rather
        /// than claiming eight weeks of a log that is four weeks old.
        var weeksCovered: Int
        /// True when the inputs sit outside the range the model was fitted on,
        /// and the number is an extrapolation rather than a reading.
        var isExtrapolated: Bool
    }

    static let trainingWindowWeeks = 8
    /// How much of that window the log has to actually reach back over. Eight
    /// runs crammed into a fortnight are not a training block, whatever the
    /// arithmetic says about them.
    static let minimumTrainingWeeks = 4
    /// The study covered 22 runners finishing between 2:47 and 3:36, training
    /// at the volumes that go with that. Outside it the curve still returns a
    /// number; it just stops being evidence.
    static let fittedWeeklyKm = 55.0...160.0
    static let fittedTrainingPace = 195.0...300.0

    static func trainingPrediction(runs: [Run], now: Date = .now) -> TrainingPrediction? {
        guard let cutoff = Calendar.current.date(byAdding: .weekOfYear,
                                                 value: -trainingWindowWeeks, to: now) else { return nil }
        // Road only. The pace term carries more than half the prediction, and
        // one mountain day at 7:30 /km would move a marathon estimate by
        // minutes — the model was fitted on road training.
        let window = runs.filter { $0.date >= cutoff && !$0.isTrail && $0.hasUsableDistance }
        let km = window.reduce(0) { $0 + $1.distanceKm }
        let seconds = window.reduce(0) { $0 + $1.duration }
        // Enough of a block to describe one.
        guard window.count >= 8, km > 0, seconds > 0,
              let earliest = window.map(\.date).min() else { return nil }

        // Over the weeks the log actually covers, not over eight regardless.
        //
        // The guard above counts *runs*, so eight runs in three weeks used to
        // be divided by eight anyway — a third of the real weekly volume, which
        // this curve turns into about a quarter of an hour of extra marathon.
        // And because the screen leads with the slower of its two models, that
        // wrong number became the headline.
        //
        // Whole weeks, and by ceiling: a block of four runs a week for eight
        // weeks has 7.7 weeks between its first run and its last, and dividing
        // by that would overstate the volume by a week's worth every time.
        // Counting the weeks the block spans is the fencepost-free reading, and
        // it keeps a taper honest — resting the last fortnight of a long block
        // still divides by eight, because the block is still eight weeks old.
        let weeksCovered = (now.timeIntervalSince(earliest) / (7 * 86_400)).rounded(.up)
        guard weeksCovered >= Double(minimumTrainingWeeks) else { return nil }
        let weekly = km / min(weeksCovered, Double(trainingWindowWeeks))
        let meanPace = seconds / km
        let pace = 17.1 + 140.0 * exp(-0.0053 * weekly) + 0.55 * meanPace
        return TrainingPrediction(
            time: pace * RaceDistance.marathon.km,
            weeklyKm: weekly,
            meanPaceSecPerKm: meanPace,
            weeksCovered: Int(min(weeksCovered, Double(trainingWindowWeeks))),
            isExtrapolated: !(fittedWeeklyKm.contains(weekly) && fittedTrainingPace.contains(meanPace))
        )
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
        /// What the last eight weeks of training say, for a marathon. The two
        /// are kept apart rather than blended: they measure different things,
        /// and where they disagree that disagreement is the information.
        var fromTraining: TrainingPrediction?
        /// The basis is the race's own distance, so `time` is a reading and not
        /// a scaling. The screen says so rather than crediting Riegel with an
        /// identity.
        var isOverRaceDistance: Bool = false

        /// What to lead with. The slower of the two — a prediction that is too
        /// optimistic costs a runner far more on the day than one that is too
        /// careful.
        var headline: TimeInterval { max(time, fromTraining?.time ?? 0) }
    }

    /// How long an effort still counts as describing current form.
    static let predictionWindowDays = 120

    /// Predict a race finish from the best evidence the log holds: the closest
    /// benchmark below the race, run recently if anything recent qualifies.
    static func predict(race: Race, runs: [Run], now: Date = .now) -> Prediction? {
        // The closest benchmark at or below the race, not the shortest one
        // available: a half says far more about a marathon than a 5 K does,
        // and it used to be asked last. Riegel's error grows with the gap it
        // has to bridge, so the gap is made as small as the log allows — and
        // the smallest gap of all is none.
        //
        // The race's own distance used to be excluded (`< km * 0.95`), which
        // meant a 5 K race could *never* be predicted: nothing shorter is on
        // the list. The screen said "run a 5 K and the prediction appears", and
        // it never did, however many the runner ran. Riegel over the identity
        // returns the effort itself, which is exactly the right answer: your
        // best 5 K is the honest forecast for a 5 K.
        let candidates: [(km: Double, label: String)] = [
            (42.195, "Marathon"), (21.0975, "Half"), (10, "10K"), (5, "5K"),
        ].filter { $0.km <= race.distance.km }

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
            isStale: isStale,
            // Tanda's model is fitted on the marathon; it says nothing about a
            // 10 K and is not asked.
            fromTraining: race.distance == .marathon
                ? trainingPrediction(runs: runs, now: now) : nil,
            isOverRaceDistance: basis.km == race.distance.km
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

    /// What a metre at this gradient costs, relative to a metre on the flat.
    ///
    /// Minetti et al. (2002) put ten runners on a treadmill from −45 % to
    /// +45 % and measured the oxygen they used; the fifth-order fit through
    /// those points is the standard answer to "how much harder was that hill",
    /// and it is what a grade-adjusted pace ought to rest on. Outside the
    /// measured range the polynomial is extrapolation, so it is clamped.
    static func gradeCostFactor(_ gradient: Double) -> Double {
        let i = min(max(gradient, -0.45), 0.45)
        let cost = 155.4 * pow(i, 5) - 30.4 * pow(i, 4) - 43.3 * pow(i, 3)
            + 46.3 * pow(i, 2) + 19.5 * i + 3.6
        // 3.6 J/kg/m is the flat cost in the same fit.
        return cost / 3.6
    }

    /// Over how much ground a gradient is worked out. A fix every few metres
    /// with a metre of altitude noise on it would otherwise report ramps that
    /// were never there.
    static let gradeSegmentKm = 0.02

    /// What a track says about the ground it covers: how far it actually ran,
    /// and what that distance would have been on the flat for the same effort.
    struct RouteGrade: Equatable {
        var measuredKm: Double
        var flatKm: Double

        /// Flat-equivalent kilometres per kilometre run. Scale-free, which is
        /// the whole reason this is a separate value — see `gradeAdjustedPace`.
        var factor: Double { measuredKm > 0 ? flatKm / measuredKm : 1 }
    }

    /// Walks a track and converts every stretch to the flat distance that would
    /// have cost the same.
    static func routeGrade(_ route: [Coordinate]) -> RouteGrade? {
        guard route.count >= 2 else { return nil }
        var measuredKm = 0.0
        var flatKm = 0.0
        var pendingKm = 0.0
        var pendingClimb = 0.0

        for (from, to) in zip(route, route.dropFirst()) {
            let km = haversineKm(from, to)
            guard km > 0, km <= maxSegmentKm else { continue }
            measuredKm += km
            pendingKm += km
            pendingClimb += to.elevation - from.elevation
            guard pendingKm >= gradeSegmentKm else { continue }
            let gradient = pendingClimb / (pendingKm * 1000)
            flatKm += pendingKm * gradeCostFactor(gradient)
            pendingKm = 0
            pendingClimb = 0
        }
        // Whatever is left of the last stretch counts on the flat.
        flatKm += pendingKm
        guard measuredKm > 0.05 else { return nil }
        return RouteGrade(measuredKm: measuredKm, flatKm: flatKm)
    }

    /// How much of a run its track has to describe before that track's
    /// gradients may stand for the whole of it.
    static let minimumRouteCoverage = 0.5

    /// Flat-equivalent pace (s/km) from a route.
    ///
    /// The gradients say how much harder the ground was than flat ground; the
    /// run's own distance says how much of it there was. Keeping the two apart
    /// is what this had wrong (CUR-40): the time was spread over the track's
    /// flat-equivalent length, so a run whose GPS died after three hundred
    /// metres spread two hours over three hundred metres and reported
    /// 465:25 /km beside a real 21:13. The terrain factor is scale-free and
    /// survives a partial track; the *length* now comes from `distanceKm`,
    /// which HealthKit measured for the whole run.
    ///
    /// Still nil without a track — total climb alone cannot say whether it came
    /// as one wall or forty rolling metres — and nil when the track covers too
    /// little of the run to speak for it. The rule of thumb takes over there,
    /// and the screens already say which of the two they are showing.
    static func gradeAdjustedPace(route: [Coordinate], duration: TimeInterval,
                                  distanceKm: Double? = nil) -> TimeInterval? {
        guard duration > 0, let grade = routeGrade(route) else { return nil }
        let km = distanceKm ?? grade.measuredKm
        guard km > 0.05, grade.measuredKm >= km * minimumRouteCoverage else { return nil }
        return duration / (km * grade.factor)
    }

    /// Over how much ground the *steepest* stretch of a run is measured.
    ///
    /// Deliberately five times `gradeSegmentKm`, and the reason is the word
    /// "steepest". A grade-adjusted pace sums hundreds of segments, so the noise
    /// in them cancels; a maximum does the opposite — it goes looking for the
    /// noisiest one it can find. GPS elevation wanders a metre or two, which
    /// over 20 m is a 10 % ramp that was never there and over 100 m is 2 %.
    static let steepestSegmentKm = 0.1

    /// The steepest `steepestSegmentKm` of a route, as a gradient (0.12 = 12 %).
    ///
    /// Uphill or down — a runner asking how steep it got means either. nil
    /// without a track: this needs to know where the height was gained, and a
    /// total cannot say.
    static func steepestGradient(route: [Coordinate]) -> Double? {
        guard route.count >= 2 else { return nil }
        var steepest: Double?
        var pendingKm = 0.0
        var pendingClimb = 0.0
        for (from, to) in zip(route, route.dropFirst()) {
            let km = haversineKm(from, to)
            guard km > 0, km <= maxSegmentKm else { continue }
            pendingKm += km
            pendingClimb += to.elevation - from.elevation
            guard pendingKm >= steepestSegmentKm else { continue }
            steepest = max(steepest ?? 0, abs(pendingClimb) / (pendingKm * 1000))
            pendingKm = 0
            pendingClimb = 0
        }
        return steepest
    }

    /// The coarse fallback for a run with no track: about 0.4 s of the run's
    /// time attributed to each metre climbed and rather less than half of that
    /// given back on the way down. Nobody's research — the app's own rule of
    /// thumb, and named as such wherever it is shown.
    static let climbCostPerMeter = 0.40
    static let descentGainPerMeter = 0.18

    /// How far a flat-equivalent pace may sit from the raw one and still be
    /// believable. Minetti's fit is clamped to ±45 %, where a metre costs
    /// between about half and four and a half times what it costs on the flat —
    /// so a run cannot be more than twice as slow, or a quarter as fast, as it
    /// was on the ground. Anything outside is a broken measurement, not a hill.
    static let gradeAdjustmentBand = 0.2...2.0

    static func gradeAdjustedPace(_ run: Run) -> TimeInterval {
        guard run.distanceKm > 0.05 else { return 0 }
        // Measured from the run's own gradients when it has them — and when the
        // stored figure is one this run could actually have produced. Runs
        // recorded before CUR-40 can carry a value taken over a truncated
        // track, which is off by orders of magnitude rather than by a hill.
        if let measured = run.gradeAdjustedSecPerKm, plausible(measured, for: run) {
            return measured
        }
        if let route = run.route,
           let fromRoute = gradeAdjustedPace(route: route, duration: run.duration,
                                             distanceKm: run.distanceKm),
           plausible(fromRoute, for: run) {
            return fromRoute
        }
        let climb = run.climbMeters ?? 0
        let descent = run.descentMeters ?? 0
        let flatTime = run.duration - climb * climbCostPerMeter + descent * descentGainPerMeter
        // Held inside the same band the measured answers are held to. The rule
        // of thumb is linear in the climb, so it has no idea when the climb it
        // was handed is nonsense: an old entry claiming a kilometre of ascent
        // over five flat ones drives it straight to zero, and "0:00 /KM" is the
        // one thing a pace field must never say.
        let raw = run.paceSecPerKm
        return min(max(max(flatTime, 0) / run.distanceKm, raw * gradeAdjustmentBand.lowerBound),
                   raw * gradeAdjustmentBand.upperBound)
    }

    /// Whether a flat-equivalent pace is one this run could have produced.
    private static func plausible(_ adjusted: TimeInterval, for run: Run) -> Bool {
        let raw = run.paceSecPerKm
        guard raw > 0, adjusted > 0 else { return false }
        return gradeAdjustmentBand.contains(adjusted / raw)
    }

    /// Whether a run's flat-equivalent pace was worked out from its gradients
    /// rather than from the rule of thumb — the screens say which.
    ///
    /// It asks the same questions `gradeAdjustedPace(_:)` does, in the same
    /// order. It used to only look for a track, so a run whose stored figure
    /// was rejected, or whose track covers too little of it to speak for it,
    /// was labelled "measured" over a number that came from the rule of thumb.
    static func hasMeasuredGradeAdjustment(_ run: Run) -> Bool {
        if let measured = run.gradeAdjustedSecPerKm, plausible(measured, for: run) { return true }
        guard let route = run.route,
              let fromRoute = gradeAdjustedPace(route: route, duration: run.duration,
                                                distanceKm: run.distanceKm) else { return false }
        return plausible(fromRoute, for: run)
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

    // MARK: - Reconstructing distance per zone

    /// A time gap longer than this between two fixes is a pause or a dropout,
    /// not a stretch of running, and the ground between them cannot be
    /// attributed to whatever the heart rate happened to be.
    static let maxSegmentGap: TimeInterval = 60
    /// Nor can a jump of half a kilometre between two fixes.
    static let maxSegmentKm = 0.5

    /// Distance covered in each zone, reconstructed from a GPS track and a
    /// heart-rate trace recorded over the same run.
    ///
    /// This is what makes "pace in zone 2" a measurement for runs Currimus did
    /// not record itself. The watch keeps this as it goes; for a workout that
    /// came from Apple Health, both halves are in the store — the route with
    /// its timestamps and every heart-rate sample — and pairing them back up
    /// is the same arithmetic after the fact.
    ///
    /// nil when there is not enough to measure, which is the point: a
    /// treadmill run has no route and a run without a strap has no trace, and
    /// neither should be guessed at.
    static func zoneDistanceKm(route: [Coordinate],
                               heartRate: [(bpm: Int, at: TimeInterval)],
                               zones: HRZones) -> [Double]? {
        zoneDistanceKm(trace: distanceTrace(fromRoute: route), heartRate: heartRate, zones: zones)
    }

    /// Cumulative distance over time — everything below works on this rather
    /// than on a GPS track, because a treadmill run has no track and Health
    /// still knows how far it went and when.
    typealias DistancePoint = (km: Double, at: TimeInterval)

    static func distanceTrace(fromRoute route: [Coordinate]) -> [DistancePoint] {
        guard route.count >= 2 else { return [] }
        var points: [DistancePoint] = [(km: 0, at: route[0].t)]
        var covered = 0.0
        for (from, to) in zip(route, route.dropFirst()) {
            let span = to.t - from.t
            let km = haversineKm(from, to)
            // A pause or a jump carries the clock forward without the ground,
            // so nothing is attributed across it.
            if span >= 0, span <= maxSegmentGap, km > 0, km <= maxSegmentKm { covered += km }
            points.append((km: covered, at: to.t))
        }
        return points
    }

    static func zoneDistanceKm(trace points: [DistancePoint],
                               heartRate: [(bpm: Int, at: TimeInterval)],
                               zones: HRZones) -> [Double]? {
        guard points.count >= 2, !heartRate.isEmpty else { return nil }
        let trace = heartRate.sorted { $0.at < $1.at }
        var distance = [Double](repeating: 0, count: 5)
        var index = 0

        for (from, to) in zip(points, points.dropFirst()) {
            let km = to.km - from.km
            let span = to.at - from.at
            guard km > 0, span >= 0, span <= maxSegmentGap else { continue }

            // The heart rate in the middle of the stretch: the trace is
            // sorted, so this walks forward with the run rather than being
            // searched again at every step.
            let middle = (from.at + to.at) / 2
            while index + 1 < trace.count, trace[index + 1].at <= middle { index += 1 }
            var sample = trace[index]
            if index + 1 < trace.count,
               abs(trace[index + 1].at - middle) < abs(sample.at - middle) {
                sample = trace[index + 1]
            }
            guard abs(sample.at - middle) <= HealthImport.maxSampleSpan else { continue }

            let zone = zones.zone(for: sample.bpm)
            guard (1...5).contains(zone) else { continue }
            distance[zone - 1] += km
        }
        return distance.reduce(0, +) > 0 ? distance : nil
    }

    /// Per-kilometre splits reconstructed from a GPS track.
    ///
    /// A run out of Apple Health arrives as one distance and one duration, so
    /// its 5 K and 10 K records could only ever be its *average* pace scaled
    /// onto the distance — which drags a fast ten kilometres down with the
    /// four slow ones that followed. The route says where the runner was and
    /// when, so the kilometre marks can be found again.
    static func splits(fromRoute route: [Coordinate]) -> [TimeInterval] {
        splits(trace: distanceTrace(fromRoute: route))
    }

    static func splits(trace points: [DistancePoint]) -> [TimeInterval] {
        guard points.count >= 2 else { return [] }
        var splits: [TimeInterval] = []
        var covered = 0.0
        var lastMarkTime = points[0].at

        for (from, to) in zip(points, points.dropFirst()) {
            let span = to.at - from.at
            let km = to.km - from.km
            guard span >= 0, span <= maxSegmentGap, km > 0 else { continue }

            var remaining = km
            var segmentStart = from.at
            // A single segment can cross a kilometre mark, and on a coarse
            // track it can cross more than one.
            while covered + remaining >= Double(splits.count + 1) {
                let toMark = Double(splits.count + 1) - covered
                let share = toMark / remaining
                let markTime = segmentStart + (to.at - segmentStart) * share
                splits.append(markTime - lastMarkTime)
                lastMarkTime = markTime
                segmentStart = markTime
                covered += toMark
                remaining -= toMark
            }
            covered += remaining
        }
        return splits
    }

    /// Great-circle distance in km. Fine at the scale of one running stride —
    /// the error against the ellipsoid is far below the GPS's own.
    private static func haversineKm(_ a: Coordinate, _ b: Coordinate) -> Double {
        let radius = 6371.0088
        let dLat = (b.lat - a.lat) * .pi / 180
        let dLon = (b.lon - a.lon) * .pi / 180
        let lat1 = a.lat * .pi / 180
        let lat2 = b.lat * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2)
        return 2 * radius * asin(min(1, h.squareRoot()))
    }

    /// What one run contributes to a zone's pace: the time it spent there and
    /// the ground it covered there.
    struct ZoneEffort: Equatable {
        var seconds: TimeInterval
        var km: Double

        var pace: TimeInterval { km > 0.05 ? seconds / km : 0 }
    }

    /// A run's contribution to one zone, or nil if it made none.
    ///
    /// Measured or nothing. A run knows the seconds *and* the kilometres it
    /// spent in each zone — recorded live by the watch, or reconstructed from
    /// Health's route and heart-rate trace — and only then does it count.
    ///
    /// It used to fall back to treating a run that spent most of its time in
    /// the zone as belonging to it whole, at its overall pace. That reads as a
    /// measurement on a chart that cannot show its own uncertainty, and it
    /// flatters the number besides: the harder kilometres of a mostly-easy run
    /// were in it. A run that cannot be measured is left out and counted in
    /// the line underneath the chart instead.
    static func effort(of run: Run, inZone zone: Int, zones: HRZones) -> ZoneEffort? {
        guard zone >= 1, zone <= 5, run.hasUsableDistance,
              let perZone = run.zoneDistanceKm, perZone.count == 5 else { return nil }
        let km = perZone[zone - 1]
        let seconds = run.zoneSeconds[zone - 1]
        // Passing through a zone on the way to another one is not running in
        // it; a fifth of a kilometre and half a minute are the floor.
        guard km > 0.2, seconds > 30 else { return nil }
        return ZoneEffort(seconds: seconds, km: km)
    }

    /// One month of running in a zone: the pace, and how much it rests on.
    struct ZoneMonth: Equatable {
        var month: Date
        /// nil when nothing was run in that zone that month — a gap in the
        /// line rather than a zero.
        var pace: TimeInterval?
        var km: Double
        var runs: Int
        /// Runs that month which were spent in the zone but could not be
        /// measured — no GPS track, or no heart-rate trace to pair it with.
        /// They are left out of the line and counted here instead.
        var unmeasured: Int
    }

    /// Whether a run was in the zone at all, measurable or not.
    static func spentTime(_ run: Run, inZone zone: Int) -> Bool {
        guard zone >= 1, zone <= 5, run.zoneSeconds.count == 5 else { return false }
        return run.zoneSeconds[zone - 1] > 30
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
            let inMonth = source.filter {
                calendar.isDate($0.date, equalTo: date, toGranularity: .month)
            }
            let efforts = inMonth.compactMap { effort(of: $0, inZone: zone, zones: zones) }
            let unmeasured = inMonth.filter {
                spentTime($0, inZone: zone) && effort(of: $0, inZone: zone, zones: zones) == nil
            }
            let km = efforts.reduce(0) { $0 + $1.km }
            let seconds = efforts.reduce(0) { $0 + $1.seconds }
            return ZoneMonth(
                month: start,
                pace: km > 0.2 ? seconds / km : nil,
                km: km,
                runs: efforts.count,
                unmeasured: unmeasured.count
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

    /// How far back "than it used to be" reaches.
    ///
    /// There was no window at all: the split into "older" and "more recent" ran
    /// over the whole log, so three years of running compared year one against
    /// year three — and once the log was long, the number stopped moving no
    /// matter what the runner did. Half a year is long enough for the adaptation
    /// this measures and short enough that the answer still describes now.
    static let driftWindowDays = 180
    /// How many runs near the pace before the comparison means anything. Two
    /// made the claim on one run against one, which is a difference between two
    /// mornings, not a trend.
    static let driftSample = 4

    /// Cardiac drift: average HR near a reference pace, and the change between
    /// the older and the more recent half of those runs. Heuristic — needs a
    /// handful of runs near the pace to be meaningful.
    static func hrAtPace(runs: [Run], referencePaceSec: TimeInterval,
                         tolerance: TimeInterval = 20,
                         now: Date = .now) -> (avg: Int, delta: Int)? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -driftWindowDays, to: now) ?? .distantPast
        let matches = runs
            .filter { !$0.isTrail && $0.avgHR > 0 && $0.date >= cutoff
                && abs($0.paceSecPerKm - referencePaceSec) <= tolerance }
            .sorted { $0.date < $1.date }
        guard matches.count >= driftSample else { return nil }
        let recent = matches.suffix(max(matches.count / 2, 1))
        let older = matches.prefix(max(matches.count / 2, 1))
        let recentAvg = recent.reduce(0) { $0 + $1.avgHR } / recent.count
        let olderAvg = older.reduce(0) { $0 + $1.avgHR } / older.count
        return (recentAvg, recentAvg - olderAvg)
    }
}
