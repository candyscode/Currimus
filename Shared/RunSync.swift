import Foundation
import WatchConnectivity

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

/// Whether there is a watch to record on at all.
///
/// The iPhone is a reader: it shows a log the watch fills. Every screen that
/// says so — the first-launch screen most of all — is a dead end for someone
/// with no watch paired, or with one that does not have Currimus on it, and
/// the app had no way of telling the difference.
enum WatchAvailability: Equatable {
    /// Paired, and Currimus is installed on it.
    case ready
    /// Paired, but the watch app is not installed.
    case appMissing
    /// No watch paired to this iPhone.
    case noWatch
    /// This device cannot pair a watch at all, or the state is not known yet.
    case unknown
}

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
    #if os(iOS)
    /// Receiving side (iPhone) learns whether there is a watch to record on.
    @MainActor var onWatchState: ((WatchAvailability) -> Void)?
    #endif

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
        publishWatchState(session)
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

    /// Fires when a watch is paired or unpaired, and when the watch app is
    /// installed or removed.
    func sessionWatchStateDidChange(_ session: WCSession) { publishWatchState(session) }

    private func publishWatchState(_ session: WCSession) {
        // Read here, on the delegate's own queue, and handed on as a value.
        let state: WatchAvailability = session.isPaired
            ? (session.isWatchAppInstalled ? .ready : .appMissing)
            : .noWatch
        Task { @MainActor in self.onWatchState?(state) }
    }
    #else
    private func publishWatchState(_ session: WCSession) {}
    #endif
}
