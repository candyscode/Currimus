import Foundation
import Combine
import SwiftUI
import HealthKit
import CoreLocation
#if os(watchOS)
import WatchKit
#endif

/// Drives one run on the watch — a real workout recording:
/// HKWorkoutSession + HKLiveWorkoutBuilder deliver heart rate, distance and
/// energy; CoreLocation supplies GPS (route + altitude for trail climb).
/// The finished workout is saved to HealthKit and the run is synced to the
/// iPhone via WatchConnectivity.
@MainActor
final class RunSession: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        case pacerPace          // step 1 · target pace (required)
        case pacerDistance      // step 2 · distance (optional, Off = just run)
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

    // MARK: - Published state

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var type: RunType = .quick
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var distanceKm: Double = 0
    @Published private(set) var heartRate: Int = 0
    @Published private(set) var rollingPace: TimeInterval = 0
    @Published private(set) var splits: [TimeInterval] = []
    @Published private(set) var zoneSeconds: [TimeInterval] = [0, 0, 0, 0, 0]
    @Published private(set) var climbMeters: Double = 0
    @Published private(set) var descentMeters: Double = 0
    @Published private(set) var climbRatePerHour: Double = 0
    @Published private(set) var altitudeMeters: Double = 0
    /// Altitude samples of the run so far, for the no-route elevation profile.
    @Published private(set) var altitudeProfile: [Double] = []
    @Published var kilometerAlert: KilometerAlert?
    @Published var pacerTarget: TimeInterval = 315
    /// nil = "Off" — pacer runs open-ended, no finish forecast.
    @Published var pacerDistanceKm: Double?
    /// Planned route elevation profile (normalized points), e.g. a GPX loaded
    /// from the iPhone. nil → the elevation page shows the profile so far.
    @Published var plannedRoute: RoutePlan?

    struct RoutePlan: Equatable {
        var profile: [CGPoint]   // x 0…1 along route, y 0…1 normalized altitude
        var distanceKm: Double
        var climbMeters: Double
    }

    var zones = HRZones()
    var kilometerAlertEnabled = true

    // MARK: - Internals

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private let locationManager = CLLocationManager()

    private var timer: AnyCancellable?
    private var lastKmMark: Double = 0
    private var kmStartElapsed: TimeInterval = 0
    private var alertDismiss: Task<Void, Never>?
    private var hrSampleSum = 0
    private var hrSampleCount = 0
    /// (elapsed, distanceKm) ring for the rolling pace window.
    private var paceWindow: [(t: TimeInterval, d: Double)] = []
    /// (elapsed, climbMeters) ring for the 10-minute climb rate.
    private var climbWindow: [(t: TimeInterval, c: Double)] = []
    private var lastAltitude: Double?
    private var lastProfileSample: TimeInterval = 0
    private var coordinates: [Coordinate] = []
    private var isSimulated = false
    /// When false, `begin` skips the 3-2-1 countdown (iPhone setting).
    var countdownEnabled = true

    // MARK: - Derived

    /// 0 = no heart-rate reading yet — the zone bar stays unlit.
    var currentZone: Int { heartRate > 0 ? zones.zone(for: heartRate) : 0 }
    var averagePace: TimeInterval { distanceKm > 0.05 ? elapsed / distanceKm : 0 }
    var averageHR: Int { hrSampleCount > 0 ? hrSampleSum / hrSampleCount : heartRate }
    /// Pacer: + means slower than target.
    var paceDelta: TimeInterval { rollingPace > 0 ? rollingPace - pacerTarget : 0 }
    /// Pacer: overall time ahead (−) / behind (+) of target schedule.
    var scheduleDelta: TimeInterval { elapsed - distanceKm * pacerTarget }
    /// Forecast for the configured distance — only meaningful with a distance.
    var finishForecast: TimeInterval? {
        guard let target = pacerDistanceKm else { return nil }
        return target * pacerTarget + scheduleDelta
    }

    // MARK: - Flow

    func setupPacer() {
        type = .pacer
        phase = .pacerPace
    }

    func confirmPacerPace() {
        phase = .pacerDistance
    }

    func begin(_ type: RunType) {
        self.type = type
        resetMetrics()
        phase = countdownEnabled ? .countdown(3) : .running
        haptic(.start)
        startTimer()

        guard !isSimulated else { return }
        requestAuthorizationThenPrepare()
    }

    /// Tap-to-skip: jump straight from the countdown into the run.
    func skipCountdown() {
        guard case .countdown = phase else { return }
        phase = .running
        haptic(.start)
    }

    func pause() {
        guard phase == .running else { return }
        phase = .paused
        workoutSession?.pause()
        haptic(.stop)
    }

    func resume() {
        guard phase == .paused else { return }
        phase = .running
        workoutSession?.resume()
        haptic(.start)
    }

    /// Ends the run, saves the workout to HealthKit, and returns it for the log.
    func end() -> Run {
        timer?.cancel()
        phase = .finished
        haptic(.success)

        // Elevation is recorded for every run (the iPhone shows road climb and
        // uses it for grade-adjusted pace); the GPS track powers the map + GPX.
        let run = Run(
            date: .now.addingTimeInterval(-elapsed),
            type: type,
            name: defaultName,
            distanceKm: (distanceKm * 100).rounded() / 100,
            duration: elapsed,
            avgHR: averageHR,
            splits: splits,
            zoneSeconds: zoneSeconds,
            climbMeters: climbMeters.rounded(),
            descentMeters: descentMeters.rounded(),
            highPointMeters: altitudeProfile.max().map { $0.rounded() },
            altitudeSamples: altitudeProfile.isEmpty ? nil : altitudeProfile,
            route: coordinates.isEmpty ? nil : coordinates
        )

        finishWorkout()
        RunSync.shared.send(run)
        return run
    }

    func reset() {
        timer?.cancel()
        phase = .idle
    }

    private var defaultName: String {
        switch type {
        case .trail: return "Trail run"
        case .pacer: return "Pacer \(Format.pace(pacerTarget))"
        case .quick:
            let hour = Calendar.current.component(.hour, from: .now)
            return hour < 11 ? "Morning Run" : (hour < 17 ? "Run" : "Evening Run")
        }
    }

    private func resetMetrics() {
        elapsed = 0; distanceKm = 0; splits = []; zoneSeconds = [0, 0, 0, 0, 0]
        climbMeters = 0; descentMeters = 0; climbRatePerHour = 0
        heartRate = 0; rollingPace = 0; lastKmMark = 0; kmStartElapsed = 0
        kilometerAlert = nil; hrSampleSum = 0; hrSampleCount = 0
        paceWindow = []; climbWindow = []; lastAltitude = nil
        altitudeProfile = []; lastProfileSample = 0; coordinates = []
        if type != .pacer { pacerDistanceKm = nil }
    }

    private func startTimer() {
        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    // MARK: - HealthKit

    private func requestAuthorizationThenPrepare() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
        ]
        let read: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.activeEnergyBurned),
        ]
        healthStore.requestAuthorization(toShare: share, read: read) { [weak self] granted, _ in
            Task { @MainActor in
                guard granted else { return }
                self?.startWorkoutSession()
            }
        }
    }

    private func startWorkoutSession() {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            workoutSession = session
            workoutBuilder = builder
            routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)

            session.startActivity(with: .now)
            builder.beginCollection(withStart: .now) { _, _ in }
        } catch {
            workoutSession = nil
            workoutBuilder = nil
        }

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    private func finishWorkout() {
        locationManager.stopUpdatingLocation()
        guard let session = workoutSession, let builder = workoutBuilder else { return }
        session.end()
        builder.endCollection(withEnd: .now) { [routeBuilder] _, _ in
            builder.finishWorkout { workout, _ in
                if let workout {
                    routeBuilder?.finishRoute(with: workout, metadata: nil) { _, _ in }
                }
            }
        }
        workoutSession = nil
        workoutBuilder = nil
    }

    // MARK: - Per-second tick

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
            if isSimulated {
                simulateOneSecond()
            } else {
                advanceRealSecond()
            }
        default:
            break
        }
    }

    private func advanceRealSecond() {
        if let builderElapsed = workoutBuilder?.elapsedTime, builderElapsed > 0 {
            elapsed = builderElapsed
        } else {
            elapsed += 1
        }

        if heartRate > 0 {
            hrSampleSum += heartRate
            hrSampleCount += 1
            zoneSeconds[currentZone - 1] += 1
        }

        updateRollingPace()
        updateClimbRate()
        checkKilometerBoundary()
    }

    private func updateRollingPace() {
        paceWindow.append((elapsed, distanceKm))
        // Rolling last kilometer, falling back to the last 90 s early on.
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
            rollingPace = 0 // standing still — no honest pace to show
        }
    }

    private func updateClimbRate() {
        climbWindow.append((elapsed, climbMeters))
        while let first = climbWindow.first, elapsed - first.t > 600 {
            climbWindow.removeFirst()
        }
        guard let first = climbWindow.first, elapsed - first.t > 60 else { return }
        let climbed = climbMeters - first.c
        climbRatePerHour = max(0, climbed / (elapsed - first.t) * 3600)
    }

    private func checkKilometerBoundary() {
        guard distanceKm >= lastKmMark + 1 else { return }
        lastKmMark += 1
        let split = elapsed - kmStartElapsed
        kmStartElapsed = elapsed
        splits.append(split)
        guard kilometerAlertEnabled else { return }
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

    // MARK: - Location → distance backstop, route, altitude

    fileprivate func integrate(_ location: CLLocation) {
        guard phase == .running else { return }

        if location.verticalAccuracy >= 0, location.verticalAccuracy < 12 {
            altitudeMeters = location.altitude
            if let last = lastAltitude {
                let delta = location.altitude - last
                // Ignore GPS jitter below 1.5 m.
                if delta > 1.5 {
                    climbMeters += delta
                    lastAltitude = location.altitude
                } else if delta < -1.5 {
                    descentMeters += -delta
                    lastAltitude = location.altitude
                }
            } else {
                lastAltitude = location.altitude
            }
            if elapsed - lastProfileSample >= 10 {
                lastProfileSample = elapsed
                altitudeProfile.append(location.altitude)
                if altitudeProfile.count > 240 { altitudeProfile.removeFirst() }
            }
        }

        if location.horizontalAccuracy >= 0, location.horizontalAccuracy < 50 {
            routeBuilder?.insertRouteData([location]) { _, _ in }
            // Keep a downsampled local copy for the map + GPX export (~every 5 s).
            if coordinates.isEmpty || elapsed - (coordinates.last?.t ?? -10) >= 5 {
                coordinates.append(Coordinate(
                    lat: location.coordinate.latitude,
                    lon: location.coordinate.longitude,
                    elevation: location.altitude,
                    t: elapsed
                ))
                if coordinates.count > 2000 { coordinates.removeFirst() }
            }
        }
    }

    // MARK: - Simulation (DEBUG screenshots / simulator demos only)

    #if DEBUG
    /// Screenshot helper: show the summary phase for an externally built run.
    func debugShowSummary() {
        phase = .finished
    }

    /// Screenshot helper: pin the heart rate so the zone-pointer bar can be
    /// captured at an exact position inside a zone.
    private var debugPinnedHR: Int?
    func debugForceHR(_ hr: Int) { debugPinnedHR = hr; heartRate = hr }

    /// Screenshot / demo helper: jump straight into a simulated run N seconds in.
    func debugFastForward(_ type: RunType, seconds: Int, paused: Bool = false, keepAlert: Bool = false) {
        isSimulated = true
        if type == .trail, UserDefaults.standard.string(forKey: "screen") != "elevation-noroute" {
            plannedRoute = RoutePlan(profile: TrailProfile.route, distanceKm: 14.2, climbMeters: 918)
        }
        begin(type)
        phase = .running
        for _ in 0..<seconds { simulateOneSecond() }
        alertDismiss?.cancel()
        if !keepAlert { kilometerAlert = nil }
        if paused { phase = .paused }
    }
    #endif

    private func simulateOneSecond() {
        elapsed += 1
        let base: TimeInterval = {
            switch type {
            case .quick: return 324
            case .pacer: return pacerTarget
            case .trail: return 453
            }
        }()
        let wave = sin(elapsed / 285) * 11 + sin(elapsed / 47) * 6 + sin(elapsed / 13) * 3
        let warmup = max(0, 30 - elapsed) * 0.6
        rollingPace = base + wave + warmup + Double.random(in: -2...2)
        distanceKm += 1 / rollingPace
        if let pinned = debugPinnedHR {
            heartRate = pinned
        } else {
            let effortHR: Double = type == .trail ? 158 : (type == .pacer ? 155 : 152)
            let ramp = min(1, elapsed / 300)
            heartRate = Int(82 + (effortHR - 82) * ramp + sin(elapsed / 31) * 5 + Double.random(in: -1...1))
        }
        hrSampleSum += heartRate
        hrSampleCount += 1
        zoneSeconds[currentZone - 1] += 1
        if type == .trail {
            let climbing = sin(elapsed / 120) > -0.35
            if climbing {
                let rate = 420 + sin(elapsed / 60) * 140
                climbMeters += rate / 3600
                climbRatePerHour = max(0, rate + Double.random(in: -25...25))
            } else {
                descentMeters += 700 / 3600
                climbRatePerHour = max(0, climbRatePerHour - 40)
            }
            altitudeMeters = 704 + climbMeters - descentMeters
            if elapsed - lastProfileSample >= 10 {
                lastProfileSample = elapsed
                altitudeProfile.append(altitudeMeters)
            }
        }
        checkKilometerBoundary()
    }

    // MARK: - Haptics

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

// MARK: - HealthKit delegates

extension RunSession: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        // The both-buttons hardware gesture pauses/resumes the session.
        Task { @MainActor in
            switch toState {
            case .paused where self.phase == .running: self.phase = .paused
            case .running where self.phase == .paused: self.phase = .running
            default: break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}
}

extension RunSession: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType,
                  let statistics = workoutBuilder.statistics(for: quantityType) else { continue }
            switch quantityType {
            case HKQuantityType(.heartRate):
                let bpm = statistics.mostRecentQuantity()?
                    .doubleValue(for: HKUnit.count().unitDivided(by: .minute())) ?? 0
                Task { @MainActor in self.heartRate = Int(bpm.rounded()) }
            case HKQuantityType(.distanceWalkingRunning):
                let meters = statistics.sumQuantity()?.doubleValue(for: .meter()) ?? 0
                Task { @MainActor in self.distanceKm = meters / 1000 }
            default:
                break
            }
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

extension RunSession: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for location in locations { self.integrate(location) }
        }
    }
}
