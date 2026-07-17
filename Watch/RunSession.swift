import Foundation
import Combine
import SwiftUI
#if os(watchOS)
import WatchKit
#endif

/// Drives one run on the watch. In this build the sensor feed is simulated
/// (pace / HR / climb follow a plausible curve); swap `tick()` for
/// HKWorkoutSession + CLLocationManager updates to go live.
@MainActor
final class RunSession: ObservableObject {
    enum Phase: Equatable {
        case idle
        case pacerSetup
        case countdown(Int)
        case running
        case paused
        case finished
    }

    struct KilometerAlert: Equatable {
        var km: Int
        var splitSeconds: TimeInterval
        var deltaVsAvg: TimeInterval
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var type: RunType = .quick
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var distanceKm: Double = 0
    @Published private(set) var heartRate: Int = 78
    @Published private(set) var rollingPace: TimeInterval = 0
    @Published private(set) var splits: [TimeInterval] = []
    @Published private(set) var zoneSeconds: [TimeInterval] = [0, 0, 0, 0, 0]
    @Published private(set) var climbMeters: Double = 0
    @Published private(set) var descentMeters: Double = 0
    @Published private(set) var climbRatePerHour: Double = 0
    @Published var kilometerAlert: KilometerAlert?
    @Published var pacerTarget: TimeInterval = 315

    var zones = HRZones()
    var kilometerAlertEnabled = true
    private var timer: AnyCancellable?
    private var lastKmMark: Double = 0
    private var kmStartElapsed: TimeInterval = 0
    private var alertDismiss: Task<Void, Never>?

    var currentZone: Int { zones.zone(for: heartRate) }

    var averagePace: TimeInterval { distanceKm > 0.05 ? elapsed / distanceKm : 0 }

    /// Pacer: + means slower than target.
    var paceDelta: TimeInterval { rollingPace - pacerTarget }

    /// Pacer: overall time ahead (−) / behind (+) of target schedule.
    var scheduleDelta: TimeInterval { elapsed - distanceKm * pacerTarget }

    var projectedTenK: TimeInterval { pacerTarget * 10 }

    // MARK: - Lifecycle

    func setupPacer() {
        type = .pacer
        phase = .pacerSetup
    }

    func begin(_ type: RunType) {
        self.type = type
        elapsed = 0; distanceKm = 0; splits = []; zoneSeconds = [0, 0, 0, 0, 0]
        climbMeters = 0; descentMeters = 0; climbRatePerHour = 0
        heartRate = 82; rollingPace = basePace; lastKmMark = 0; kmStartElapsed = 0
        kilometerAlert = nil
        phase = .countdown(3)
        haptic(.start)
        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func pause() {
        guard phase == .running else { return }
        phase = .paused
        haptic(.stop)
    }

    func resume() {
        guard phase == .paused else { return }
        phase = .running
        haptic(.start)
    }

    /// Ends the run and returns it for the log.
    func end() -> Run {
        timer?.cancel()
        phase = .finished
        haptic(.success)
        return Run(
            date: .now.addingTimeInterval(-elapsed),
            type: type,
            name: type == .trail ? "Trail run" : (type == .pacer ? "Pacer \(Format.pace(pacerTarget))" : "Run"),
            distanceKm: (distanceKm * 100).rounded() / 100,
            duration: elapsed,
            avgHR: 148,
            splits: splits,
            zoneSeconds: zoneSeconds,
            climbMeters: type == .trail ? climbMeters.rounded() : nil,
            descentMeters: type == .trail ? descentMeters.rounded() : nil,
            highPointMeters: type == .trail ? 1622 : nil
        )
    }

    func reset() {
        timer?.cancel()
        phase = .idle
    }

    // MARK: - Simulation

    private var basePace: TimeInterval {
        switch type {
        case .quick: return 324      // 5:24
        case .pacer: return pacerTarget
        case .trail: return 453      // 7:33
        }
    }

    private func tick() {
        switch phase {
        case .countdown(let n):
            if n > 1 {
                phase = .countdown(n - 1)
                haptic(.click)
            } else {
                phase = .running
                haptic(.start)
            }
        case .running:
            advanceOneSecond()
        case .paused:
            heartRate = max(heartRate - 1, 96)
        default:
            break
        }
    }

    private func advanceOneSecond() {
        elapsed += 1

        // Pace drifts around the base: a per-km-scale drift so splits differ,
        // a shorter wave, and jitter.
        let wave = sin(elapsed / 285) * 11 + sin(elapsed / 47) * 6 + sin(elapsed / 13) * 3
        let warmup = max(0, 30 - elapsed) * 0.6 // start slower
        rollingPace = basePace + wave + warmup + Double.random(in: -2...2)
        distanceKm += 1000 / rollingPace / 1000

        // HR climbs to a zone that fits the effort, with noise.
        let effortHR: Double = {
            switch type {
            case .trail: return 158
            case .pacer: return 155
            case .quick: return 152
            }
        }()
        let ramp = min(1, elapsed / 300)
        heartRate = Int(82 + (effortHR - 82) * ramp + sin(elapsed / 31) * 5 + Double.random(in: -1...1))
        zoneSeconds[currentZone - 1] += 1

        if type == .trail {
            let climbing = sin(elapsed / 120) > -0.35 // mostly up
            if climbing {
                let rate = 420 + sin(elapsed / 60) * 140 // m/h
                climbMeters += rate / 3600
                climbRatePerHour = max(0, rate + Double.random(in: -25...25))
            } else {
                descentMeters += 700 / 3600
                climbRatePerHour = max(0, climbRatePerHour - 40)
            }
        }

        // Kilometer boundary → alert (auto-dismisses after 5 s).
        if distanceKm >= lastKmMark + 1 {
            lastKmMark += 1
            let split = elapsed - kmStartElapsed
            kmStartElapsed = elapsed
            splits.append(split)
            if kilometerAlertEnabled {
                kilometerAlert = KilometerAlert(
                    km: Int(lastKmMark),
                    splitSeconds: split,
                    deltaVsAvg: split - averagePace
                )
                haptic(.notification)
                alertDismiss?.cancel()
                alertDismiss = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(5))
                    if !Task.isCancelled { self?.kilometerAlert = nil }
                }
            }
        }
    }

    #if DEBUG
    /// Screenshot / demo helper: jump straight into a run N seconds in.
    func debugFastForward(_ type: RunType, seconds: Int, paused: Bool = false, keepAlert: Bool = false) {
        begin(type)
        phase = .running
        for _ in 0..<seconds { advanceOneSecond() }
        alertDismiss?.cancel()
        if !keepAlert { kilometerAlert = nil }
        if paused { phase = .paused }
    }
    #endif

    private enum HapticKind { case start, stop, success, click, notification }

    private func haptic(_ kind: HapticKind) {
        #if os(watchOS)
        let map: [HapticKind: WKHapticType] = [
            .start: .start, .stop: .stop, .success: .success,
            .click: .click, .notification: .notification,
        ]
        WKInterfaceDevice.current().play(map[kind] ?? .click)
        #endif
    }
}
