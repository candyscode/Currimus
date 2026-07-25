import Foundation

/// The arithmetic of a run in flight: rolling pace, per-kilometer splits,
/// climb and climb rate, time in zones, and the sampling of the altitude
/// series and GPS track.
///
/// Deliberately pure — it owns no clock, no HealthKit, no location manager.
/// Callers hand it readings and it hands back state, which is what makes the
/// awkward cases testable: a runner stopped at a traffic light, GPS altitude
/// jitter, a four-hour ultra, a kilometer split landing on the same second as
/// a pause. `RunSession` is then only lifecycle wiring around this.
struct RunMetrics: Equatable {

    /// A completed kilometer, reported back to whoever wants to alert on it.
    struct KilometerSplit: Equatable {
        var km: Int
        var seconds: TimeInterval
        var deltaVsAverage: TimeInterval
    }

    // MARK: - Tuning

    /// Altitude series: one sample per `altitudeInterval`, never more than
    /// this many points. See `decimated` for what happens at the ceiling.
    static let altitudeCapacity = 240
    static let initialAltitudeInterval: TimeInterval = 10

    /// GPS track: same shape, coarser budget (it feeds the map and GPX).
    static let routeCapacity = 2_000
    static let initialRouteInterval: TimeInterval = 5

    /// GPS altitude wanders by a metre or two while standing still; only
    /// movement beyond this counts as climb or descent.
    static let altitudeNoiseFloor = 1.5
    /// Vertical accuracy worse than this (or negative = invalid) is discarded.
    static let usableVerticalAccuracy = 12.0
    static let usableHorizontalAccuracy = 50.0

    // MARK: - Output

    private(set) var splits: [TimeInterval] = []
    private(set) var rollingPace: TimeInterval = 0
    private(set) var climbMeters: Double = 0
    private(set) var descentMeters: Double = 0
    private(set) var climbRatePerHour: Double = 0
    private(set) var altitudeMeters: Double = 0
    private(set) var altitudeProfile: [Double] = []
    private(set) var coordinates: [Coordinate] = []
    private(set) var zoneSeconds: [TimeInterval] = [0, 0, 0, 0, 0]

    /// Mean of every heart-rate reading seen, not just the last one.
    var averageHR: Int { hrSampleCount > 0 ? hrSampleSum / hrSampleCount : 0 }

    // MARK: - Internals

    private var lastKmMark: Double = 0
    private var kmStartElapsed: TimeInterval = 0
    private var hrSampleSum = 0
    private var hrSampleCount = 0
    /// (elapsed, distance) ring backing the rolling-pace window.
    private var paceWindow: [(t: TimeInterval, d: Double)] = []
    /// (elapsed, climb) ring backing the 10-minute climb rate.
    private var climbWindow: [(t: TimeInterval, c: Double)] = []
    private var lastAltitude: Double?
    private var altitudeInterval = RunMetrics.initialAltitudeInterval
    private var lastAltitudeSample: TimeInterval = -.greatestFiniteMagnitude
    private var routeInterval = RunMetrics.initialRouteInterval
    private var lastRouteSample: TimeInterval = -.greatestFiniteMagnitude

    static func == (lhs: RunMetrics, rhs: RunMetrics) -> Bool {
        lhs.splits == rhs.splits && lhs.rollingPace == rhs.rollingPace
            && lhs.climbMeters == rhs.climbMeters && lhs.descentMeters == rhs.descentMeters
            && lhs.climbRatePerHour == rhs.climbRatePerHour
            && lhs.altitudeProfile == rhs.altitudeProfile
            && lhs.coordinates == rhs.coordinates && lhs.zoneSeconds == rhs.zoneSeconds
    }

    // MARK: - Per-second tick

    /// Advances one recorded second. Returns the split if this second closed
    /// a kilometer.
    @discardableResult
    mutating func tick(elapsed: TimeInterval, distanceKm: Double,
                       heartRate: Int, zone: Int) -> KilometerSplit? {
        if heartRate > 0 {
            hrSampleSum += heartRate
            hrSampleCount += 1
            if (1...5).contains(zone) { zoneSeconds[zone - 1] += 1 }
        }
        updateRollingPace(elapsed: elapsed, distanceKm: distanceKm)
        updateClimbRate(elapsed: elapsed)
        return closeKilometer(elapsed: elapsed, distanceKm: distanceKm)
    }

