import Foundation

enum RunType: String, Codable {
    case quick, pacer, trail
}

/// How hard the watch drives GPS while recording. The receiver is by far the
/// biggest battery draw of a run, so this is the one setting that meaningfully
/// trades precision for hours.
enum GPSAccuracy: String, Codable, CaseIterable, Identifiable {
    case high, balanced, saving
    var id: String { rawValue }

    var label: String {
        switch self {
        case .high: return "High"
        case .balanced: return "Balanced"
        case .saving: return "Battery saver"
        }
    }

    var detail: String {
        switch self {
        case .high:
            return "Best possible fix, updated continuously. Most accurate distance, pace and elevation — and the shortest battery life. Use it on trails."
        case .balanced:
            return "Fixes to about 10 m, at most one every 5 m run. Distance and pace stay close; sharp switchbacks lose a little detail."
        case .saving:
            return "Fixes to about 100 m, at most one every 20 m run. Noticeably longer battery life, but expect distance to drift on winding routes."
        }
    }

    /// Metres of horizontal accuracy to ask CoreLocation for.
    var desiredAccuracy: Double {
        switch self {
        case .high: return -1        // kCLLocationAccuracyBest
        case .balanced: return 10
        case .saving: return 100
        }
    }

    /// Minimum metres between delivered fixes; 0 = every fix.
    var distanceFilter: Double {
        switch self {
        case .high: return 0
        case .balanced: return 5
        case .saving: return 20
        }
    }

    /// How vague a fix may be and still be drawn.
    ///
    /// It has to follow the accuracy that was *asked* for, and it did not: the
    /// route gate was a flat 50 m for every mode, while battery saver asks
    /// CoreLocation for 100 m fixes. Every one of them was then thrown away, so
    /// the setting that promises "distance may drift on winding routes"
    /// silently promised no route at all — and balanced, at 10 m requested,
    /// lost the stretches where the sky closes in. That is one candidate for
    /// the half-drawn track in CUR-40.
    ///
    /// Generous rather than tight: a coarse point on the map is a coarse point,
    /// and a missing one is a hole.
    var usableHorizontalAccuracy: Double {
        switch self {
        case .high: return 50
        case .balanced: return 100
        case .saving: return 250
        }
    }
}

/// A single GPS fix, stored per run for the map, GPX export and grade math.
struct Coordinate: Codable, Equatable, Hashable {
    var lat: Double
    var lon: Double
    var elevation: Double
    /// Wall-clock seconds since the run started — pauses included, so the GPX
    /// timestamps derived from it stay true to when the run actually happened.
    var t: TimeInterval

    /// The same point, written to the precision it was actually measured at.
    ///
    /// A `Double` encodes as however many digits it takes to round-trip, and a
    /// GPS fix carries seventeen of them for an accuracy of about five metres.
    /// Five decimal places of latitude is a metre — under the noise — and it
    /// nearly halves what a track costs to send. See `RunSync.payload(for:)`.
    var rounded: Coordinate {
        Coordinate(lat: (lat * 100_000).rounded() / 100_000,
                   lon: (lon * 100_000).rounded() / 100_000,
                   elevation: (elevation * 10).rounded() / 10,
                   t: t.rounded())
    }
}

/// How the Log/Home present a run. Road runs are auto-classified from their
/// shape (distance, dominant zone, pace variance); trail comes from the watch.
enum RunClass: String, Codable, CaseIterable {
    case easy, tempo, intervals, long, trail, race

    var label: String {
        switch self {
        case .easy: return String(localized: "Easy")
        case .tempo: return String(localized: "Tempo")
        case .intervals: return String(localized: "Intervals")
        case .long: return String(localized: "Long")
        case .trail: return String(localized: "Trail")
        case .race: return String(localized: "Race")
        }
    }
}

