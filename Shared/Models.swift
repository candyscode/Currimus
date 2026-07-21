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
}

/// A single GPS fix, stored per run for the map, GPX export and grade math.
struct Coordinate: Codable, Equatable, Hashable {
    var lat: Double
    var lon: Double
    var elevation: Double
    var t: TimeInterval   // seconds since run start
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

    var paceSecPerKm: TimeInterval { distanceKm > 0.05 ? duration / distanceKm : 0 }

    /// Recorded elsewhere: counts towards every total, but Currimus does not
    /// own it — it cannot be deleted here and carries no splits or zone data.
    var isImported: Bool { imported == true }

    var isTrail: Bool { type == .trail }

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
        if type == .trail { return .trail }
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
        if let overrides, overrides.count == 4 { return overrides }
        if let restingHR, restingHR > 30, restingHR < maxHR {
            // Karvonen: resting + fraction × (max − resting).
            let reserve = Double(maxHR - restingHR)
            return Self.reserveFractions.map { Int((Double(restingHR) + reserve * $0).rounded()) }
        }
        // 60 / 70 / 80 / 90 % of max, matching the design's 115 / 133 / 152 / 171 at max 190.
        return [0.605, 0.70, 0.80, 0.90].map { Int((Double(maxHR) * $0).rounded()) }
    }

    var usesReserve: Bool { overrides == nil && restingHR != nil }

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
        case 1: return "< \(b[0])"
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
        case 1: return (Int((Double(maxHR) * 0.5).rounded()), b[0])
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
            guard let age else { return "Estimated from your age." }
            return "Estimated from your age (\(age)) with the Tanaka formula, 208 − 0.7 × age. "
                 + "No hard effort in Health yet to measure it from."
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

    static func km(_ km: Double, decimals: Int = 2) -> String {
        String(format: "%.\(decimals)f", km)
    }

    /// Elevation with the design's grouping and a non-breaking unit:
    /// 1622 → "1.622 m". `unit: false` drops the suffix for stat rows, where
    /// the label carries the unit.
    static func elevation(_ meters: Double, unit: Bool = true) -> String {
        let value = Int(meters.rounded())
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = "."
        formatter.groupingSize = 3
        let digits = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return unit ? digits + "\u{00A0}m" : digits
    }

    /// Signed pace delta, e.g. "−0:06" / "+0:12"
    static func paceDelta(_ seconds: TimeInterval) -> String {
        let sign = seconds < 0 ? "−" : "+"
        let total = Int(abs(seconds).rounded())
        return "\(sign)\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
