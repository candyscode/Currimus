import Foundation
import WatchConnectivity
import WidgetKit

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
    /// Where the numbers above came from. Carried for two reasons, and the
    /// second is why it is here at all:
    ///
    /// - The watch runs the same `refreshHeartRateZones` the phone does, so it
    ///   needs to know whether these zones are still Currimus' to maintain.
    /// - This payload *is* the persisted settings blob (`AppDefaults.settingsKey`).
    ///   Without the derivation in it, `isAutomatic` came back `true` on every
    ///   launch and the automatic refresh overwrote a max heart rate the runner
    ///   had set by hand — the exact behaviour CUR-2 removed, reintroduced
    ///   through the store rather than through the model.
    var derivation: HRDerivation?
    var gpsAccuracy: GPSAccuracy?
    var alwaysOnReduced: Bool?
    /// Zone the watch should hold the runner in by vibration alone (1…5);
    /// nil = off, which is also what an older phone's payload decodes to.
    var zoneCoachTarget: Int?
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

    /// Encoding and handing over happen off the caller's thread: a finished
    /// run carries its whole GPS track, and that encode ran on the main thread
    /// at the exact moment the watch was drawing the summary.
    private let queue = DispatchQueue(label: "com.currimus.app.sync", qos: .utility)

    /// How large a payload may be before it goes as a file instead.
    ///
    /// `transferUserInfo` refuses a dictionary past a limit Apple does not
    /// publish, and it refuses it *asynchronously* — the call returns a transfer
    /// object either way and the failure arrives, if anyone is listening, in
    /// `didFinish`. Nobody was listening (CUR-40), so a run that was too big
    /// simply never appeared on the phone while its workout sat in Apple
    /// Health, saved.
    ///
    /// A four-hour trail run carries two thousand GPS points, which at full
    /// `Double` precision is six figures of JSON. Sixty kilobytes is far under
    /// any limit anyone has measured; past it, `transferFile` carries the same
    /// bytes with the same delivery guarantee and no size limit at all.
    static let maxPayloadBytes = 60_000

    /// How a run's bytes should travel.
    enum Delivery: Equatable {
        /// Small enough for the dictionary queue.
        case userInfo(Data)
        /// Too big for it — the same JSON, sent as a file.
        case file(Data)

        var data: Data {
            switch self {
            case .userInfo(let data), .file(let data): return data
            }
        }
    }

    /// Hands a finished run to the phone, and keeps hold of it until the system
    /// confirms it arrived.
    ///
    /// The outbox is the point. A run cannot be run again, so every path that
    /// used to end in `return` — session not activated yet, payload refused,
    /// watch app killed before the transfer drained — now ends in the run
    /// staying on disk and being offered again at the next opportunity.
    func send(_ run: Run) {
        guard WCSession.isSupported() else { return }
        queue.async {
            guard let delivery = Self.delivery(for: run) else { return }
            self.remember(delivery.data, id: run.id.uuidString)
            self.flushPending()
        }
    }

    /// Encodes a run and says how it has to travel.
    ///
    /// Nothing is thinned. An earlier version of this fix decimated the track
    /// until it fitted the dictionary limit, which trades one silent failure
    /// for another: a marathon would have arrived with half its GPS points and
    /// nobody would have been told. A file has no such limit.
    static func delivery(for run: Run) -> Delivery? {
        do {
            let data = try JSONEncoder().encode(run.roundedForTransfer)
            return data.count <= maxPayloadBytes ? .userInfo(data) : .file(data)
        } catch {
            Log.sync.error("run not encoded: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - The outbox

    /// One run handed over and not yet confirmed delivered.
    struct Pending: Codable, Equatable {
        var id: String
        var run: Data
        var queued: Date
    }

    /// Where they live. The app group rather than memory: the run has to
    /// survive the watch app being killed, which is exactly what happens when
    /// someone finishes a run and drops their wrist.
    private static let outboxKey = "outbox.v1"
    /// How long a run keeps being re-offered. Long enough to cover a phone left
    /// at home for a week; short enough that a watch with no phone paired to it
    /// at all does not accumulate every run it ever recorded.
    static let outboxLifetime: TimeInterval = 14 * 86_400
    static let outboxCapacity = 50

    /// Guards the read-modify-write. `UserDefaults` is thread-safe per call,
    /// which is not the same thing: two runs finishing close together could each
    /// read the outbox, add themselves and write back, and one of them would be
    /// the run that goes missing.
    private let outboxLock = NSLock()

    private var outbox: [Pending] {
        guard let data = AppDefaults.shared.data(forKey: Self.outboxKey) else { return [] }
        return (try? JSONDecoder().decode([Pending].self, from: data)) ?? []
    }

    /// Applies a change to the outbox, oldest first, trimmed on the way out.
    private func updateOutbox(_ change: (inout [Pending]) -> Void) {
        outboxLock.withLock {
            var pending = outbox
            change(&pending)
            pending = Self.trimmed(pending)
            guard let data = try? JSONEncoder().encode(pending) else { return }
            AppDefaults.shared.set(data, forKey: Self.outboxKey)
        }
    }

    /// Drops what has waited too long, and keeps the newest of what is left.
    static func trimmed(_ pending: [Pending], now: Date = .now) -> [Pending] {
        pending
            .filter { now.timeIntervalSince($0.queued) < outboxLifetime }
            .sorted { $0.queued < $1.queued }
            .suffix(outboxCapacity)
            .map { $0 }
    }

    private func remember(_ data: Data, id: String) {
        updateOutbox { pending in
            pending.removeAll { $0.id == id }
            pending.append(Pending(id: id, run: data, queued: .now))
        }
    }

    private func forget(_ id: String) {
        updateOutbox { $0.removeAll { $0.id == id } }
    }

    /// Offers everything in the outbox that is not already in flight.
    ///
    /// Safe to call as often as anything likes: WatchConnectivity's own queue is
    /// the source of truth for what is in flight, and the phone drops a run it
    /// already holds by id.
    func flush() {
        queue.async { self.flushPending() }
    }

    /// The work itself, on `queue`. It decodes every waiting run's whole
    /// payload and writes the oversized ones to disk — nothing to do on the
    /// main actor, which is where the foreground call comes from, and the case
    /// this exists for is precisely the one with a week of trail runs in it.
    private func flushPending() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let session = WCSession.default
        let inFlight = Set(
            session.outstandingUserInfoTransfers.compactMap { $0.userInfo["id"] as? String }
            + session.outstandingFileTransfers.compactMap { $0.file.metadata?["id"] as? String })
        for entry in outbox where !inFlight.contains(entry.id) {
            if entry.run.count <= Self.maxPayloadBytes {
                session.transferUserInfo(["id": entry.id, "run": entry.run])
            } else if let url = spool(entry) {
                session.transferFile(url, metadata: ["id": entry.id])
            }
        }
    }

    /// Writes a too-big run out for `transferFile`.
    ///
    /// The system copies the file when the transfer completes and leaves the
    /// original to us; `didFinish(fileTransfer:)` removes it. The name carries
    /// the run id so a re-offer overwrites its own previous attempt rather than
    /// filling the container with copies of the same marathon.
    private func spool(_ entry: Pending) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-\(entry.id).json")
        do {
            try entry.run.write(to: url, options: .atomic)
            return url
        } catch {
            Log.sync.error("run not spooled: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func send(settings: WatchSettings) {
        contextLock.lock()
        lastSettings = try? JSONEncoder().encode(settings)
        contextLock.unlock()
        pushContext()
    }

    /// The phone's own week/month/year distance, for the watch's complications.
    ///
    /// The watch cannot work these out for itself: its HealthKit store holds
    /// only what it recorded plus a short window synced from the phone, so a
    /// year total read on the watch is short by everything older than that
    /// window and by every run some phone-side app recorded (CUR-46). The
    /// phone's log is the one place with the whole picture.
    func send(totals: DistanceTotals) {
        contextLock.lock()
        lastTotals = try? JSONEncoder().encode(totals)
        contextLock.unlock()
        pushContext()
    }

    /// One application context, both payloads, every time.
    ///
    /// `updateApplicationContext` **replaces** the dictionary rather than
    /// merging into it, so sending only the key that changed would silently
    /// drop the other one — a settings change would erase the totals until the
    /// next run finished, and vice versa.
    private func pushContext() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        contextLock.lock()
        var context: [String: Any] = [:]
        if let lastSettings { context["settings"] = lastSettings }
        if let lastTotals { context["totals"] = lastTotals }
        contextLock.unlock()
        guard !context.isEmpty else { return }
        do {
            try WCSession.default.updateApplicationContext(context)
        } catch {
            Log.sync.error("context not sent: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Both senders are called from the store's io queue, and the delegate
    /// callbacks arrive on a queue of WatchConnectivity's choosing.
    private let contextLock = NSLock()
    private var lastSettings: Data?
    private var lastTotals: Data?

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
        // And offer anything a previous launch could not hand over. This is the
        // path a run took when it was finished before the session was ready.
        flush()
    }

    /// The delivery receipt — and, until CUR-40, the callback nobody
    /// implemented. A transfer that failed said nothing to anyone, and the run
    /// it carried was gone.
    func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer,
                 error: Error?) {
        guard let id = userInfoTransfer.userInfo["id"] as? String else { return }
        if let error {
            // Left in the outbox on purpose: the next flush tries again.
            Log.sync.error("run \(id, privacy: .public) not delivered: \(error.localizedDescription, privacy: .public)")
            return
        }
        forget(id)
    }

    /// The same receipt for the runs that travelled as files.
    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer,
                 error: Error?) {
        // Unconditionally, and before anything else can return: the run itself
        // is safe in the outbox, and `spool` writes the file again from there
        // on the next attempt. Deleting only on success left one copy of every
        // failed marathon in the container.
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
        guard let id = fileTransfer.file.metadata?["id"] as? String else { return }
        if let error {
            Log.sync.error("run \(id, privacy: .public) not delivered: \(error.localizedDescription, privacy: .public)")
            return
        }
        forget(id)
    }

    /// The phone coming back into range is the moment a queued run can move.
    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable { flush() }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["run"] as? Data else { return }
        ingest(data)
    }

    /// A run big enough to have travelled as a file — a long trail day, an
    /// ultra. Read here and now: the system deletes the file the moment this
    /// returns.
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        do {
            ingest(try Data(contentsOf: file.fileURL))
        } catch {
            Log.sync.error("arriving run file unreadable: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A run may arrive more than once — the watch re-offers anything the
    /// system has not confirmed. `RunStore.add` drops one it already holds.
    private func ingest(_ data: Data) {
        do {
            let run = try JSONDecoder().decode(Run.self, from: data)
            Task { @MainActor in self.onReceive?(run) }
        } catch {
            Log.sync.error("arriving run unreadable: \(error.localizedDescription, privacy: .public)")
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        applySettings(from: applicationContext)
        applyTotals(from: applicationContext)
    }

    /// Straight into the shared defaults, off the main actor and without the
    /// store: the complications read this key and nothing else has to happen
    /// for them to be right. `RunStore` picks it up as a side effect of living
    /// in the same app group.
    private func applyTotals(from context: [String: Any]) {
        #if os(watchOS)
        guard let data = context["totals"] as? Data else { return }
        guard (try? JSONDecoder().decode(DistanceTotals.self, from: data)) != nil else {
            Log.sync.error("arriving totals unreadable")
            return
        }
        AppDefaults.shared.set(data, forKey: AppDefaults.totalsKey)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
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
