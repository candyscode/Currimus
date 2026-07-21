import Foundation

/// The few numbers a complication shows, read straight from shared defaults.
///
/// The widget used to build a whole `RunStore` for this — which seeds
/// settings, activates WatchConnectivity, wires sync callbacks and now lives
/// on the main actor, none of which belongs in a timeline provider. Reading
/// the two keys it actually needs is both cheaper and honest about the
/// dependency.
struct WeekSnapshot: Equatable {
    var weekKm: Double
    var goalKm: Double
    var lastPace: TimeInterval
    var runCount: Int

    static let placeholder = WeekSnapshot(weekKm: 0, goalKm: 55, lastPace: 0, runCount: 0)

    static func current(defaults: UserDefaults = AppDefaults.shared,
                        now: Date = .now) -> WeekSnapshot {
        let runs = decode(AppDefaults.runsKey, from: defaults)
            + decode(AppDefaults.importedKey, from: defaults)
        // Monday-first, like every other weekly total in the app — a
        // complication disagreeing with the app it belongs to is worse than
        // either number on its own.
        let calendar = Calendar.runWeek
        let thisWeek = runs.filter {
            calendar.isDate($0.date, equalTo: now, toGranularity: .weekOfYear)
        }
        return WeekSnapshot(
            weekKm: thisWeek.reduce(0) { $0 + $1.distanceKm },
            goalKm: defaults.object(forKey: AppDefaults.goalKey) != nil
                ? defaults.double(forKey: AppDefaults.goalKey)
                : placeholder.goalKm,
            lastPace: runs.max { $0.date < $1.date }?.paceSecPerKm ?? 0,
            runCount: thisWeek.count
        )
    }

    private static func decode(_ key: String, from defaults: UserDefaults) -> [Run] {
        guard let data = defaults.data(forKey: key) else { return [] }
        do {
            return try JSONDecoder().decode([Run].self, from: data)
        } catch {
            Log.store.error("widget could not read \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
