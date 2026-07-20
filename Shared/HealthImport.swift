import Foundation
import HealthKit

/// Runs recorded by *other* apps — Apple Fitness, Nike, Strava — pulled out of
/// Apple Health so the weekly totals, progress and widgets describe everything
/// the user actually ran, not just what Currimus happened to record.
///
/// Currimus' own workouts are in Health too, so they are filtered out by source
/// bundle id; a time-overlap guard catches the rarer case of two apps recording
/// the same run.
enum HealthImport {
    /// Our own writers — the watch app saves workouts, the phone may later.
    private static let ownBundlePrefix = "com.currimus.app"

    /// Types we need to read to build an imported run.
    static var readTypes: Set<HKObjectType> {
        [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.distanceWalkingRunning),
        ]
    }

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Asks for read access. Health never reveals whether *read* access was
    /// granted — a denied type simply returns no samples — so the result only
    /// says the prompt completed.
    static func requestAuthorization(_ store: HKHealthStore) async {
        guard isAvailable else { return }
        try? await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// Every running workout from another app in the given window.
    static func fetchRuns(
        _ store: HKHealthStore,
        since: Date = Calendar.current.date(byAdding: .month, value: -18, to: .now) ?? .distantPast
    ) async -> [Run] {
        guard isAvailable else { return [] }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .running),
            HKQuery.predicateForSamples(withStart: since, end: nil),
        ])
        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, _ in
                continuation.resume(returning: samples as? [HKWorkout] ?? [])
            }
            store.execute(query)
        }
        return workouts
            .filter { !$0.sourceRevision.source.bundleIdentifier.hasPrefix(ownBundlePrefix) }
            .map(run(from:))
            .filter { $0.distanceKm > 0.2 && $0.duration > 60 }
    }

    /// Imported runs minus any that overlap a run Currimus recorded itself —
    /// two apps tracking the same outing must not count twice.
    static func merging(_ imported: [Run], with own: [Run]) -> [Run] {
        imported.filter { candidate in
            let range = candidate.date...(candidate.date + candidate.duration)
            return !own.contains { mine in
                let mineRange = mine.date...(mine.date + mine.duration)
                return range.overlaps(mineRange)
            }
        }
    }

    private static func run(from workout: HKWorkout) -> Run {
        let meters = workout
            .statistics(for: HKQuantityType(.distanceWalkingRunning))?
            .sumQuantity()?
            .doubleValue(for: .meter()) ?? 0
        let hr = workout
            .statistics(for: HKQuantityType(.heartRate))?
            .averageQuantity()?
            .doubleValue(for: .count().unitDivided(by: .minute()))
        let climb = (workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?
            .doubleValue(for: .meter())

        return Run(
            // The workout's own UUID keeps the identity stable across imports.
            id: workout.uuid,
            date: workout.startDate,
            type: .quick,
            name: workout.sourceRevision.source.name,
            distanceKm: meters / 1000,
            duration: workout.duration,
            avgHR: Int((hr ?? 0).rounded()),
            splits: [],
            zoneSeconds: [0, 0, 0, 0, 0],
            climbMeters: climb,
            imported: true
        )
    }
}
