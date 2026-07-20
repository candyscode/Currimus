import Foundation

/// The shared preference store and the keys inside it.
///
/// Separate from `RunStore` because the widget's timeline provider needs the
/// same bytes without the main-actor-bound store around them.
enum AppDefaults {
    static let runsKey = "runs.v2"
    static let importedKey = "imported.v1"
    static let raceKey = "race.v1"
    static let settingsKey = "settings.v1"
    static let goalKey = "weeklyGoal"
    static let unitsKey = "usesKilometers"
    static let gpsAccuracyKey = "gpsAccuracy"

    static let appGroup = "group.com.currimus.app"

    /// App-group defaults so the widget extension reads the same store as the
    /// app; falls back to standard defaults if the group is unavailable.
    ///
    /// `nonisolated(unsafe)` because `UserDefaults` is documented as thread-safe
    /// but is not annotated `Sendable`. Stating that once here beats either
    /// pinning the store to an actor it does not need or silencing strict
    /// concurrency project-wide.
    nonisolated(unsafe) static let shared: UserDefaults = {
        guard let shared = UserDefaults(suiteName: appGroup) else {
            Log.store.error("app group unavailable — falling back to standard defaults")
            return .standard
        }
        // The log used to live in standard defaults. Moving to the group would
        // read as "all my runs vanished", so carry them over once.
        for key in [runsKey, raceKey, settingsKey, goalKey, unitsKey]
        where shared.object(forKey: key) == nil {
            if let legacy = UserDefaults.standard.object(forKey: key) {
                shared.set(legacy, forKey: key)
            }
        }
        return shared
    }()
}
