import Foundation

#if DEBUG
/// Runs a `RunScenario` through the real `RunMetrics` pipeline exactly the way
/// `RunSession` drives a live recording — pace → distance → tick → splits, plus
/// altitude and GPS ingestion — but headless and instant. A four-hour marathon
/// or a six-hour ultra is simulated in milliseconds, which is what makes "is
/// every kilometre recorded, does anything drop on a long run" a question a
/// unit test can answer instead of a device session nobody watches to the end.
///
/// It deliberately reuses `RunMetrics` (the same type the watch runs) and
/// builds the same `Run` value `RunSession.end()` does, so a bug in the
/// recording arithmetic or the finished-run construction shows up here too.
struct RunSimulator {
    var scenario: RunScenario
    var zones = HRZones()

    struct Result {
        var run: Run
        var metrics: RunMetrics
        var elapsed: TimeInterval
        var distanceKm: Double
        /// The per-kilometre splits as they were reported, in order.
        var reportedSplits: [RunMetrics.KilometerSplit]
        var ticks: Int
        /// Wall-clock seconds the simulation itself took — a proxy for per-tick
        /// cost, so a quadratic blow-up on long runs is measurable.
        var simSeconds: Double
    }

    func run() -> Result {
        var metrics = RunMetrics()
        var distanceKm = 0.0
        // Two clocks, exactly as a real run keeps: `moving` is the run clock
        // (splits, pace, duration) and stops during a pause; `pausedTotal` is
        // the wall time spent paused, so GPS/altitude are stamped at
        // `moving + pausedTotal` and the track carries the pause as a gap.
        var moving = 0.0
        var pausedTotal = 0.0
        var ticks = 0
        var pending = scenario.pauses.sorted { $0.atMoving < $1.atMoving }
        var reported: [RunMetrics.KilometerSplit] = []

        let started = Date()
        while !scenario.stop.reached(elapsed: moving, distanceKm: distanceKm),
              ticks < scenario.maxSeconds {
            // A due pause: wall jumps, the run clock and distance do not, and
            // nothing is ingested across the gap (RunSession drops fixes while
            // paused).
            if let next = pending.first, moving >= next.atMoving {
                pending.removeFirst()
                pausedTotal += next.wallDuration
                continue
            }
            ticks += 1
            moving += 1
            let wall = moving + pausedTotal

            // Distance accrues from pace, exactly as RunSession's simulated
            // second does. A standstill (pace == .infinity) adds nothing.
            let pace = scenario.paceSecPerKm(moving)
            if pace.isFinite, pace > 0 { distanceKm += 1 / pace }

            let heartRate = scenario.heartRate(moving)
            let zone = heartRate > 0 ? zones.zone(for: heartRate) : 0

            if let altitude = scenario.altitude(moving) {
                metrics.ingestAltitude(altitude, verticalAccuracy: scenario.verticalAccuracy,
                                       at: wall)
            }
            if scenario.hasGPS(moving) {
                let c = scenario.coordinate(distanceKm: distanceKm)
                metrics.ingestCoordinate(latitude: c.lat, longitude: c.lon,
                                         altitude: scenario.altitude(moving) ?? 0,
                                         horizontalAccuracy: scenario.horizontalAccuracy,
                                         at: wall)
            }
            if let split = metrics.tick(elapsed: moving, distanceKm: distanceKm,
                                        heartRate: heartRate, zone: zone) {
                reported.append(split)
            }
        }
        let simSeconds = Date().timeIntervalSince(started)
        let elapsed = moving

        // The same construction as RunSession.end(), so the finished run is
        // shaped exactly like a real one.
        let run = Run(
            date: .now,
            type: scenario.type,
            name: scenario.name,
            distanceKm: (distanceKm * 100).rounded() / 100,
            duration: elapsed,
            avgHR: metrics.averageHR,
            splits: metrics.splits,
            zoneSeconds: metrics.zoneSeconds,
            climbMeters: metrics.climbMeters.rounded(),
            descentMeters: metrics.descentMeters.rounded(),
            highPointMeters: metrics.altitudeProfile.max().map { $0.rounded() },
            altitudeSamples: metrics.altitudeProfile.isEmpty ? nil : metrics.altitudeProfile,
            route: metrics.coordinates.isEmpty ? nil : metrics.coordinates
        )
        return Result(run: run, metrics: metrics, elapsed: elapsed, distanceKm: distanceKm,
                      reportedSplits: reported, ticks: ticks, simSeconds: simSeconds)
    }
}
#endif