struct Run: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var date: Date
    var type: RunType = .quick
    var name: String
    var distanceKm: Double
    var duration: TimeInterval
    var avgHR: Int
    /// Seconds per km for each completed kilometer.
    var splits: [TimeInterval] = []
    /// Seconds spent in each of the five HR zones.
    var zoneSeconds: [TimeInterval] = [0, 0, 0, 0, 0]
    var climbMeters: Double?
    var descentMeters: Double?
    var highPointMeters: Double?
    /// Elevation samples (m) at ~10 s spacing — grade-adjusted pace + GPX.
    var altitudeSamples: [Double]?
    /// GPS track — map + GPX export.
    var route: [Coordinate]?
    /// Set when another app recorded this run and Currimus read it from Apple
    /// Health. Optional on purpose: synthesized `Decodable` ignores property
    /// defaults, so a non-optional field here would fail to decode every run
    /// persisted before it existed — i.e. wipe the log. New fields stay
    /// optional; read it through `isImported`.
    var imported: Bool?
    /// Distance covered in each of the five zones. Optional like every field
    /// added later: runs recorded before this existed have no such record, and
    /// their zone-2 pace can only ever be approximated from the run as a whole.
    var zoneDistanceKm: [Double]?
    /// Set when the workout was recorded indoors — a treadmill, or a track
    /// session with GPS off. Optional like every field added later.
    var isIndoor: Bool?
    /// Flat-equivalent pace (s/km) worked out from this run's own gradients,
    /// after Minetti. Optional like every field added later; without it the
    /// screens fall back to a rule of thumb and say so.
    var gradeAdjustedSecPerKm: Double?
    /// Average steps per minute over the run. Optional like every field added
    /// later — and genuinely absent for runs recorded before Currimus counted
    /// steps, and for those another app recorded without them.
    var cadenceSpm: Int?
    /// Set when this run was read back out of Apple Health because it never
    /// made the crossing from the watch (CUR-40). A stand-in: it has the
    /// summary, the route and the trace, but no per-kilometre splits and no
    /// live zone seconds. If the watch's own copy turns up later it replaces
    /// this one. Optional for the same reason as every field added later.
    var recovered: Bool?
    /// Set when the runner disagrees with the auto-classification, which is a
    /// heuristic over splits and zones and is wrong often enough to be worth
    /// correcting — it is the label every log row leads with. Optional for the
    /// same reason as `imported`: a non-optional field would fail to decode
    /// every run already in the log.
    var classificationOverride: RunClass?

    var paceSecPerKm: TimeInterval { distanceKm > 0.05 ? duration / distanceKm : 0 }

    /// Recorded elsewhere: counts towards every total, but Currimus does not
    /// own it — it cannot be deleted here and carries no splits or zone data.
    var isImported: Bool { imported == true }

    var isTrail: Bool { type == .trail }

    /// No GPS because there was nothing to record, rather than because
    /// something failed.
    var isTreadmill: Bool { isIndoor == true }

    /// Whether this is a run at all, or a recording that measured nothing.
    ///
    /// Distance comes from the workout builder; if it never delivered, every
    /// derived number is zero or meaningless — pace, splits, zones, the
    /// classification. Such an entry is a failed recording, and filing it in
    /// the log as a 0.00 km "Easy run" claims something that did not happen.
    /// The threshold is deliberately tiny: it rejects nothing, not short runs.
    var hasUsableDistance: Bool { distanceKm >= 0.01 }

    var dominantZone: Int {
        guard let maxValue = zoneSeconds.max(), maxValue > 0,
              let index = zoneSeconds.firstIndex(of: maxValue) else { return 0 }
        return index + 1
    }

    /// Spread of the per-km splits (s) — high = intervals, low = steady.
    var splitSpread: TimeInterval {
        guard splits.count > 1 else { return 0 }
        let mean = splits.reduce(0, +) / Double(splits.count)
        let variance = splits.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(splits.count)
        return variance.squareRoot()
    }

    /// Auto-derived training type. Heuristic — good for the common cases,
    /// approximate at the edges (a hard tempo vs. a threshold interval set).
    var classification: RunClass {
        // Trail is a recording mode, not a guess, so it outranks both.
        if type == .trail { return .trail }
        if let classificationOverride { return classificationOverride }
        if distanceKm >= 18 { return .long }
        // Intervals: repeated hard efforts → wide split spread with Z4/Z5 work.
        if splits.count >= 4, splitSpread >= 18, zoneSeconds[3] + zoneSeconds[4] >= duration * 0.20 {
            return .intervals
        }
        // Tempo: sustained hard, tight spread, Z3/Z4 dominant.
        if dominantZone >= 3, splitSpread < 20, distanceKm >= 5 {
            return .tempo
        }
        return .easy
    }
}

enum RaceDistance: String, Codable, CaseIterable, Identifiable {
    case fiveK, tenK, half, marathon
    var id: String { rawValue }

