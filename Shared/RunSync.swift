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
}

/// Watch ↔ iPhone transfer.
/// - Runs: watch → iPhone via `transferUserInfo` (queued, guaranteed delivery).
/// - Settings: iPhone → watch via `updateApplicationContext` (latest-wins).
final class RunSync: NSObject, WCSessionDelegate {
    static let shared = RunSync()

    /// Receiving side (iPhone) ingests arriving runs.
    var onReceive: ((Run) -> Void)?
    /// Receiving side (watch) applies arriving settings.
    var onSettings: ((WatchSettings) -> Void)?

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func activate() {}

    // MARK: - Send

    func send(_ run: Run) {
        guard WCSession.isSupported(),
              let data = try? JSONEncoder().encode(run) else { return }
        WCSession.default.transferUserInfo(["run": data])
    }

    func send(settings: WatchSettings) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              let data = try? JSONEncoder().encode(settings) else { return }
        try? WCSession.default.updateApplicationContext(["settings": data])
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        // Apply any settings that were queued before activation completed.
        applySettings(from: session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["run"] as? Data,
              let run = try? JSONDecoder().decode(Run.self, from: data) else { return }
        DispatchQueue.main.async { self.onReceive?(run) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        applySettings(from: applicationContext)
    }

    private func applySettings(from context: [String: Any]) {
        guard let data = context["settings"] as? Data,
              let settings = try? JSONDecoder().decode(WatchSettings.self, from: data) else { return }
        DispatchQueue.main.async { self.onSettings?(settings) }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
    #endif
}
