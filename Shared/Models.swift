import Foundation

enum RunType: String, Codable {
    case quick, pacer, trail
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
        case .easy: return "Easy"
        case .tempo: return "Tempo"
        case .intervals: return "Intervals"
        case .long: return "Long"
        case .trail: return "Trail"
        case .race: return "Race"
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

    var paceSecPerKm: TimeInterval { distanceKm > 0.05 ? duration / distanceKm : 0 }

    var isTrail: Bool { type == .trail }

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
    var id: String { label }
    var label: String
    var value: String
    var date: Date
    var isNew = false
    var delta: String?
}

struct HRZones: Codable, Equatable {
    var maxHR: Int = 190
    /// Manual overrides for the four upper-bounds (Z1…Z4); nil = auto from maxHR.
    var overrides: [Int]?

    /// Upper bound of each zone 1…4 (zone 5 is open-ended).
    var bounds: [Int] {
        if let overrides, overrides.count == 4 { return overrides }
        // 60 / 70 / 80 / 90 % of max, matching the design's 115 / 133 / 152 / 171 at max 190.
        return [0.605, 0.70, 0.80, 0.90].map { Int((Double(maxHR) * $0).rounded()) }
    }

    static let zoneNames = ["Recovery", "Easy", "Steady", "Threshold", "Max"]

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
