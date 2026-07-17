import Foundation
import WatchConnectivity

/// Watch ↔ iPhone run transfer. The watch queues each finished run with
/// `transferUserInfo` (delivered even if the phone is unreachable right now);
/// the iPhone decodes it into its `RunStore`.
final class RunSync: NSObject, WCSessionDelegate {
    static let shared = RunSync()

    /// Set by the receiving side (iPhone) to ingest arriving runs.
    var onReceive: ((Run) -> Void)?

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Called once at startup so the session is active before it is needed.
    func activate() {}

    func send(_ run: Run) {
        guard WCSession.isSupported(),
              let data = try? JSONEncoder().encode(run) else { return }
        WCSession.default.transferUserInfo(["run": data])
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["run"] as? Data,
              let run = try? JSONDecoder().decode(Run.self, from: data) else { return }
        DispatchQueue.main.async { self.onReceive?(run) }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
    #endif
}
