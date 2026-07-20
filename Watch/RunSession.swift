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
///
/// The arithmetic lives in `RunMetrics`; what is left here is lifecycle —
/// permissions, the workout session, the per-second clock, haptics.
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

    /// Something the recording cannot do, in the user's terms.
    ///
    /// These used to be silent `return`s. A denied Health prompt left the
    /// clock ticking over a distance frozen at 0.00 with nothing on screen to
    /// explain it — the worst failure this app has, because a run cannot be
    /// run again.
    enum RecordingIssue: Equatable, Hashable {
        case healthUnavailable
        case healthDenied
        case workoutFailed
        case locationDenied

        var headline: String {
            switch self {
            case .healthUnavailable: return "No Health data"
            case .healthDenied: return "Health access off"
            case .workoutFailed: return "Workout not started"
            case .locationDenied: return "Location off"
            }
        }

        /// What is actually lost, so carrying on is an informed choice.
        var detail: String {
            switch self {
            case .healthUnavailable:
                return "This watch has no Health data. Time is recorded; heart rate and distance are not."
            case .healthDenied:
                return "Without Health access there is no heart rate and no distance. Allow it in Settings › Privacy › Health."
            case .workoutFailed:
                return "The workout session did not start. Time and GPS still record; heart rate does not."
            case .locationDenied:
                return "Without location there is no route, climb or elevation. Allow it in Settings › Privacy › Location."
            }
        }
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
    @Published private(set) var metrics = RunMetrics()
    /// Non-fatal recording problems. The run screen shows the first one; the
    /// summary repeats it so it survives a glance mid-run.
    @Published private(set) var issues: [RecordingIssue] = []
    @Published var kilometerAlert: KilometerAlert?
    @Published var pacerTarget: TimeInterval = 315
    /// nil = "Off" — pacer runs open-ended, no finish forecast.
    @Published var pacerDistanceKm: Double?
    var zones = HRZones()
    var kilometerAlertEnabled = true
    var gpsAccuracy: GPSAccuracy = .high

    // MARK: - Metrics passthrough (what the views read)

    var rollingPace: TimeInterval { metrics.rollingPace }
    var splits: [TimeInterval] { metrics.splits }
    var zoneSeconds: [TimeInterval] { metrics.zoneSeconds }
    var climbMeters: Double { metrics.climbMeters }
    var descentMeters: Double { metrics.descentMeters }
    var climbRatePerHour: Double { metrics.climbRatePerHour }
    var altitudeMeters: Double { metrics.altitudeMeters }
    /// Altitude samples of the run so far, for the no-route elevation profile.
    var altitudeProfile: [Double] { metrics.altitudeProfile }

    // MARK: - Internals

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private let locationManager = CLLocationManager()

    private var timer: AnyCancellable?
    private var alertDismiss: Task<Void, Never>?
    /// Wall-clock start, so a paused run still reports when it actually began.
    private var startDate: Date?
    private var isSimulated = false
    /// When false, `begin` skips the 3-2-1 countdown (iPhone setting).
    var countdownEnabled = true

    // MARK: - Derived

    /// 0 = no heart-rate reading yet — the zone bar stays unlit.
    var currentZone: Int { heartRate > 0 ? zones.zone(for: heartRate) : 0 }
    var averagePace: TimeInterval { distanceKm > 0.05 ? elapsed / distanceKm : 0 }
    var averageHR: Int { metrics.averageHR > 0 ? metrics.averageHR : heartRate }
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
        startDate = .now
        phase = countdownEnabled ? .countdown(3) : .running
        haptic(.start)
        startTimer()

        guard !isSimulated else { return }
        // GPS first, and independently of Health: location needs no HealthKit
        // grant, and a run with a route but no heart rate beats one with
        // neither. Starting it inside the authorization callback meant a
        // declined Health prompt silently killed GPS too.
        startLocationUpdates()
        Task { await requestAuthorizationThenPrepare() }
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
            // `elapsed` excludes pauses, so `now - elapsed` walked the start
            // time forward on every paused run. Use the real one.
            date: startDate ?? .now.addingTimeInterval(-elapsed),
            type: type,
            name: defaultName,
            distanceKm: (distanceKm * 100).rounded() / 100,
            duration: elapsed,
            avgHR: averageHR,
            splits: metrics.splits,
            zoneSeconds: metrics.zoneSeconds,
            climbMeters: metrics.climbMeters.rounded(),
            descentMeters: metrics.descentMeters.rounded(),
            highPointMeters: metrics.altitudeProfile.max().map { $0.rounded() },
            altitudeSamples: metrics.altitudeProfile.isEmpty ? nil : metrics.altitudeProfile,
            route: metrics.coordinates.isEmpty ? nil : metrics.coordinates
        )

        finishWorkout()
        RunSync.shared.send(run)
        return run
    }

    func reset() {
        timer?.cancel()
        phase = .idle
        issues = []
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
        elapsed = 0
        distanceKm = 0
        heartRate = 0
        metrics = RunMetrics()
        kilometerAlert = nil
        issues = []
        if type != .pacer { pacerDistanceKm = nil }
    }

    private func startTimer() {
        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    private func note(_ issue: RecordingIssue) {
        guard !issues.contains(issue) else { return }
        issues.append(issue)
        Log.session.error("recording degraded: \(issue.headline, privacy: .public)")
    }

    // MARK: - HealthKit

    private func requestAuthorizationThenPrepare() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            note(.healthUnavailable)
            return
        }
        let share: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
        ]
        let read: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.activeEnergyBurned),
        ]
        do {
            try await healthStore.requestAuthorization(toShare: share, read: read)
        } catch {
            Log.session.error("health authorization failed: \(error.localizedDescription, privacy: .public)")
            note(.healthDenied)
            return
        }
        // Read authorization is never knowable (Health hides it deliberately),
        // but a workout we may not save is a denial we can actually detect —
        // and it is the one that costs the user their heart rate.
        if healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingDenied {
            note(.healthDenied)
        }
        startWorkoutSession()
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
            builder.beginCollection(withStart: .now) { started, error in
                if !started {
                    Log.session.error("collection did not begin: \(error?.localizedDescription ?? "unknown", privacy: .public)")
                }
            }
        } catch {
            Log.session.error("workout session failed: \(error.localizedDescription, privacy: .public)")
            workoutSession = nil
            workoutBuilder = nil
            note(.workoutFailed)
        }
    }

    private func startLocationUpdates() {
        locationManager.delegate = self
        // GPS dominates the run's power draw, so the user's choice lands here.
        locationManager.desiredAccuracy = gpsAccuracy == .high
            ? kCLLocationAccuracyBest
            : gpsAccuracy.desiredAccuracy
        locationManager.distanceFilter = gpsAccuracy.distanceFilter > 0
            ? gpsAccuracy.distanceFilter
            : kCLDistanceFilterNone
        locationManager.activityType = .fitness
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        checkLocationAuthorization()
    }

    private func checkLocationAuthorization() {
        switch locationManager.authorizationStatus {
        case .denied, .restricted: note(.locationDenied)
        default: break
        }
    }

    private func finishWorkout() {
        locationManager.stopUpdatingLocation()
        guard let session = workoutSession, let builder = workoutBuilder else { return }
        session.end()
        builder.endCollection(withEnd: .now) { [routeBuilder] ended, error in
            if !ended {
                Log.session.error("collection did not end: \(error?.localizedDescription ?? "unknown", privacy: .public)")
            }
            builder.finishWorkout { workout, error in
                guard let workout else {
                    Log.session.error("workout not saved: \(error?.localizedDescription ?? "unknown", privacy: .public)")
                    return
                }
                routeBuilder?.finishRoute(with: workout, metadata: nil) { _, error in
                    if let error {
                        Log.session.error("route not saved: \(error.localizedDescription, privacy: .public)")
                    }
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
        let split = metrics.tick(elapsed: elapsed, distanceKm: distanceKm,
                                 heartRate: heartRate, zone: currentZone)
        if let split { raiseKilometerAlert(split) }
    }

    private func raiseKilometerAlert(_ split: RunMetrics.KilometerSplit) {
        guard kilometerAlertEnabled else { return }
        kilometerAlert = KilometerAlert(km: split.km, splitSeconds: split.seconds,
                                        deltaVsAvg: split.deltaVsAverage)
        haptic(.notification)
        alertDismiss?.cancel()
        alertDismiss = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { self?.kilometerAlert = nil }
        }
    }

    // MARK: - Location → route, altitude

    fileprivate func integrate(_ location: CLLocation) {
        guard phase == .running else { return }

        metrics.ingestAltitude(location.altitude,
                               verticalAccuracy: location.verticalAccuracy,
                               at: elapsed)

        if location.horizontalAccuracy >= 0,
           location.horizontalAccuracy < RunMetrics.usableHorizontalAccuracy {
            routeBuilder?.insertRouteData([location]) { inserted, error in
                if !inserted {
                    Log.session.error("route point dropped: \(error?.localizedDescription ?? "unknown", privacy: .public)")
                }
            }
        }
        // Local copy for the map + GPX export; the route builder's own copy
        // goes to Health and is not readable back during the run.
        metrics.ingestCoordinate(latitude: location.coordinate.latitude,
                                 longitude: location.coordinate.longitude,
                                 altitude: location.altitude,
                                 horizontalAccuracy: location.horizontalAccuracy,
                                 at: elapsed)
    }

    // MARK: - Simulation (DEBUG screenshots / simulator demos only)

    #if DEBUG
    /// Screenshot helper: show the summary phase for an externally built run.
    func debugShowSummary() {
        phase = .finished
    }

    /// Screenshot helper: pin the heart rate so the zone-pointer bar can be
    /// captured at an exact position inside a zone.
    func debugForceHR(_ hr: Int) { debugPinnedHR = hr; heartRate = hr }

    /// Replaces the simulated altitude series with a known one, so the Y axis
    /// can be validated against numbers instead of a moving simulation.
    func debugSetAltitudeProfile(_ samples: [Double]) {
        metrics.overrideAltitudeProfile(samples)
        debugPinnedAltitude = true
    }

    /// Screenshot helper: render an issue banner without a real failure.
    func debugRaiseIssue(_ issue: RecordingIssue) {
        issues = [issue]
    }

    /// Screenshot / demo helper: jump straight into a simulated run N seconds in.
    func debugFastForward(_ type: RunType, seconds: Int, paused: Bool = false, keepAlert: Bool = false) {
        isSimulated = true
        begin(type)
        phase = .running
        for _ in 0..<seconds { simulateOneSecond() }
        alertDismiss?.cancel()
        if !keepAlert { kilometerAlert = nil }
        if paused { phase = .paused }
    }
    #endif

    /// A pinned debug profile owns the altitude — otherwise the simulation
    /// would drift the readout out of the chart's own axis range.
    private var debugPinnedAltitude = false
    /// Pinned heart rate for zone-pointer screenshots.
    private var debugPinnedHR: Int?

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
        let pace = base + wave + warmup + Double.random(in: -2...2)
        metrics.setRollingPace(pace)
        distanceKm += 1 / pace

        #if DEBUG
        heartRate = debugPinnedHR ?? simulatedHeartRate
        #else
        heartRate = simulatedHeartRate
        #endif

        if type == .trail {
            let climbing = sin(elapsed / 120) > -0.35
            if climbing {
                let rate = 420 + sin(elapsed / 60) * 140
                metrics.addSimulatedClimb(rate / 3600, ratePerHour: rate + Double.random(in: -25...25))
            } else {
                metrics.addSimulatedDescent(700 / 3600)
            }
            if !debugPinnedAltitude {
                metrics.setSimulatedAltitude(704 + metrics.climbMeters - metrics.descentMeters,
                                             at: elapsed)
            }
        }

        // Zone time and splits follow the same path a real second takes.
        let split = metrics.tick(elapsed: elapsed, distanceKm: distanceKm,
                                 heartRate: heartRate, zone: currentZone)
        if let split { raiseKilometerAlert(split) }
    }

    private var simulatedHeartRate: Int {
        let effortHR: Double = type == .trail ? 158 : (type == .pacer ? 155 : 152)
        let ramp = min(1, elapsed / 300)
        return Int(82 + (effortHR - 82) * ramp + sin(elapsed / 31) * 5 + Double.random(in: -1...1))
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

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Log.session.error("workout session failed: \(error.localizedDescription, privacy: .public)")
        Task { @MainActor in self.note(.workoutFailed) }
    }
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

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Log.session.error("location failed: \(error.localizedDescription, privacy: .public)")
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.checkLocationAuthorization() }
    }
}
