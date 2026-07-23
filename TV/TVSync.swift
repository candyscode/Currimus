import SwiftUI

/// Drives the Apple TV's one job: pull the run log out of CloudKit and pour it
/// into the shared `RunStore`, so every screen reuses the phone's aggregates,
/// records and charts unchanged.
///
/// The store is the model; this is the loading state around it — account
/// reachability, an in-flight flag, and whether the first fetch has landed —
/// so the UI can tell "signed out" from "still loading" from "signed in, no
/// runs yet". It owns no run data itself.
@MainActor
final class TVSync: ObservableObject {
    enum Phase: Equatable {
        case loading            // first fetch in flight, nothing to show yet
        case ready              // at least one fetch has completed
        case signedOut          // iCloud unavailable on this device
    }

    @Published private(set) var phase: Phase = .loading
    /// True while a refresh is running *after* the first load, so the UI can
    /// show a quiet spinner without blanking the screen.
    @Published private(set) var isRefreshing = false

    private let store: RunStore

    init(store: RunStore) {
        self.store = store
    }

    /// Fetch the log and hand it to the store. Safe to call on every appear /
    /// foreground; the store replaces its log wholesale, so nothing duplicates.
    func refresh() async {
        if phase != .loading { isRefreshing = true }
        defer { isRefreshing = false }

        guard await RunCloudSync.accountAvailable() else {
            phase = .signedOut
            return
        }

        let runs = await RunCloudSync.fetchRuns()
        store.replaceAllFromCloud(runs)
        phase = .ready
    }
}
