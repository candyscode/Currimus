import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Settings the iPhone owns and the watch consumes at the start of a run.
struct WatchSettings: Codable, Equatable {
    var pacerTargetSecPerKm: TimeInterval = 315
    var pacerDefaultDistanceKm: Double?          // nil = "Off"
    var kilometerAlert = true
    var countdownEnabled = true
    var maxHR = 190
    /// Optional manual overrides for the four zone upper-bounds (Z1…Z4).
    var zoneBounds: [Int]?
    /// Optional, like every field added later — an older watch build must still
    /// decode a payload from a newer phone.
    var restingHR: Int?
    var gpsAccuracy: GPSAccuracy?
    var alwaysOnReduced: Bool?
}

#if canImport(WatchConnectivity)

/// Watch ↔ iPhone transfer.
/// - Runs: watch → iPhone via `transferUserInfo` (queued, guaranteed delivery).
/// - Settings: iPhone → watch via `updateApplicationContext` (latest-wins).
///
/// The callbacks are main-actor properties: `RunStore` writes them on the main
/// actor, and `WCSessionDelegate` callbacks arrive on a background queue.
/// Hopping to the main actor before touching them is what makes that safe —
/// reading them straight from the delegate thread was an unsynchronised access
/// that Swift 5 mode could not see.
final class RunSync: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = RunSync()

    /// Receiving side (iPhone) ingests arriving runs.
    @MainActor var onReceive: ((Run) -> Void)?
    /// Receiving side (watch) applies arriving settings.
    @MainActor var onSettings: ((WatchSettings) -> Void)?

    private override init() {
        super.init()
        activate()
    }

    /// Idempotent — the app, the store and the watch root all want to be sure
    /// the session is up without caring who got there first.
    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState != .activated else { return }
        session.delegate = self
        session.activate()
    }

    // MARK: - Send

    func send(_ run: Run) {
        guard WCSession.isSupported() else { return }
        // A transfer queued before activation is dropped, and a finished run
        // is exactly what must not be dropped.
        guard WCSession.default.activationState == .activated else {
            Log.sync.error("run not sent: session not activated")
            return
        }
        do {
            WCSession.default.transferUserInfo(["run": try JSONEncoder().encode(run)])
        } catch {
            Log.sync.error("run not encoded: \(error.localizedDescription, privacy: .public)")
        }
    }

    func send(settings: WatchSettings) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        do {
            let data = try JSONEncoder().encode(settings)
            try WCSession.default.updateApplicationContext(["settings": data])
        } catch {
            Log.sync.error("settings not sent: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        if let error {
            Log.sync.error("activation failed: \(error.localizedDescription, privacy: .public)")
        }
        // Apply any settings that were queued before activation completed.
        applySettings(from: session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["run"] as? Data else { return }
        do {
            let run = try JSONDecoder().decode(Run.self, from: data)
            Task { @MainActor in self.onReceive?(run) }
        } catch {
            Log.sync.error("arriving run unreadable: \(error.localizedDescription, privacy: .public)")
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        applySettings(from: applicationContext)
    }

    private func applySettings(from context: [String: Any]) {
        guard let data = context["settings"] as? Data else { return }
        do {
            let settings = try JSONDecoder().decode(WatchSettings.self, from: data)
            Task { @MainActor in self.onSettings?(settings) }
        } catch {
            Log.sync.error("arriving settings unreadable: \(error.localizedDescription, privacy: .public)")
        }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
    #endif
}

#else

/// tvOS has no WatchConnectivity: there is no watch to pair with and no phone
/// session to join. The TV is a pure CloudKit reader (see `RunCloudSync`), so
/// this stub keeps `RunStore`'s call sites (`RunSync.shared.activate()`,
/// `onReceive`, `onSettings`, `send(_:)`, `send(settings:)`) compiling and
/// inert on the platform. Every method is a no-op.
final class RunSync: @unchecked Sendable {
    static let shared = RunSync()

    @MainActor var onReceive: ((Run) -> Void)?
    @MainActor var onSettings: ((WatchSettings) -> Void)?

    private init() {}

    func activate() {}
    func send(_ run: Run) {}
    func send(settings: WatchSettings) {}
}

#endif
