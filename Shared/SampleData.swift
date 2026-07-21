import Foundation

/// Demo content standing in for synced watch runs — a marathon build-up.
/// Types, climb and altitude are shaped so the auto-classifier, records,
/// prediction and grade-adjusted pace all have realistic inputs.
enum SampleData {
    #if DEBUG
    static let runs: [Run] = generate()

    static let race: Race? = Race(
        name: "Freiburg Marathon",
        distance: .marathon,
        date: Calendar.current.date(byAdding: .day, value: 42, to: Calendar.current.startOfDay(for: .now))!,
        goalTime: 3 * 3600 + 59 * 60   // 3:59:00
    )
    #else
    /// A shipped app cannot reach the flag that seeds this, so the generator
    /// and its whole marathon build-up stay out of the release binary.
    static let runs: [Run] = []
    static let race: Race? = nil
    #endif

    #if DEBUG
    private enum Kind { case easy, tempo, intervals, long, trail }

    private struct Slot {
        var weekday: Int          // Calendar weekday, Sun = 1
        var kind: Kind
        var km: Double
        var pace: TimeInterval    // s/km
        var hr: Int
    }

    private static func generate() -> [Run] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        // A week: Tue easy, Thu tempo, Sat trail (or intervals), Sun long.
        let week: [Slot] = [
            Slot(weekday: 3, kind: .easy, km: 10, pace: 325, hr: 150),
            Slot(weekday: 5, kind: .tempo, km: 12, pace: 324, hr: 162),
            Slot(weekday: 7, kind: .trail, km: 18, pace: 452, hr: 152),
            Slot(weekday: 1, kind: .long, km: 20, pace: 352, hr: 148),
        ]

        var runs: [Run] = []
        for daysBack in 0...181 {
            guard let day = cal.date(byAdding: .day, value: -daysBack, to: today) else { continue }
            let weekday = cal.component(.weekday, from: day)
            guard var slot = week.first(where: { $0.weekday == weekday }) else { continue }

            let progress = 1 - Double(daysBack) / 181           // 0 old → 1 now
            let wave = sin(Double(daysBack) / 8)

            // Volume grows, pace sharpens toward race day.
            slot.km = max(slot.km * (0.7 + 0.3 * progress) + wave * 0.8, 4)
            slot.pace -= 22 * progress

            // Every third Saturday is a hard interval session instead of trail.
            if slot.kind == .trail && (daysBack / 7) % 3 == 1 {
                slot = Slot(weekday: 7, kind: .intervals, km: 9, pace: 300, hr: 168)
            }

            let hour = slot.kind == .tempo ? 6 : (slot.kind == .trail ? 8 : 7)
            let date = cal.date(bySettingHour: hour, minute: [58, 2, 15, 31][daysBack % 4], second: 0, of: day)!
            guard date <= .now else { continue }
            runs.append(make(slot, date: date, sharpen: progress))
        }

        // A recent 10K PR and a 5K PR so records/prediction have real bests.
        if let idx = runs.firstIndex(where: { $0.classification == .intervals }) {
            runs[idx] = tenKPR(date: runs[idx].date)
        }
        return runs.sorted { $0.date > $1.date }
    }

    private static func make(_ slot: Slot, date: Date, sharpen: Double) -> Run {
        let km = (slot.km * 100).rounded() / 100
        let whole = max(Int(km.rounded(.down)), 1)

        var splits: [TimeInterval] = []
        for i in 0..<whole {
            switch slot.kind {
            case .intervals:
                splits.append(slot.pace + (i % 2 == 0 ? 34 : -30) + Double.random(in: -3...3))
            case .tempo:
                splits.append(slot.pace + (i == 0 ? 26 : (i == whole - 1 ? 14 : 0)) + sin(Double(i)) * 3)
            case .long:
                splits.append(slot.pace + 8 + sin(Double(i) * 0.6) * 6)
            case .easy:
                splits.append(slot.pace + sin(Double(i)) * 5)
            case .trail:
                splits.append(slot.pace + sin(Double(i) * 0.9) * 55)
            }
        }
        let duration = (splits.reduce(0, +)).rounded()

        let zones: [Double]
        switch slot.kind {
        case .easy:      zones = [0.10, 0.62, 0.24, 0.03, 0.01]
        case .tempo:     zones = [0.04, 0.14, 0.30, 0.44, 0.08]
        case .intervals: zones = [0.06, 0.16, 0.20, 0.34, 0.24]
        case .long:      zones = [0.12, 0.58, 0.26, 0.03, 0.01]
        case .trail:     zones = [0.06, 0.30, 0.40, 0.20, 0.04]
        }

        let (climb, descent, high, alt) = elevation(for: slot.kind, km: km)
        let names: [Kind: String] = [
            .easy: "Easy run", .tempo: "Morning tempo", .intervals: "Intervals",
            .long: "Long run", .trail: "Ridge trail",
        ]

        return Run(
            date: date,
            type: slot.kind == .trail ? .trail : .quick,
            name: names[slot.kind] ?? "Run",
            distanceKm: km,
            duration: duration,
            avgHR: slot.hr - Int(3 * sharpen),
            splits: splits,
            zoneSeconds: zones.map { $0 * duration },
            climbMeters: climb, descentMeters: descent, highPointMeters: high,
            altitudeSamples: alt
        )
    }

    /// A synthetic elevation profile → climb/descent/high point + samples.
    private static func elevation(for kind: Kind, km: Double)
        -> (Double, Double, Double, [Double]) {
        let base = 260.0
        let n = max(Int(km * 6), 8)              // ~10 s samples
        let amplitude: Double = kind == .trail ? 340 : 22
        var samples: [Double] = []
        var climb = 0.0, descent = 0.0, last = base, high = base
        for i in 0..<n {
            let x = Double(i) / Double(n - 1)
            let h = base + amplitude * (kind == .trail
                ? (sin(x * .pi * 2.1) * 0.5 + 0.5) + x * 0.7   // net ascent
                : sin(x * .pi * 3) * 0.5 + 0.5)
            samples.append(h)
            let d = h - last
            if d > 0 { climb += d } else { descent += -d }
            high = max(high, h)
            last = h
        }
        return (climb.rounded(), descent.rounded(), high.rounded(), samples)
    }

    /// A standout 10K session that also holds the 5K PR window.
    private static func tenKPR(date: Date) -> Run {
        let splits: [TimeInterval] = [307, 303, 300, 298, 296, 299, 301, 297, 295, 296]
        let duration = splits.reduce(0, +)
        return Run(
            date: date, type: .quick, name: "10K time trial",
            distanceKm: 10.0, duration: duration, avgHR: 171,
            splits: splits,
            zoneSeconds: [0.02, 0.08, 0.20, 0.40, 0.30].map { $0 * duration },
            climbMeters: 18, descentMeters: 18, highPointMeters: 272,
            altitudeSamples: (0..<60).map { 260 + sin(Double($0) / 6) * 6 }
        )
    }
    #endif
}
