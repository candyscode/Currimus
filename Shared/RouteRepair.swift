import Foundation
import CoreLocation
import HealthKit

/// Puts the GPS track back onto a workout in Apple Health that was saved
/// without one.
///
/// The route is written by the watch at the end of a run, in a call that
/// happens *after* the workout has already been handed to healthd. The workout
/// therefore survives a suspension and the route does not — which is how a run
/// came to sit in Apple Fitness with no map while Currimus, which keeps its own
/// copy of the track, drew one perfectly well (CUR-44). `RunSession` now holds a
/// background assertion across that gap, but a fix that only helps future runs
/// leaves every run already recorded without its map. This is the sweep that
/// repairs them.
///
/// It runs on the **watch**, and it has to: HealthKit only lets an app attach
/// objects to a workout it saved itself, and the watch is what saved these.
enum RouteRepair {
    /// Ids whose workout has been confirmed to carry a route, so the sweep
    /// stops asking Health about them on every launch.
    static let settledKey = "routesSettled.v1"

    /// How far back to look. A run older than this either has its route or
    /// never will — and the sweep is meant to cost nothing on a normal launch.
    static let window: TimeInterval = 60 * 24 * 3600

    /// At most this many runs are examined per launch, newest first. The check
    /// is two Health queries per run and the app has other things to do when it
    /// comes up.
    static let batch = 8

    /// The runs worth asking Health about: recorded by Currimus itself, recent,
    /// not already settled, and long enough ago that the live save has had its
    /// chance. A run that finished seconds ago is still being written.
    static func candidates(from runs: [Run], settled: Set<UUID>,
                           now: Date = .now) -> [Run] {
        runs.filter { run in
            !run.isImported
                && run.recovered != true
                && !settled.contains(run.id)
                && now.timeIntervalSince(run.date) < window
                && now.timeIntervalSince(run.date) > run.duration + 120
        }
        .sorted { $0.date > $1.date }
        .prefix(batch)
        .map { $0 }
    }

    /// A run's stored track as locations HealthKit will accept.
    ///
    /// `insertRouteData` rejects a location whose accuracy is negative, and the
    /// stored track carries no accuracy of its own — every point in it already
    /// passed `RunMetrics.usableHorizontalAccuracy` on the way in, so that
    /// limit is stated back as an honest upper bound rather than a flattering
    /// guess. Timestamps are the run's start plus each point's own offset,
    /// which is wall-clock and so includes the pauses, exactly as the GPX
    /// export writes them.
    static func locations(for run: Run, track: [Coordinate]) -> [CLLocation] {
        track.map { point in
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon),
                altitude: point.elevation,
                horizontalAccuracy: RunMetrics.usableHorizontalAccuracy,
                verticalAccuracy: RunMetrics.usableVerticalAccuracy,
                timestamp: run.date.addingTimeInterval(point.t)
            )
        }
    }

    /// What one run's repair came to. `settled` means stop asking: either the
    /// route is there or nothing this app does will put it there.
    enum Outcome: Equatable {
        /// The workout already had its route.
        case present
        /// A route was written for it.
        case repaired(points: Int)
        /// No workout, no track, or Health said no — see the log.
        case skipped(String)

        var settled: Bool {
            switch self {
            case .present, .repaired: return true
            case .skipped: return false
            }
        }
    }
}

#if os(watchOS)
extension RouteRepair {
    /// Checks each candidate and writes the routes that are missing. Returns
    /// the ids that need never be looked at again.
    static func sweep(_ runs: [Run], in store: HKHealthStore,
                      loadTrack: (UUID) -> [Coordinate]? = { RunSampleStore.load($0)?.route }
    ) async -> Set<UUID> {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        // Writing a route needs share authorization for the series type. The
        // watch asks for it before every run, so this is a check rather than a
        // prompt: a sweep must never put a permission sheet in front of someone
        // who just opened the app.
        guard store.authorizationStatus(for: HKSeriesType.workoutRoute()) == .sharingAuthorized
        else { return [] }

        var settled: Set<UUID> = []
        for run in runs {
            let outcome = await repair(run, in: store, track: loadTrack(run.id))
            switch outcome {
            case .present:
                settled.insert(run.id)
            case .repaired(let points):
                Log.store.notice("route of \(points, privacy: .public) points restored in Health")
                settled.insert(run.id)
            case .skipped(let why):
                Log.store.notice("route not restored: \(why, privacy: .public)")
            }
        }
        return settled
    }

    static func repair(_ run: Run, in store: HKHealthStore,
                       track: [Coordinate]?) async -> Outcome {
        guard let track, track.count > 1 else { return .skipped("no track stored") }
        guard let workout = await HealthImport.ownWorkout(matching: run, in: store) else {
            return .skipped("no workout of ours for this run")
        }
        if await HealthImport.hasRoute(workout, in: store) { return .present }

        let builder = HKWorkoutRouteBuilder(healthStore: store, device: nil)
        let points = locations(for: run, track: track)
        do {
            try await builder.insertRouteData(points)
            _ = try await builder.finishRoute(with: workout, metadata: nil)
            return .repaired(points: points.count)
        } catch {
            return .skipped(error.localizedDescription)
        }
    }
}
#endif
