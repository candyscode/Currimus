import Foundation

/// Demo content standing in for synced watch runs. The log follows a
/// Mon / Wed / Fri / Sun training pattern anchored to real weekdays, with
/// pace and volume trending up toward today — so every aggregate view
/// (week bars, monthly km, trend) looks alive on any date.
enum SampleData {
    static let runs: [Run] = generate()

    private static func generate() -> [Run] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var runs: [Run] = []

        // Weekday (Mon=2 … Sun=1 in Calendar terms), name, base km, base HR.
        let pattern: [(weekday: Int, name: String, km: Double, hr: Int)] = [
            (2, "Easy run", 8.21, 149),
            (4, "Morning Run", 12.02, 151),
            (6, "Evening 5k", 6.00, 156),
            (1, "Sunday long run", 14.10, 148),
        ]

        for daysBack in 0...175 {
            guard let day = calendar.date(byAdding: .day, value: -daysBack, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            guard let slot = pattern.first(where: { $0.weekday == weekday }) else { continue }

            // Volume and pace improve toward today; a light wave keeps it organic.
            let progress = 1 - Double(daysBack) / 175 // 0 → oldest, 1 → today
            let wave = sin(Double(daysBack) / 9) * 0.6
            let km = max(slot.km * (0.82 + 0.18 * progress) + wave, 4)
            let pace = (349 - 25 * progress) * (slot.name == "Evening 5k" ? 0.94 : 1.0)
            let duration = km * pace
            let hour = slot.weekday == 6 ? 18 : 7

            var splits: [TimeInterval] = []
            for index in 0..<Int(km.rounded(.down)) {
                splits.append(pace + sin(Double(index) * 1.7) * 9 - Double(index % 3) * 3)
            }

            let zoneWeights: [Double] = [0.08, 0.30, 0.42, 0.16, 0.04]
            let zoneSeconds = zoneWeights.map { $0 * duration }

            let runDate = calendar.date(bySettingHour: hour, minute: [2, 14, 31, 48][daysBack % 4], second: 0, of: day)!
            guard runDate <= .now else { continue }
            runs.append(Run(
                date: runDate,
                name: slot.name,
                distanceKm: (km * 100).rounded() / 100,
                duration: (duration).rounded(),
                avgHR: slot.hr - Int(4 * progress.rounded()),
                splits: splits,
                zoneSeconds: zoneSeconds
            ))
        }

        // One ridge trail and one pacer session for variety.
        if runs.count > 4 {
            var trail = runs[4]
            trail.type = .trail
            trail.name = "Ridge trail"
            trail.distanceKm = 14.2
            trail.duration = 6728
            trail.avgHR = 152
            trail.splits = [412, 448, 471, 502, 476, 455, 490, 468, 441, 452, 447, 438, 429, 433]
            trail.climbMeters = 918
            trail.descentMeters = 902
            trail.highPointMeters = 1622
            runs[4] = trail
        }
        if runs.count > 9 {
            var pacer = runs[9]
            pacer.type = .pacer
            pacer.name = "Pacer 5:15"
            pacer.duration = pacer.distanceKm * 315
            runs[9] = pacer
        }

        return runs.sorted { $0.date > $1.date }
    }

    static let records: [RecordEntry] = [
        RecordEntry(
            label: "5k", value: "25:38",
            date: Calendar.current.date(byAdding: .day, value: -5, to: .now)!,
            isNew: true, delta: "−0:41 vs previous"
        ),
        RecordEntry(label: "1 km", value: "4:41", date: Calendar.current.date(byAdding: .day, value: -23, to: .now)!),
        RecordEntry(label: "10 km", value: "53:12", date: Calendar.current.date(byAdding: .day, value: -16, to: .now)!),
        RecordEntry(label: "Half marathon", value: "1:58:47", date: Calendar.current.date(byAdding: .day, value: -47, to: .now)!),
        RecordEntry(label: "Longest run", value: "24.6 km", date: Calendar.current.date(byAdding: .day, value: -47, to: .now)!),
    ]

    /// Avg pace per week for the trend chart, oldest first (sec/km).
    static let paceTrend: [TimeInterval] = [
        345, 349, 342, 347, 341, 338, 340, 334, 332, 330, 327, 324,
    ]
}