    var km: Double {
        switch self {
        case .fiveK: return 5
        case .tenK: return 10
        case .half: return 21.0975
        case .marathon: return 42.195
        }
    }

    /// Short chip label (Race Setup segmented control).
    var short: String {
        switch self {
        case .fiveK: return "5K"
        case .tenK: return "10K"
        case .half: return "Half"
        case .marathon: return "Marathon"
        }
    }

    /// Full name used in headlines.
    var name: String {
        switch self {
        case .fiveK: return "5K"
        case .tenK: return "10K"
        case .half: return "Half Marathon"
        case .marathon: return "Marathon"
        }
    }
}

struct Race: Codable, Equatable {
    var id = UUID()
    var name: String
    var distance: RaceDistance
    var date: Date
    /// Goal finish time (s).
    var goalTime: TimeInterval

    /// Whole days from the start of today to race day (0 = today).
    func daysUntil(from now: Date = .now) -> Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        let race = cal.startOfDay(for: date)
        return cal.dateComponents([.day], from: start, to: race).day ?? 0
    }

    var isToday: Bool { daysUntil() == 0 }
    var isPast: Bool { daysUntil() < 0 }
    /// How long ago it was, for a race that has been run.
    var daysSince: Int { max(-daysUntil(), 0) }

    /// Pace needed to hit the goal (s/km).
    var requiredPace: TimeInterval { goalTime / distance.km }
}

struct RecordEntry: Identifiable {
    /// Identity is the kind, not the label. The label is display text and
    /// therefore translated; keying rows off it meant every lookup broke in
    /// any language but English.
    enum Kind: String, CaseIterable {
        case oneK, fiveK, tenK, half, marathon, longest, mostClimb

        var label: String {
            switch self {
            case .oneK: return String(localized: "1 km")
            case .fiveK: return String(localized: "5 km")
            case .tenK: return String(localized: "10 km")
            case .half: return String(localized: "Half marathon")
            case .marathon: return String(localized: "Marathon")
            case .longest: return String(localized: "Longest run")
            case .mostClimb: return String(localized: "Most climb")
            }
        }

        /// What is still missing, for a row that has no time yet. An em dash
        /// says "broken" as readily as "empty"; this says which.
        var emptyHint: String {
            switch self {
            case .oneK: return String(localized: "no 1 km effort yet")
            case .fiveK: return String(localized: "no 5 km effort yet")
            case .tenK: return String(localized: "no 10 km effort yet")
            case .half: return String(localized: "no half marathon yet")
            case .marathon: return String(localized: "no marathon yet")
            case .longest: return String(localized: "no runs yet")
            case .mostClimb: return String(localized: "no trail runs yet")
            }
        }

        /// The benchmark distance this row is a personal best over.
        var km: Double? {
            switch self {
            case .oneK: return 1
            case .fiveK: return 5
            case .tenK: return 10
            case .half: return 21.0975
            case .marathon: return 42.195
            case .longest, .mostClimb: return nil
            }
        }
    }

    var kind: Kind
    var id: String { kind.rawValue }
    var label: String { kind.label }
    var value: String
    /// No time set over this distance yet. A flag rather than checking the
    /// value for a placeholder string, which stops being recognisable the
    /// moment it is translated.
    var isUnset = false
    var date: Date
    /// Secondary line: how much a PR beat the previous best, or why there is
    /// no time yet. `nil` falls back to the date.
    var delta: String?
    /// The delta is a countdown to the target race, so it burns Signal. A flag
    /// rather than sniffing the delta text for "race day", which stopped being
    /// true the moment that text could be translated.
    var isRaceCountdown = false
}

struct HRZones: Codable, Equatable {
    var maxHR: Int = 190
    /// Manual overrides for the four upper-bounds (Z1…Z4); nil = auto from maxHR.
    var overrides: [Int]?
    /// Resting heart rate from Apple Health. Present → zones use heart-rate
    /// reserve (Karvonen), which is markedly more personal than % of max.
    /// Optional, like every field added later: synthesized `Decodable` ignores
    /// defaults, so a non-optional here would fail to decode saved settings.
    var restingHR: Int?
    /// Plain-language account of where these numbers came from, shown in
    /// Settings. nil → nothing has been derived from Health yet.
    var derivation: HRDerivation?

