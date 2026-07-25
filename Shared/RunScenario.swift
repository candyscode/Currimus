import Foundation

#if DEBUG
/// A deterministic, reproducible description of one run, sampled once per
/// second. Both the headless `RunSimulator` (tests) and the in-app playback
/// (`RunSession.beginSimulation`) consume it, so a problem found in a test is
/// reproducible on screen and vice versa — and a "defined test set" is simply a
/// named scenario. Nothing here is random: the same scenario always produces
/// the same run.
///
/// DEBUG only, like `SampleData` — none of this reaches a shipped binary.
struct RunScenario {

    /// When the run ends.
    enum Stop {
        case afterDistance(Double)          // kilometres
        case afterDuration(TimeInterval)    // seconds

        func reached(elapsed: TimeInterval, distanceKm: Double) -> Bool {
            switch self {
            case .afterDistance(let km): return distanceKm >= km
            case .afterDuration(let s):  return elapsed >= s
            }
        }
    }

    /// A short key for launch-argument lookup (`-simulate marathon`).
    var key: String
    var name: String
    var type: RunType
    var stop: Stop

    /// The truth the runner runs: target pace (s/km) at a given elapsed second.
    /// Return `.infinity` for a standstill — no distance accrues that second.
    var paceSecPerKm: (TimeInterval) -> Double
    /// Heart rate this second; 0 = no reading (a sensor gap).
    var heartRate: (TimeInterval) -> Int
    /// GPS altitude this second (m), or nil for no usable fix.
    var altitude: (TimeInterval) -> Double?
    /// Whether a usable GPS fix arrives this second (a route point).
    var hasGPS: (TimeInterval) -> Bool

    /// Accuracy the fixes carry, so the scenario can exercise RunMetrics' gates.
    var horizontalAccuracy: Double = 5
    var verticalAccuracy: Double = 5
    /// Where synthetic coordinates start (Freiburg).
    var origin: (lat: Double, lon: Double) = (47.9959, 7.8522)
    /// A ceiling so a mis-specified scenario can never loop forever.
    var maxSeconds: Int = 12 * 3600
    /// Pauses to insert, each `(atMoving:, wallDuration:)`. When the run clock
    /// reaches `atMoving`, recording pauses for `wallDuration` of wall time: the
    /// run clock and distance stop, and — like `RunSession`, which drops fixes
    /// while paused — no GPS is taken across it, so the track shows a time gap
    /// rather than teleporting. Honoured by the headless `RunSimulator`.
    var pauses: [(atMoving: TimeInterval, wallDuration: TimeInterval)] = []
}

// MARK: - Shared shaping helpers

extension RunScenario {
    /// A smooth deterministic wobble, so pace and effort vary like a real run
    /// without any randomness.
    static func wave(_ t: TimeInterval) -> Double {
        sin(t / 285) * 6 + sin(t / 47) * 3 + sin(t / 13) * 1.5
    }

    /// Heart rate ramping from ~rest to an effort level over the first five
    /// minutes, then holding with a slow drift.
    static func effortHR(_ t: TimeInterval, peak: Double) -> Int {
        let ramp = min(1, t / 300)
        return Int(82 + (peak - 82) * ramp + sin(t / 31) * 4)
    }

    /// Gently rolling road altitude (±18 m).
    static func roadAltitude(_ t: TimeInterval) -> Double { 260 + sin(t / 400) * 18 }

    /// A synthetic moving position for a cumulative distance — a wandering loop
    /// out of the origin, so a simulated route has real extent and grows with
    /// the run. Shared by the headless simulator and the live playback.
    func coordinate(distanceKm: Double) -> (lat: Double, lon: Double) {
        let angle = distanceKm / 2
        let radius = 0.01 + distanceKm / 1000
        return (origin.lat + sin(angle) * radius, origin.lon + cos(angle) * radius * 1.4)
    }
}

// MARK: - The library (the "defined test sets")

extension RunScenario {
    /// An even-paced road marathon at ~5:00/km — the canonical long run.
    static var marathon: RunScenario {
        RunScenario(
            key: "marathon", name: "Marathon · even 5:00", type: .quick,
            stop: .afterDistance(RaceDistance.marathon.km),
            paceSecPerKm: { 300 + wave($0) + max(0, 30 - $0) * 0.6 },
            heartRate: { effortHR($0, peak: 158) },
            altitude: { roadAltitude($0) },
            hasGPS: { _ in true }
        )
    }

    /// A negative-split marathon: opens at ~5:15, closes near 4:50.
    static var marathonNegativeSplit: RunScenario {
        RunScenario(
            key: "negsplit", name: "Marathon · negative split", type: .quick,
            stop: .afterDistance(RaceDistance.marathon.km),
            paceSecPerKm: { t in (315 - 25 * min(1, t / 12000)) + wave(t) },
            heartRate: { effortHR($0, peak: 162) },
            altitude: { roadAltitude($0) },
            hasGPS: { _ in true }
        )
    }

    /// A 50 km mountain ultra: slow, ~6 h, one big climb to a high point and
    /// back down, so climb, descent and grade-adjusted pace all get real input.
    static var trailUltra: RunScenario {
        RunScenario(
            key: "ultra", name: "Trail ultra · 50 km", type: .trail,
            stop: .afterDistance(50),
            paceSecPerKm: { 430 + wave($0) * 2 + sin($0 / 1200) * 70 },
            heartRate: { effortHR($0, peak: 156) },
            // Rises ~1400 m to a summit near halfway, then descends, with ridge
            // detail on top — a profile the climb/descent maths must survive.
            altitude: { 300 + 700 * (1 - cos($0 / 3400)) + sin($0 / 240) * 22 },
            hasGPS: { _ in true }
        )
    }

