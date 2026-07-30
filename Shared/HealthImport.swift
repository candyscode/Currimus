import Foundation
import HealthKit
import CoreLocation

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

    /// Types we need to read to build an imported run and to personalise the
    /// heart-rate zones.
    static var readTypes: Set<HKObjectType> {
        [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.stepCount),
            // The GPS track of a run another app recorded, so its detail
            // screen can draw a map instead of an apology.
            HKSeriesType.workoutRoute(),
            HKCharacteristicType(.dateOfBirth),
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

    // MARK: - The heavy half of an imported workout

    /// What a run another app recorded keeps in Health but not in the log: the
    /// heart-rate trace and the GPS route.
    ///
    /// Fetched on demand, when a detail screen actually asks. Pulling the
    /// route and every heart-rate sample of eighteen months of workouts on
    /// each refresh would spend a lot of battery filling screens nobody opened.
    struct WorkoutDetail: Equatable {
        var zoneSeconds: [TimeInterval]
        var route: [Coordinate]
        /// Distance per zone, paired back together from the two above. nil
        /// when one of them is missing — a treadmill run, or one without a
        /// strap — and then the run is simply not measured.
        var zoneDistanceKm: [Double]?
        /// Per-kilometre splits recovered from the route.
        var splits: [TimeInterval]
        /// Flat-equivalent pace from the route's own gradients, after Minetti.
        var gradeAdjustedSecPerKm: Double?

        var isEmpty: Bool {
            zoneSeconds.reduce(0, +) < 1 && route.isEmpty
        }
    }

    /// How long one heart-rate sample is taken to stand for: until the next
    /// one, but never longer than this. A gap where nothing was recorded is
    /// not time spent in whatever zone was last seen.
    static let maxSampleSpan: TimeInterval = 60

    /// Seconds per zone from a heart-rate trace. Pure, so the arithmetic can
    /// be tested without a Health store.
    static func zoneSeconds(from samples: [(bpm: Int, at: Date)],
                            zones: HRZones, end: Date) -> [TimeInterval] {
        var seconds = [TimeInterval](repeating: 0, count: 5)
        for (index, sample) in samples.enumerated() {
            let next = index + 1 < samples.count ? samples[index + 1].at : end
            let span = min(max(next.timeIntervalSince(sample.at), 0), maxSampleSpan)
            let zone = zones.zone(for: sample.bpm)
            guard zone >= 1, zone <= 5 else { continue }
            seconds[zone - 1] += span
        }
        return seconds
    }

    /// `fallbackRoute` is used when Health has no route of its own for the
    /// workout — a run Currimus recorded keeps its track in its own sidecar,
    /// and there is no reason to fetch it twice.
    /// Why a rebuild produced nothing, which is not one question but two.
    ///
    /// "Health has no such workout" is final — that run will never gain
    /// anything and should stop being offered. "Health could not answer" is
    /// not: the device may be locked, or access not yet granted, and treating
    /// that as final tells the runner everything is rebuilt when nothing was.
    enum DetailOutcome {
        case detail(WorkoutDetail)
        case noWorkout
        case unavailable
    }

    static func detail(for run: Run, zones: HRZones,
                       fallbackRoute: [Coordinate]? = nil,
                       in store: HKHealthStore) async -> DetailOutcome {
        guard isAvailable else { return .unavailable }
        // An imported run carries the workout's own UUID as its id, so it can
        // be asked for directly. A run Currimus recorded has an id of its own
        // and has to be found by when it happened — the same match the delete
        // uses, and the same reason: the two ids were never tied together.
        let lookup = await workout(with: run.id, in: store)
        if case .failed = lookup { return .unavailable }
        var found = lookup.workout
        if found == nil, !run.isImported {
            // The other half of the same question, and it used to swallow its
            // error: a failed query looked exactly like "no such workout", so
            // a rebuild interrupted by a locking phone marked every remaining
            // run as final.
            let own = await ownWorkouts(matching: run, in: store)
            if case .failed = own { return .unavailable }
            found = own.workouts.first
        }
        guard let workout = found else { return .noWorkout }
        let samples = await heartRateSamples(of: workout, in: store)
        let locations = await routeLocations(of: workout, in: store)
        var route = locations.map {
            Coordinate(lat: $0.coordinate.latitude, lon: $0.coordinate.longitude,
                       elevation: $0.altitude,
                       t: max($0.timestamp.timeIntervalSince(workout.startDate), 0))
        }
        if route.isEmpty, let fallbackRoute, !fallbackRoute.isEmpty { route = fallbackRoute }
        // Both halves were recorded over the same run; pairing them puts back
        // everything the workout's summary threw away.
        let trace = samples.map {
            (bpm: $0.bpm, at: $0.at.timeIntervalSince(workout.startDate))
        }
        // A track when there is one, and otherwise the distance samples the
        // watch wrote anyway — which is what a treadmill run has instead. It
        // is the same arithmetic either way, and without this an indoor run
        // could never contribute to zone-2 pace or hold a record.
        var distance = RunAnalytics.distanceTrace(fromRoute: route)
        if distance.count < 2 {
            distance = await distanceTrace(of: workout, in: store)
        }
        return .detail(WorkoutDetail(
            zoneSeconds: zoneSeconds(from: samples, zones: zones, end: workout.endDate),
            route: route,
            zoneDistanceKm: RunAnalytics.zoneDistanceKm(trace: distance, heartRate: trace, zones: zones),
            splits: RunAnalytics.splits(trace: distance),
            // Gradients need a track; a treadmill has none, and a flat run's
            // adjusted pace is its pace.
            gradeAdjustedSecPerKm: RunAnalytics.gradeAdjustedPace(route: route,
                                                                  duration: workout.duration)
        ))
    }

    /// A lookup either answered — with a workout or with nothing — or it did
    /// not run at all.
    private enum WorkoutLookup {
        case found(HKWorkout)
        case none
        case failed

        var workout: HKWorkout? {
            if case .found(let workout) = self { return workout }
            return nil
        }
    }

    private static func workout(with id: UUID, in store: HKHealthStore) async -> WorkoutLookup {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: HKQuery.predicateForObject(with: id),
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if error != nil { return continuation.resume(returning: .failed) }
                guard let workout = samples?.first as? HKWorkout else {
                    return continuation.resume(returning: WorkoutLookup.none)
                }
                continuation.resume(returning: .found(workout))
            }
            store.execute(query)
        }
    }

    private static func heartRateSamples(of workout: HKWorkout,
                                         in store: HKHealthStore) async -> [(bpm: Int, at: Date)] {
        let unit = HKUnit.count().unitDivided(by: .minute())
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKQuantityType(.heartRate),
                // By time rather than by association: plenty of apps save a
                // workout without tying the heart-rate samples to it, and the
                // watch's own readings during that window are the same trace.
                predicate: HKQuery.predicateForSamples(withStart: workout.startDate,
                                                       end: workout.endDate),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                let readings = (samples as? [HKQuantitySample] ?? []).map {
                    (bpm: Int($0.quantity.doubleValue(for: unit).rounded()), at: $0.startDate)
                }
                continuation.resume(returning: readings)
            }
            store.execute(query)
        }
    }

    /// The route arrives in batches, so the locations are collected in a box
    /// the query's own queue can safely append to, and the continuation is
    /// resumed exactly once — twice would trap.
    private final class RouteBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var locations: [CLLocation] = []
        private var finished = false

        /// Appends a batch; returns everything when this was the last one.
        func add(_ batch: [CLLocation]?, done: Bool) -> [CLLocation]? {
            lock.lock()
            defer { lock.unlock() }
            locations.append(contentsOf: batch ?? [])
            guard done, !finished else { return nil }
            finished = true
            return locations
        }
    }

    private static func routeLocations(of workout: HKWorkout,
                                       in store: HKHealthStore) async -> [CLLocation] {
        guard let series = await routeSeries(of: workout, in: store) else { return [] }
        return await withCheckedContinuation { continuation in
            let buffer = RouteBuffer()
            let query = HKWorkoutRouteQuery(route: series) { _, locations, done, error in
                // An error ends the query whether or not `done` was set, and a
                // continuation that is never resumed leaves the detail screen
                // waiting on it for the rest of the session.
                if let all = buffer.add(locations, done: done || error != nil) {
                    continuation.resume(returning: all)
                }
            }
            store.execute(query)
        }
    }

    /// Cumulative distance over the workout, from Health's own samples.
    ///
    /// **One source, or the numbers double.** `HKSampleQuery` does not
    /// deduplicate the way the Health app's own charts do: an iPhone carried on
    /// a run writes `distanceWalkingRunning` alongside the watch, and adding
    /// both up gives a run twice as long as it was. Every kilometre mark then
    /// falls at half the real distance, so the recovered splits come out roughly
    /// twice as fast — and those splits set records.
    ///
    /// Samples tied to the workout are asked for first. Plenty of apps save a
    /// workout without tying anything to it, so the fallback is the same
    /// *source* over the workout's window — the app that recorded the run is the
    /// one whose distance describes it — rather than everything in the window
    /// from every source on the device.
    private static func distanceTrace(of workout: HKWorkout,
                                      in store: HKHealthStore) async -> [RunAnalytics.DistancePoint] {
        var samples = await distanceSamples(HKQuery.predicateForObjects(from: workout), in: store)
        if samples.isEmpty {
            samples = await distanceSamples(
                NSCompoundPredicate(andPredicateWithSubpredicates: [
                    HKQuery.predicateForObjects(from: workout.sourceRevision.source),
                    HKQuery.predicateForSamples(withStart: workout.startDate,
                                                end: workout.endDate),
                ]),
                in: store)
        }
        // Each sample is the distance covered over its own interval, so they
        // add up to the run.
        var covered = 0.0
        var points: [RunAnalytics.DistancePoint] = [(km: 0, at: 0)]
        for sample in samples {
            covered += sample.quantity.doubleValue(for: .meter()) / 1000
            points.append((km: covered,
                           at: max(sample.endDate.timeIntervalSince(workout.startDate), 0)))
        }
        return points
    }

    private static func distanceSamples(_ predicate: NSPredicate,
                                        in store: HKHealthStore) async -> [HKQuantitySample] {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKQuantityType(.distanceWalkingRunning),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
            }
            store.execute(query)
        }
    }

    private static func routeSeries(of workout: HKWorkout,
                                    in store: HKHealthStore) async -> HKWorkoutRoute? {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKSeriesType.workoutRoute(),
                predicate: HKQuery.predicateForObjects(from: workout),
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: samples?.first as? HKWorkoutRoute)
            }
            store.execute(query)
        }
    }

    // MARK: - Deleting our own workouts

    /// What came of trying to take a run's workout out of Apple Health.
    ///
    /// A run deleted here has to leave Health too — otherwise the outing the
    /// runner just disowned keeps counting in Fitness, in the rings and in
    /// every other app reading the same store. But Health can say no, and a
    /// refusal has to be reported rather than swallowed: telling someone a
    /// workout is gone when it is still there is the one outcome to avoid.
    enum Deletion: Equatable {
        /// Removed, along with the GPS routes attached to them.
        case removed(workouts: Int)
        /// Health held nothing of ours for these runs — an entry that predates
        /// the Health connection, or one that never reached it.
        case nothingFound
        /// Write access to workouts was declined.
        case refused
        case failed(String)
        case unavailable
    }

    /// Deleting is a write, so Health gates it on *share* authorization — for
    /// the route series as well, which is a separate type.
    private static var deletableTypes: Set<HKSampleType> {
        [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
    }

    /// How far a workout's start may sit from the run's before the two stop
    /// being the same outing. The watch stamps the run and begins the workout
    /// in the same breath, so this is slack for the clock, not a guess.
    static let matchWindow: TimeInterval = 120

    /// Whether a workout starting at `start` is the one this run was recorded
    /// as. Deliberately narrow: two runs on the same morning are minutes and a
    /// whole recording apart, and deleting the wrong one is unrecoverable.
    static func isSameOuting(start: Date, as run: Run) -> Bool {
        abs(start.timeIntervalSince(run.date)) <= matchWindow
    }

    /// Removes the workouts Currimus saved for these runs, and the routes
    /// hanging off them — deleting a workout leaves its route behind.
    ///
    /// Only ever our own recordings: HealthKit refuses to delete another app's
    /// samples, which is why an imported run is never offered a delete at all.
    static func deleteWorkouts(for runs: [Run], in store: HKHealthStore) async -> Deletion {
        let mine = runs.filter { !$0.isImported }
        guard isAvailable else { return .unavailable }
        guard !mine.isEmpty else { return .nothingFound }

        // The phone had only ever read Health, so the write permission is
        // asked for here — at the first delete, where what it is for is
        // obvious — rather than at launch, where a sheet offering to write
        // workouts would answer a question nobody had asked.
        try? await store.requestAuthorization(toShare: deletableTypes, read: readTypes)
        guard store.authorizationStatus(for: HKObjectType.workoutType()) != .sharingDenied else {
            return .refused
        }

        var workouts: [HKWorkout] = []
        for run in mine {
            workouts.append(contentsOf: await ownWorkouts(matching: run, in: store).workouts)
        }
        guard !workouts.isEmpty else { return .nothingFound }

        var doomed: [HKObject] = workouts
        for workout in workouts {
            doomed.append(contentsOf: await routes(of: workout, in: store))
        }
        do {
            try await store.delete(doomed)
            return .removed(workouts: workouts.count)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// The workouts Currimus itself saved for this run. Queried over a window
    /// around the run rather than by identifier: the log's id is Currimus', the
    /// workout's is Health's, and the two were never tied together.
    /// Several workouts, or the admission that the question could not be put.
    private enum WorkoutsLookup {
        case found([HKWorkout])
        case failed

        var workouts: [HKWorkout] {
            if case .found(let workouts) = self { return workouts }
            return []
        }
    }

    private static func ownWorkouts(matching run: Run, in store: HKHealthStore) async -> WorkoutsLookup {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .running),
            HKQuery.predicateForSamples(
                withStart: run.date.addingTimeInterval(-matchWindow),
                end: run.date.addingTimeInterval(run.duration + matchWindow)
            ),
        ])
        let lookup: WorkoutsLookup = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if error != nil { return continuation.resume(returning: .failed) }
                continuation.resume(returning: .found(samples as? [HKWorkout] ?? []))
            }
            store.execute(query)
        }
        guard case .found(let found) = lookup else { return .failed }
        return .found(found.filter {
            $0.sourceRevision.source.bundleIdentifier.hasPrefix(ownBundlePrefix)
                && isSameOuting(start: $0.startDate, as: run)
        })
    }

    private static func routes(of workout: HKWorkout, in store: HKHealthStore) async -> [HKObject] {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKSeriesType.workoutRoute(),
                predicate: HKQuery.predicateForObjects(from: workout),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: samples as? [HKObject] ?? [])
            }
            store.execute(query)
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
        // A treadmill run says so in its metadata, and saying it back is the
        // difference between "no GPS track for this run" reading as a fault
        // and reading as a fact.
        let indoor = (workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool) == true
        // Cadence is steps over moving time. Most apps write the step count
        // with the workout; the ones that do not simply have no cadence, which
        // is a missing measurement rather than a zero.
        let steps = workout
            .statistics(for: HKQuantityType(.stepCount))?
            .sumQuantity()?
            .doubleValue(for: .count())
        let cadence = steps.flatMap { steps -> Int? in
            guard steps > 0, workout.duration >= 60 else { return nil }
            return Int((steps / (workout.duration / 60)).rounded())
        }

        return Run(
            // The workout's own UUID keeps the identity stable across imports.
            id: workout.uuid,
            date: workout.startDate,
            type: .quick,
            // Not `sourceRevision.source.name`. That is the recording app's
            // name only for third-party apps — for anything Apple's own Workout
            // app recorded it is the *device* name, so the log filled up with
            // rows reading "Apple Watch von Andreas", which says nothing about
            // the run and says it over and over.
            name: RunNaming.defaultName(for: workout.startDate, isIndoor: indoor),
            distanceKm: meters / 1000,
            duration: workout.duration,
            avgHR: Int((hr ?? 0).rounded()),
            splits: [],
            zoneSeconds: [0, 0, 0, 0, 0],
            climbMeters: climb,
            imported: true,
            isIndoor: indoor ? true : nil,
            cadenceSpm: cadence
        )
    }
}