    /// The five HRR percentages the reserve model splits on — the classic
    /// 50/60/70/80/90 ladder, so Z1 ends at 60 % of reserve and so on.
    private static let reserveFractions = [0.60, 0.70, 0.80, 0.90]

    /// Upper bound of each zone 1…4 (zone 5 is open-ended).
    var bounds: [Int] {
        // Overrides only if they are actually a ladder. A boundary stepped past
        // its neighbour — which the Settings stepper used to allow — produced
        // "151 – 133" on screen and a `range` whose upper bound sat below its
        // lower one, and `zone(for:)` then answered by whichever bound it
        // reached first. Values that cannot describe five zones are ignored
        // rather than drawn.
        if let overrides, overrides.count == 4, Self.isLadder(overrides) { return overrides }
        if let restingHR, restingHR > 30, restingHR < maxHR {
            // Karvonen: resting + fraction × (max − resting).
            let reserve = Double(maxHR - restingHR)
            return Self.reserveFractions.map { Int((Double(restingHR) + reserve * $0).rounded()) }
        }
        // 60 / 70 / 80 / 90 % of max, which is what Settings says out loud.
        //
        // The first of these was 0.605 for a long time, to land on the design
        // mock's 115 at a max of 190 — but 60 % of 190 is 114, so the screen
        // claimed one model and drew another. A mock that is a beat off its own
        // stated arithmetic loses to the arithmetic.
        return Self.maxFractions.map { Int((Double(maxHR) * $0).rounded()) }
    }

    private static let maxFractions = [0.60, 0.70, 0.80, 0.90]

    /// Strictly increasing, so the four values really are four upper bounds.
    static func isLadder(_ bounds: [Int]) -> Bool {
        zip(bounds, bounds.dropFirst()).allSatisfy { $0 < $1 }
    }

    var usesReserve: Bool { overrides == nil && restingHR != nil }

    /// Whether these zones are still Currimus' to maintain. A boundary or a
    /// max the runner set by hand is a decision, and a decision outranks a
    /// measurement — the explicit "Recalculate from Apple Health" button is
    /// how it gets handed back.
    var isAutomatic: Bool { overrides == nil && derivation?.maxSource != .manual }

    /// One line saying what actually moved, or nil when nothing did.
    ///
    /// Zones are re-derived from Health on every launch, so they drift with
    /// the runner's fitness — quietly, which is wrong: someone whose zone 2
    /// suddenly ends 5 bpm higher has earned that number and should be told.
    static func changeSummary(from old: HRZones, to new: HRZones) -> String? {
        let oldBounds = old.bounds, newBounds = new.bounds
        guard oldBounds != newBounds || old.maxHR != new.maxHR else { return nil }
        // The boundary that moved furthest carries the news. Naming all four
        // would be a table, and a table is not a notice.
        let moved = zip(oldBounds, newBounds).enumerated()
            .map { (zone: $0.offset + 1, from: $0.element.0, to: $0.element.1) }
            .filter { $0.from != $0.to }
        guard let biggest = moved.max(by: { abs($0.to - $0.from) < abs($1.to - $1.from) }) else {
            return String(localized: "Heart rate zones updated from Apple Health — your max heart rate is now \(new.maxHR) bpm instead of \(old.maxHR).")
        }
        return String(localized: "Heart rate zones updated from Apple Health. Zone \(biggest.zone) now ends at \(biggest.to) bpm instead of \(biggest.from).")
    }

    static let zoneNames = [
        String(localized: "Recovery"), String(localized: "Easy"),
        String(localized: "Steady"), String(localized: "Threshold"),
        String(localized: "Max"),
    ]

    func zone(for hr: Int) -> Int {
        for (index, bound) in bounds.enumerated() where hr <= bound { return index + 1 }
        return 5
    }

    func label(forZone zone: Int) -> String {
        let b = bounds
        switch zone {
        // `zone(for:)` puts `b[0]` itself in zone 1, so "< 114" named a range
        // one beat short of the zone it was labelling — and zone 2's own label
        // started at 115, so the missing beat was visible on the same screen.
        case 1: return "≤ \(b[0])"
        case 2: return "\(b[0] + 1) – \(b[1])"
        case 3: return "\(b[1] + 1) – \(b[2])"
        case 4: return "\(b[2] + 1) – \(b[3])"
        default: return "> \(b[3])"
        }
    }

