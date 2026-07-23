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

        switch await resolvedState() {
        case .signedOut:
            // A confirmed sign-out is the one state worth explaining. Don't
            // clobber an already-loaded screen, though — the account can't
            // change under a running TV app in practice, and keeping cached
            // runs beats flashing a sign-in prompt.
            if !hasLoaded { phase = .signedOut }
            return
        case .transient:
            // Never resolved (rare). Leave the current screen — loading on a
            // cold start, or the cached log — and let the next foreground retry.
            // Crucially NOT signed-out: that would misread a hiccup as no account.
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

    /// Resolve the account status, retrying a transient answer a few times with
    /// a short backoff. iCloud status is often transient in the seconds right
    /// after boot, and since the scene is already active on first launch nothing
    /// would re-drive the refresh — so without this the TV could sit on the
    /// loading spinner. Returns `.available` / `.signedOut` as soon as either is
    /// seen, else `.transient` after the last attempt.
    private func resolvedState() async -> RunCloudSync.AccountState {
        for attempt in 0..<transientRetryLimit {
            let state = await RunCloudSync.accountState()
            if state != .transient { return state }
            if attempt < transientRetryLimit - 1 {
                try? await Task.sleep(for: .seconds(1))
            }
        }
        return .transient
    }

    private let transientRetryLimit = 3
}
