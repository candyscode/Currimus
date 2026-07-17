import Foundation

enum RunType: String, Codable {
    case quick, pacer, trail
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
    /// Trail only.
    var climbMeters: Double?
    var descentMeters: Double?
    var highPointMeters: Double?

    var paceSecPerKm: TimeInterval { distanceKm > 0.05 ? duration / distanceKm : 0 }

    var dominantZone: Int {
        guard let maxValue = zoneSeconds.max(), maxValue > 0,
              let index = zoneSeconds.firstIndex(of: maxValue) else { return 0 }
        return index + 1
    }
}

struct RecordEntry: Identifiable {
    var id: String { label }
    var label: String
    var value: String
    var date: Date
    var isNew = false
    var delta: String?
}

struct HRZones {
    var maxHR: Int = 190

    /// Upper bound of each zone 1…4 (zone 5 is open-ended).
    var bounds: [Int] {
        // 60 / 70 / 80 / 90 % of max, matching the design's 115 / 133 / 152 / 171 at max 190.
        [0.605, 0.70, 0.80, 0.90].map { Int((Double(maxHR) * $0).rounded()) }
    }

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

    /// Signed pace delta, e.g. "−0:06" / "+0:12"
    static func paceDelta(_ seconds: TimeInterval) -> String {
        let sign = seconds < 0 ? "−" : "+"
        let total = Int(abs(seconds).rounded())
        return "\(sign)\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
