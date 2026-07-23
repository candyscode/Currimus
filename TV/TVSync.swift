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
        case signedOut          // no iCloud account — the explain-and-stop state
    }

    @Published private(set) var phase: Phase = .loading
    /// True while a refresh is running *after* the first successful load, so the
    /// UI can show a quiet spinner over existing content instead of blanking it.
    @Published private(set) var isRefreshing = false

    private let store: RunStore

    /// Whether a successful fetch has ever populated the store this launch. Once
    /// true, a later failure must not blank the screen or wipe the cache.
    private var hasLoaded = false

    init(store: RunStore) {
        self.store = store
    }

    /// Fetch the log and hand it to the store. Safe to call on every appear /
    /// foreground; the store replaces its log wholesale, so nothing duplicates.
    ///
    /// Failure is deliberately non-destructive. A transient account status or a
    /// fetch error leaves whatever is already on screen (or the persisted
    /// offline cache) untouched — only a confirmed sign-out or a genuinely empty
    /// account changes what the user sees.
    func refresh() async {
        if hasLoaded { isRefreshing = true }
        defer { isRefreshing = false }

        switch await RunCloudSync.accountState() {
        case .signedOut:
            phase = .signedOut
            return
        case .transient:
            // Don't downgrade to signed-out on a hiccup. If we've loaded before,
            // keep showing it; otherwise stay on the loading screen and let the
            // next foreground retry.
            return
        case .available:
            break
        }

        do {
            let runs = try await RunCloudSync.fetchRuns()
            store.replaceAllFromCloud(runs)
            hasLoaded = true
            phase = .ready
        } catch {
            // A failed fetch is not an empty log. Never feed [] into the store —
            // that would wipe the offline cache and show "no runs". Leave the
            // last good data in place and let the next refresh try again.
            Log.sync.error("TV refresh failed: \(error.localizedDescription, privacy: .public)")
            if hasLoaded { phase = .ready }   // keep showing cached runs
        }
    }
}
