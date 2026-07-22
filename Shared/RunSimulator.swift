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
        var elapsed = 0.0
        var second = 0
        var reported: [RunMetrics.KilometerSplit] = []

        let started = Date()
        while !scenario.stop.reached(elapsed: elapsed, distanceKm: distanceKm),
              second < scenario.maxSeconds {
            second += 1
            elapsed = Double(second)

            // Distance accrues from pace, exactly as RunSession's simulated
            // second does. A standstill (pace == .infinity) adds nothing.
            let pace = scenario.paceSecPerKm(elapsed)
            if pace.isFinite, pace > 0 { distanceKm += 1 / pace }

            let heartRate = scenario.heartRate(elapsed)
            let zone = heartRate > 0 ? zones.zone(for: heartRate) : 0

            if let altitude = scenario.altitude(elapsed) {
                metrics.ingestAltitude(altitude, verticalAccuracy: scenario.verticalAccuracy,
                                       at: elapsed)
            }
            if scenario.hasGPS(elapsed) {
                let c = scenario.coordinate(distanceKm: distanceKm)
                metrics.ingestCoordinate(latitude: c.lat, longitude: c.lon,
                                         altitude: scenario.altitude(elapsed) ?? 0,
                                         horizontalAccuracy: scenario.horizontalAccuracy,
                                         at: elapsed)
            }
            if let split = metrics.tick(elapsed: elapsed, distanceKm: distanceKm,
                                        heartRate: heartRate, zone: zone) {
                reported.append(split)
            }
        }
        let simSeconds = Date().timeIntervalSince(started)

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
                      reportedSplits: reported, ticks: second, simSeconds: simSeconds)
    }
}
#endif
