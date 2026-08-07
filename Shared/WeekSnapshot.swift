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
        let runs = SharedRuns.all(from: defaults)
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
}

/// Week, month and year distance — the three totals the Distance widget shows.
///
/// The buckets are the app's own: weeks are Monday-first (`Calendar.runWeek`),
/// months and years follow `Calendar.current`, exactly as `RunStore` does. A
/// widget that disagreed with the screen behind it would be worse than no
/// widget.
///
/// **The iPhone works these out and pushes them; the watch does not add them
/// up itself.** It cannot: the HealthKit store on Apple Watch holds what the
/// watch recorded plus a short window synced from the phone, not a history —
/// so a year read on the watch is missing everything older than that window
/// and every run recorded by an app that only exists on the phone. A clean
/// install showed 37 km for a year that was many times that (CUR-46), and no
/// amount of sweeping the watch's own Health store can fix it, because the
/// data is not there to sweep.
///
/// What the watch still contributes is the near edge: a run it recorded after
/// the last push, which the phone has not counted yet. Those are added on top,
/// so a run finished on a walk home shows in the complication before the phone
/// has heard about it.
struct DistanceTotals: Equatable, Codable {
    var weekKm: Double
    var monthKm: Double
    var yearKm: Double
    /// When the iPhone worked these out. nil on a record computed locally.
    var pushedAt: Date?

    static let placeholder = DistanceTotals(weekKm: 0, monthKm: 0, yearKm: 0)

    init(weekKm: Double, monthKm: Double, yearKm: Double, pushedAt: Date? = nil) {
        self.weekKm = weekKm
        self.monthKm = monthKm
        self.yearKm = yearKm
        self.pushedAt = pushedAt
    }

    static func current(defaults: UserDefaults = AppDefaults.shared,
                        now: Date = .now) -> DistanceTotals {
        guard let pushed = pushed(from: defaults), let pushedAt = pushed.pushedAt else {
            // No phone has spoken yet — a watch that has never paired, or the
            // first launch after an install. Its own log is all there is, and
            // being short is better than being blank.
            return local(SharedRuns.all(from: defaults), now: now)
        }
        // Only runs the push cannot have included, or they would count twice.
        let unseen = SharedRuns.all(from: defaults).filter { $0.date > pushedAt }
        let extra = local(unseen, now: now)
        return DistanceTotals(weekKm: pushed.weekKm + extra.weekKm,
                              monthKm: pushed.monthKm + extra.monthKm,
                              yearKm: pushed.yearKm + extra.yearKm,
                              pushedAt: pushedAt)
    }

    /// The three buckets over a given set of runs. This is what the **iPhone**
    /// calls, over its whole log, to produce the record it pushes.
    static func local(_ runs: [Run], now: Date = .now) -> DistanceTotals {
        let calendar = Calendar.current
        func total(_ include: (Run) -> Bool) -> Double {
            runs.lazy.filter(include).reduce(0) { $0 + $1.distanceKm }
        }
        return DistanceTotals(
            weekKm: total { Calendar.runWeek.isDate($0.date, equalTo: now, toGranularity: .weekOfYear) },
            monthKm: total { calendar.isDate($0.date, equalTo: now, toGranularity: .month) },
            yearKm: total { calendar.isDate($0.date, equalTo: now, toGranularity: .year) }
        )
    }

    static func pushed(from defaults: UserDefaults = AppDefaults.shared) -> DistanceTotals? {
        guard let data = defaults.data(forKey: AppDefaults.totalsKey) else { return nil }
        return try? JSONDecoder().decode(DistanceTotals.self, from: data)
    }
}

/// Every run the app group holds — Currimus' own plus the ones imported from
/// Apple Health, the same union `RunStore.allRuns` serves the app from.
enum SharedRuns {
    static func all(from defaults: UserDefaults = AppDefaults.shared) -> [Run] {
        decode(AppDefaults.runsKey, from: defaults)
            + decode(AppDefaults.importedKey, from: defaults)
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