    /// (lower, upper) HR bound of a zone. Zone 1 has no hard floor, so a
    /// resting-ish floor (~50 % max) anchors the pointer.
    func range(forZone zone: Int) -> (lower: Int, upper: Int) {
        let b = bounds
        switch zone {
        // Zone 1 starts at half the heart-rate reserve when there is one —
        // Apple's model, and the same ladder the upper bounds already use.
        // It used to start at half of *max*, which is a different (lower)
        // number and made zone 1 read wider than Apple Fitness shows it.
        case 1:
            if let restingHR, restingHR > 30, restingHR < maxHR {
                return (Int((Double(restingHR) + Double(maxHR - restingHR) * 0.5).rounded()), b[0])
            }
            return (Int((Double(maxHR) * 0.5).rounded()), b[0])
        case 2: return (b[0], b[1])
        case 3: return (b[1], b[2])
        case 4: return (b[2], b[3])
        default: return (b[3], maxHR)
        }
    }

    /// Where `hr` sits inside its zone, 0 (lower edge) … 1 (upper edge).
    func position(forHR hr: Int) -> Double {
        guard hr > 0 else { return 0.5 }
        let (lo, hi) = range(forZone: zone(for: hr))
        guard hi > lo else { return 0.5 }
        return min(max(Double(hr - lo) / Double(hi - lo), 0), 1)
    }
}

/// Where the zone numbers came from, so Settings can explain itself rather
/// than presenting a personalised number as if it fell from the sky.
struct HRDerivation: Codable, Equatable {
    enum MaxSource: String, Codable {
        case measured   // highest reliably observed heart rate
        case age        // Tanaka age formula
        case manual
    }
    var maxSource: MaxSource
    /// Day the peak heart rate was recorded (`measured` only).
    var maxDate: Date?
    var age: Int?
    var restingHR: Int?
    /// Days of resting-HR data the average is built on.
    var restingSampleDays: Int?

    var maxExplanation: String {
        switch maxSource {
        case .measured:
            let day = maxDate?.formatted(.dateTime.day().month(.abbreviated)) ?? "a recent run"
            return "Highest heart rate Apple Health has seen you reach, on \(day). Measured beats a formula every time."
        case .age:
            guard let age else { return String(localized: "Estimated from your age.") }
            return String(localized: "Estimated from your age (\(age)), after \(Source.tanaka.link) — Apple Health has not seen a hard enough effort to measure it from yet.")
        case .manual:
            return "Set by you."
        }
    }

    func zoneExplanation(usesReserve: Bool) -> String {
        guard usesReserve, let restingHR else {
            return "Zones are 60 / 70 / 80 / 90 % of your max heart rate."
        }
        let days = restingSampleDays.map { " (\($0)-day average)" } ?? ""
        return "Zones use your heart-rate reserve — the span between your resting "
             + "\(restingHR) bpm\(days) and your max. Each boundary sits at 60 / 70 / 80 / 90 % "
             + "of that span, which fits you far better than a plain share of max."
    }
}

/// Everything one log row draws, worked out once instead of on every pass.
///
/// A row costs two date formats, three number formats and the classification
/// heuristic — which walks the run's splits twice to get their spread. None of
/// it changes between renders, and the log rebuilds every row whenever
/// anything on the screen moves: a filter chip, a checkbox in the marking
/// mode, a swipe. At a year of running that was visible on the phone.
struct LogRowText: Equatable {
    /// "SUN\n26.07"
    var day: String
    var distance: String
    var pace: String
    var isTrail: Bool
    var isIndoor: Bool
    /// The plain part of the second line.
    var detail: String
    /// The benchmark tag that closes the second line, drawn in signal.
    var prTag: String?

