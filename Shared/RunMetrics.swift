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

    /// How far the altitude has to turn around before the leg it was on counts
    /// as finished — the hysteresis band, in metres.
    ///
    /// This is the number that decides how close the climb comes to Apple
    /// Fitness's, and it only works together with `altitudeTimeConstant` and a
    /// barometric source. See `ingestAltitude` for why a *band* rather than a
    /// per-sample floor. Three metres is deliberately on the conservative side:
    /// the failure this replaces was a 20–25 % over-count, and undulations
    /// smaller than a house are not what a runner means by "climbed".
    static let climbHysteresis = 3.0
    /// Time constant (s) of the low-pass on the altitude series. Sensor noise
    /// lives well below it; a runner's actual climb rate is far slower than it,
    /// so terrain passes through and jitter does not. It costs a lag of about
    /// `constant × climb rate` — under two metres at a hard 0.3 m/s. That lag is
    /// paid twice per reversal (a summit reads a little low and a trough a
    /// little high), which is why it is six seconds and not the twelve that
    /// would filter better: on rolling terrain the difference is a five per
    /// cent under-count against a ten.
    static let altitudeTimeConstant = 6.0
    /// Vertical accuracy worse than this (or negative = invalid) is discarded.
    static let usableVerticalAccuracy = 12.0
    /// The default horizontal gate — what `GPSAccuracy.high` asks for. A run
    /// set to a coarser mode raises it through `horizontalAccuracyLimit`, or
    /// the fixes it deliberately asked for would all be thrown away.
    static let usableHorizontalAccuracy = 50.0
    /// The window the live climb rate is read over. One minute, not ten: on a
    /// trail the number is there to answer "how hard is *this* climb", and a
    /// ten-minute mean still carried the descent before it (Andi, CUR-40).
    static let climbRateWindow: TimeInterval = 60
    /// How much of that window has to have gone by before the rate is worth
    /// showing. Below this the divisor is small enough that one noisy metre
    /// becomes a four-figure m/h.
    static let climbRateMinimumSpan: TimeInterval = 30

    // MARK: - Output

    private(set) var splits: [TimeInterval] = []
    private(set) var rollingPace: TimeInterval = 0
    /// Metres climbed, including the leg currently under way.
    ///
    /// A leg is only *committed* when the altitude turns around, but a runner
    /// halfway up a pass must not watch the number sit still — so what is shown
    /// is the committed total plus the rise of the leg in progress. The two
    /// agree at the moment of the turn, so the number never jumps backwards.
    var climbMeters: Double { committedClimb + (leg?.isClimb == true ? legRise : 0) }
    var descentMeters: Double { committedDescent + (leg?.isClimb == false ? legRise : 0) }
    private(set) var climbRatePerHour: Double = 0
    private(set) var altitudeMeters: Double = 0
    private(set) var altitudeProfile: [Double] = []
    private(set) var coordinates: [Coordinate] = []
    private(set) var zoneSeconds: [TimeInterval] = [0, 0, 0, 0, 0]
    /// Distance covered while in each zone. The tick already knows both the
    /// zone and the distance; keeping only the seconds threw away the half
    /// that makes "pace in zone 2" a measurement rather than an estimate.
    private(set) var zoneDistanceKm: [Double] = [0, 0, 0, 0, 0]

    /// How vague a fix may be and still join the track. Set from the run's GPS
    /// setting; see `GPSAccuracy.usableHorizontalAccuracy`.
    var horizontalAccuracyLimit = RunMetrics.usableHorizontalAccuracy

    /// Mean of every heart-rate reading seen, not just the last one.
    var averageHR: Int { hrSampleCount > 0 ? hrSampleSum / hrSampleCount : 0 }

    // MARK: - Internals

    private var lastKmMark: Double = 0
    /// Where the last recorded second left off, so a tick knows how far this
    /// one came.
    private var lastTickDistanceKm: Double = 0
    private var kmStartElapsed: TimeInterval = 0
    private var hrSampleSum = 0
    private var hrSampleCount = 0
    /// (elapsed, distance) ring backing the rolling-pace window.
    private var paceWindow: [(t: TimeInterval, d: Double)] = []
    /// (elapsed, climb) ring backing the climb rate.
    private var climbWindow: [(t: TimeInterval, c: Double)] = []
    /// Committed climb and descent — everything from legs that have already
    /// turned around. What the screens read adds the leg in progress; see
    /// `climbMeters`.
    private var committedClimb: Double = 0
    private var committedDescent: Double = 0
    /// The low-passed altitude every elevation decision is made on, and when it
    /// was last advanced (so the filter can be time-aware rather than assume a
    /// sample rate it does not control).
    private var smoothedAltitude: Double?
    private var lastAltitudeAt: TimeInterval?
    /// The monotone stretch of altitude currently under way: where it started,
    /// how far it has got, and which way it is going. nil until the altitude
    /// has moved out of the hysteresis band for the first time.
    private var leg: (start: Double, extreme: Double, isClimb: Bool)?
    /// The band a first leg would start from while no direction is established.
    private var legPivot: (low: Double, high: Double)?
    private var legRise: Double { leg.map { abs($0.extreme - $0.start) } ?? 0 }
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
            && lhs.zoneDistanceKm == rhs.zoneDistanceKm
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
            if (1...5).contains(zone) {
                zoneSeconds[zone - 1] += 1
                // Whatever ground was covered since the last tick belongs to
                // the zone the runner was in for it.
                zoneDistanceKm[zone - 1] += max(distanceKm - lastTickDistanceKm, 0)
            }
        }
        lastTickDistanceKm = distanceKm
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
        while let first = climbWindow.first, elapsed - first.t > Self.climbRateWindow {
            climbWindow.removeFirst()
        }
        guard let first = climbWindow.first,
              elapsed - first.t >= Self.climbRateMinimumSpan else { return }
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
    ///
    /// Two things happen here, and both exist because the old rule — "any step
    /// bigger than 1.5 m is climb" — over-counted a thousand-metre day by two
    /// to three hundred metres against Apple Fitness (CUR-40).
    ///
    /// **The low-pass.** Sensor noise that survives a per-sample threshold is
    /// counted by it, once per wobble, for the whole run. A first-order filter
    /// with a six-second constant removes it and leaves terrain untouched: no
    /// runner gains height at a rate that lives that high up the spectrum.
    ///
    /// **The hysteresis band, applied to legs and not to steps.** A rise only
    /// stops being a rise once the altitude has fallen `climbHysteresis` back
    /// off its highest point; until then the same leg is still going. So a
    /// three-metre bump repeated forty times adds three metres, not a hundred
    /// and twenty — which is exactly the arithmetic the old rule was doing.
    mutating func ingestAltitude(_ altitude: Double, verticalAccuracy: Double,
                                 at elapsed: TimeInterval) {
        guard verticalAccuracy >= 0, verticalAccuracy < Self.usableVerticalAccuracy else { return }
        altitudeMeters = altitude

        // Time-aware, because the caller's sample rate is not ours to assume:
        // a real run feeds this at 1 Hz, a reconstruction every ten seconds.
        let smoothed: Double
        if let previous = smoothedAltitude, let last = lastAltitudeAt, elapsed > last {
            let alpha = 1 - exp(-(elapsed - last) / Self.altitudeTimeConstant)
            smoothed = previous + alpha * (altitude - previous)
        } else {
            smoothed = smoothedAltitude ?? altitude
        }
        smoothedAltitude = smoothed
        lastAltitudeAt = elapsed
        accumulate(smoothed)
        sampleAltitude(altitude, at: elapsed)
    }

    /// Forgets where the altitude currently is, keeping what has been climbed.
    ///
    /// For the one moment a run changes altitude source: the next reading is
    /// then the start of a fresh series rather than a step of tens of metres
    /// away from the last one, which the leg tracker would otherwise bank as
    /// climb.
    ///
    /// The leg under way is banked rather than dropped. It was measured on one
    /// consistent series, so it is real ground — only the *gap* to the next
    /// series is not, and that is what forgetting the position removes.
    mutating func resetAltitudeTracking() {
        if let leg {
            if leg.isClimb {
                committedClimb += leg.extreme - leg.start
            } else {
                committedDescent += leg.start - leg.extreme
            }
        }
        smoothedAltitude = nil
        lastAltitudeAt = nil
        leg = nil
        legPivot = nil
    }

    /// Walks one filtered altitude through the leg state machine above.
    private mutating func accumulate(_ altitude: Double) {
        guard var current = leg else {
            // No direction yet — the opening seconds of a run. Hold the lowest
            // and highest altitude seen so far and start the first leg from
            // whichever of them it actually leaves, so an ascent that begins
            // after a few metres of drop is measured from the trough.
            let low = min(legPivot?.low ?? altitude, altitude)
            let high = max(legPivot?.high ?? altitude, altitude)
            if altitude > low + Self.climbHysteresis {
                leg = (start: low, extreme: altitude, isClimb: true)
            } else if altitude < high - Self.climbHysteresis {
                leg = (start: high, extreme: altitude, isClimb: false)
            } else {
                legPivot = (low: low, high: high)
            }
            return
        }

        if current.isClimb ? altitude > current.extreme : altitude < current.extreme {
            current.extreme = altitude
            leg = current
            return
        }
        // Turned around far enough to close the leg: bank it whole, and start
        // the next one from the summit (or the trough) it turned at.
        guard abs(altitude - current.extreme) > Self.climbHysteresis else { return }
        if current.isClimb {
            committedClimb += current.extreme - current.start
        } else {
            committedDescent += current.start - current.extreme
        }
        leg = (start: current.extreme, extreme: altitude, isClimb: !current.isClimb)
    }

    /// Folds one GPS fix into the stored track.
    mutating func ingestCoordinate(latitude: Double, longitude: Double, altitude: Double,
                                   horizontalAccuracy: Double, at elapsed: TimeInterval) {
        guard horizontalAccuracy >= 0, horizontalAccuracy < horizontalAccuracyLimit else { return }
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