    /// A pacer run holding target — for the live playback and the pacer summary.
    static var pacerOnTarget: RunScenario {
        RunScenario(
            key: "pacer", name: "Pacer · on target", type: .pacer,
            stop: .afterDistance(10),
            paceSecPerKm: { 300 + wave($0) },
            heartRate: { effortHR($0, peak: 155) },
            altitude: { roadAltitude($0) },
            hasGPS: { _ in true }
        )
    }

    /// Treadmill: distance accrues from pace, but no GPS at all — so no route
    /// and no elevation should be recorded.
    static var treadmill: RunScenario {
        RunScenario(
            key: "treadmill", name: "Treadmill · no GPS", type: .quick,
            stop: .afterDistance(10),
            paceSecPerKm: { 330 + wave($0) },
            heartRate: { effortHR($0, peak: 150) },
            altitude: { _ in nil },
            hasGPS: { _ in false }
        )
    }

    /// GPS drops out between roughly km 3 and km 5 (a tunnel or dense forest):
    /// the route should keep both ends and show the gap, not lose the run.
    static var gpsDropout: RunScenario {
        let out = 900.0 ... 1500.0    // ~km 3–5 at 5:00/km
        return RunScenario(
            key: "dropout", name: "Road · GPS dropout km 3–5", type: .quick,
            stop: .afterDistance(8),
            paceSecPerKm: { 300 + wave($0) },
            heartRate: { effortHR($0, peak: 155) },
            altitude: { out.contains($0) ? nil : roadAltitude($0) },
            hasGPS: { !out.contains($0) }
        )
    }

    /// The heart-rate strap drops for two minutes mid-run: those seconds must
    /// add no zone time and not skew the average.
    static var heartRateGap: RunScenario {
        let gap = 600.0 ... 720.0
        return RunScenario(
            key: "hrgap", name: "Road · HR sensor gap", type: .quick,
            stop: .afterDistance(6),
            paceSecPerKm: { 300 + wave($0) },
            heartRate: { gap.contains($0) ? 0 : effortHR($0, peak: 155) },
            altitude: { roadAltitude($0) },
            hasGPS: { _ in true }
        )
    }

    /// A real standstill at a crossing (10:00–12:00): the rolling pace must go
    /// honest-blank rather than keep reading as if still moving.
    static var stopAndGo: RunScenario {
        let stopped = 600.0 ... 720.0
        return RunScenario(
            key: "stopgo", name: "Road · stop at a crossing", type: .quick,
            stop: .afterDuration(1500),
            paceSecPerKm: { stopped.contains($0) ? .infinity : 300 + wave($0) },
            heartRate: { effortHR($0, peak: 150) },
            altitude: { roadAltitude($0) },
            hasGPS: { !stopped.contains($0) }
        )
    }

    /// A walk-run session: four minutes running, one walking, repeated. The
    /// pace steps between a run and a walk, so splits and rolling pace must
    /// survive big swings rather than one steady effort.
    static var walkRun: RunScenario {
        RunScenario(
            key: "walkrun", name: "Walk-run intervals", type: .quick,
            stop: .afterDistance(8),
            paceSecPerKm: { t in
                t.truncatingRemainder(dividingBy: 300) < 240   // 4 min run, 1 min walk
                    ? 330 + wave(t) : 690 + sin(t / 20) * 20
            },
            heartRate: { t in
                t.truncatingRemainder(dividingBy: 300) < 240
                    ? effortHR(t, peak: 156) : effortHR(t, peak: 120)
            },
            altitude: { roadAltitude($0) },
            hasGPS: { _ in true }
        )
    }

    /// A long run paused for five minutes at the half-hour mark (a café stop):
    /// the run clock and distance must ignore the pause, and the GPS track must
    /// carry the gap across it rather than teleporting through it.
    static var pausedLongRun: RunScenario {
        RunScenario(
            key: "paused", name: "Long run · 5-min pause", type: .quick,
            stop: .afterDistance(15),
            paceSecPerKm: { 315 + wave($0) },
            heartRate: { effortHR($0, peak: 150) },
            altitude: { roadAltitude($0) },
            hasGPS: { _ in true },
            pauses: [(atMoving: 1800, wallDuration: 300)]
        )
    }

    /// A battery-saver run: GPS fixes arrive sparsely (about one every fifteen
    /// seconds) and a little coarser, but still inside the usable gate. Distance
    /// and pace come from the workout builder, so they must stay whole while the
    /// route is merely thinner.
    static var batterySaver: RunScenario {
        RunScenario(
            key: "saver", name: "Battery-saver GPS", type: .quick,
            stop: .afterDistance(10),
            paceSecPerKm: { 330 + wave($0) },
            heartRate: { effortHR($0, peak: 150) },
            altitude: { roadAltitude($0) },
            hasGPS: { $0.truncatingRemainder(dividingBy: 15) < 1 },
            horizontalAccuracy: 35, verticalAccuracy: 10
        )
    }

    /// Every scenario, for the launch-argument lookup and any sweep.
    static var all: [RunScenario] {
        [.marathon, .marathonNegativeSplit, .trailUltra, .pacerOnTarget,
         .treadmill, .gpsDropout, .heartRateGap, .stopAndGo,
         .walkRun, .pausedLongRun, .batterySaver]
    }

    static func named(_ key: String) -> RunScenario? {
        all.first { $0.key == key }
    }
}
#endif