    init(run: Run, prTag: String?) {
        day = run.date.formatted(.dateTime.weekday(.abbreviated)).uppercased()
            + "\n" + run.date.formatted(.dateTime.day(.twoDigits).month(.twoDigits))
        distance = Format.km(run.distanceKm)
        pace = Format.pace(run.paceSecPerKm)
        isTrail = run.isTrail
        isIndoor = run.isTreadmill

        // The second line is the time and the zone the run mostly sat in, and
        // for a trail run what it climbed. One shape for every row.
        //
        // It used to be four shapes, each repeating something the row already
        // said or could not support: the recording app's name (which for
        // anything Apple recorded is a device name), the word "Trail" beside
        // the orange TRAIL tag on the line above, and a classification derived
        // from splits and zones that imported runs do not have — so every one
        // of them read "Easy". Andi, 2026-07-30.
        //
        // A record is the exception, and outranks all of it.
        let clock = Format.clock(run.duration)
        if let prTag, prTag != "Longest" {
            detail = "\(clock) · "
            self.prTag = prTag
        } else {
            // "Zone 2", not "Z2" — the room is there now.
            let zone = run.dominantZone > 0 ? String(localized: "Zone \(run.dominantZone)") : nil
            let climb = run.isTrail ? "+\(Format.elevation(run.climbMeters ?? 0))" : nil
            detail = [clock, zone, climb].compactMap { $0 }.joined(separator: " · ")
            self.prTag = nil
        }
    }
}

enum Format {
    /// 324 → "5:24"
    static func pace(_ secondsPerKm: TimeInterval) -> String {
        guard secondsPerKm.isFinite, secondsPerKm > 0 else { return "–:––" }
        let total = Int(secondsPerKm.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    /// 2537 → "42:17", 3898 → "1:04:58"
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? "\(h):\(String(format: "%02d", m)):\(String(format: "%02d", s))"
            : "\(m):\(String(format: "%02d", s))"
    }

    /// Every number in this app is written one way, whatever the device's
    /// region: a full stop for the decimal, a comma for the thousands.
    ///
    /// Deliberately *not* locale-aware, which is Andi's call (2026-07-30) — the
    /// interface is English throughout, and "22,2 km" beside an English label
    /// reads as a fault rather than as a translation. Following the region for
    /// numbers and not for words is the mismatch, so it follows neither.
    ///
    /// What this replaced was worse than either: three formatters that
    /// disagreed. `elevation` grouped with a hard-coded full stop — the German
    /// convention, in an English UI, where "1.622 m" reads as one and a half
    /// metres — `km` was POSIX, and the trail detail had a third that grouped
    /// with a space. Fixed here also means the UI-snapshot references do not
    /// depend on the region of the machine that recorded them.
    ///
    /// `en_US` and not `en_US_POSIX`: the POSIX locale exists for
    /// machine-readable output and switches grouping off altogether, so a
    /// four-digit climb came out as "1622".
    private static let fixed = Locale(identifier: "en_US")

    static func km(_ km: Double, decimals: Int = 2) -> String {
        km.formatted(.number.precision(.fractionLength(decimals))
            .grouping(.never).locale(fixed))
    }

    /// Distance for a narrow column — a tenth under 100 km, whole numbers past
    /// it. Four glyphs plus a point plus a decimal do not fit a third of a
    /// rectangular complication, and at 400 km the tenth is noise anyway.
    static func compactKm(_ km: Double) -> String {
        Self.km(km, decimals: km < 100 ? 1 : 0)
    }

    /// Elevation with grouping and a non-breaking unit: 1622 → "1,622 m".
    /// `unit: false` drops the suffix for stat rows, where the label carries it.
    static func elevation(_ meters: Double, unit: Bool = true) -> String {
        let digits = Int(meters.rounded()).formatted(.number.locale(fixed))
        return unit ? digits + "\u{00A0}m" : digits
    }

    /// A pacer target distance as a compact label: "Off", "10 km", or the two
    /// race distances with their decimal ("21.1 km" / "42.2 km"). One place, so
    /// the Settings summary and the wheel cannot disagree on how a marathon
    /// reads.
    static func pacerDistance(_ km: Double?) -> String {
        guard let km else { return String(localized: "Off") }
        if km == RaceDistance.half.km || km == RaceDistance.marathon.km {
            return "\(Self.km(km, decimals: 1)) km"
        }
        return "\(Int(km).formatted(.number.locale(fixed))) km"
    }

    /// "1 run", "2 runs". Every naive "\(n) runs" in the app read "1 runs"
    /// at exactly one, which is the count a new log spends its first week at.
    static func plural(_ count: Int, _ singular: String, _ plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }

    /// Signed pace delta, e.g. "−0:06" / "+0:12"
    static func paceDelta(_ seconds: TimeInterval) -> String {
        let sign = seconds < 0 ? "−" : "+"
        let total = Int(abs(seconds).rounded())
        return "\(sign)\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