    /// Rolling pace over the last kilometer. Falls back to a time window early
    /// on, and reports nothing at all when the runner has stopped — a stale
    /// pace is worse than an honest blank.
    private mutating func updateRollingPace(elapsed: TimeInterval, distanceKm: Double) {
        paceWindow.append((elapsed, distanceKm))
        while let first = paceWindow.first,
              distanceKm - first.d > 1.0 || elapsed - first.t > 600 {
            paceWindow.removeFirst()
        }
        guard let first = paceWindow.first else { return }
        let dt = elapsed - first.t
        let dd = distanceKm - first.d
        if dd > 0.015, dt > 20 {
            rollingPace = dt / dd
        } else if dt > 45 {
            rollingPace = 0
        }
    }

    private mutating func updateClimbRate(elapsed: TimeInterval) {
        climbWindow.append((elapsed, climbMeters))
        while let first = climbWindow.first, elapsed - first.t > 600 {
            climbWindow.removeFirst()
        }
        guard let first = climbWindow.first, elapsed - first.t > 60 else { return }
        climbRatePerHour = max(0, (climbMeters - first.c) / (elapsed - first.t) * 3600)
    }

    private mutating func closeKilometer(elapsed: TimeInterval, distanceKm: Double) -> KilometerSplit? {
        guard distanceKm >= lastKmMark + 1 else { return nil }
        lastKmMark += 1
        let seconds = elapsed - kmStartElapsed
        kmStartElapsed = elapsed
        splits.append(seconds)
        let average = distanceKm > 0.05 ? elapsed / distanceKm : seconds
        return KilometerSplit(km: Int(lastKmMark), seconds: seconds,
                              deltaVsAverage: seconds - average)
    }

    // MARK: - Location

    /// Folds one altitude reading into climb, descent and the profile.
    mutating func ingestAltitude(_ altitude: Double, verticalAccuracy: Double,
                                 at elapsed: TimeInterval) {
        guard verticalAccuracy >= 0, verticalAccuracy < Self.usableVerticalAccuracy else { return }
        altitudeMeters = altitude
        if let last = lastAltitude {
            let delta = altitude - last
            if delta > Self.altitudeNoiseFloor {
                climbMeters += delta
                lastAltitude = altitude
            } else if delta < -Self.altitudeNoiseFloor {
                descentMeters += -delta
                lastAltitude = altitude
            }
        } else {
            lastAltitude = altitude
        }
        sampleAltitude(altitude, at: elapsed)
    }

    /// Folds one GPS fix into the stored track.
    mutating func ingestCoordinate(latitude: Double, longitude: Double, altitude: Double,
                                   horizontalAccuracy: Double, at elapsed: TimeInterval) {
        guard horizontalAccuracy >= 0, horizontalAccuracy < Self.usableHorizontalAccuracy else { return }
        guard elapsed - lastRouteSample >= routeInterval else { return }
        lastRouteSample = elapsed
        coordinates.append(Coordinate(lat: latitude, lon: longitude, elevation: altitude, t: elapsed))
        if coordinates.count > Self.routeCapacity {
            coordinates = Self.decimated(coordinates)
            routeInterval *= 2
        }
    }

    private mutating func sampleAltitude(_ altitude: Double, at elapsed: TimeInterval) {
        guard elapsed - lastAltitudeSample >= altitudeInterval else { return }
        lastAltitudeSample = elapsed
        altitudeProfile.append(altitude)
        if altitudeProfile.count > Self.altitudeCapacity {
            altitudeProfile = Self.decimated(altitudeProfile)
            altitudeInterval *= 2
        }
    }

    /// Halves a series by dropping every second point, keeping both ends.
    ///
    /// This is what a full buffer does instead of dropping from the front.
    /// Truncating cost the *beginning* of the run — so a marathon's elevation
    /// profile started at kilometer 12 and its GPX export had no start line.
    /// Decimating costs resolution evenly and keeps the whole run, which is
    /// the trade a profile drawn 240 px wide wants anyway.
    static func decimated<T>(_ values: [T]) -> [T] {
        guard values.count > 2 else { return values }
        var thinned = stride(from: 0, to: values.count, by: 2).map { values[$0] }
        // An even count leaves the final point out of the stride; a profile
        // that loses its summit at the finish is exactly what this avoids.
        if values.count.isMultiple(of: 2), let last = values.last {
            thinned.append(last)
        }
        return thinned
    }

    // MARK: - Simulation support (DEBUG screenshot routes)

    /// Replaces the profile with a known series so screenshots can be measured
    /// against numbers instead of a moving simulation.
    mutating func overrideAltitudeProfile(_ samples: [Double]) {
        altitudeProfile = samples
        altitudeMeters = samples.last ?? 0
    }

    mutating func setRollingPace(_ pace: TimeInterval) { rollingPace = pace }
}
