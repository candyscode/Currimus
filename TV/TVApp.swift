import SwiftUI

@main
struct CurrimusTVApp: App {
    @StateObject private var store: RunStore
    @StateObject private var sync: TVSync
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FontLoader.registerAll()
        // One store, shared with the sync driver. `StateObject(wrappedValue:)`
        // keeps SwiftUI's single-instance guarantee while letting the two
        // objects reference each other.
        let store = RunStore()
        _store = StateObject(wrappedValue: store)
        _sync = StateObject(wrappedValue: TVSync(store: store))
    }

    var body: some Scene {
        WindowGroup {
            TVRootView()
                .environmentObject(store)
                .environmentObject(sync)
                .preferredColorScheme(.dark)
                .tint(Theme.signal)
                .task { await sync.refresh() }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await sync.refresh() }
                }
        }
    }
}

/// The TV shell: a top tab bar (Home · Log · Progress) over the ink background,
/// with the loading and signed-out states handled once, up front, so each tab
/// can assume it has data.
struct TVRootView: View {
    @EnvironmentObject private var store: RunStore
    @EnvironmentObject private var sync: TVSync

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            switch sync.phase {
            case .loading:
                TVStatusView(
                    title: "Loading your runs",
                    message: "Fetching from iCloud…",
                    showsProgress: true
                )
            case .signedOut:
                TVStatusView(
                    title: "Sign in to iCloud",
                    message: "Currimus shows the runs from your iPhone. Sign this Apple TV into the same iCloud account in Settings, then reopen Currimus.",
                    showsProgress: false
                )
            case .ready:
                if store.allRuns.isEmpty {
                    TVStatusView(
                        title: "No runs yet",
                        message: "Runs you record on your Apple Watch and iPhone appear here automatically.",
                        showsProgress: false
                    )
                } else {
                    tabs
                }
            }
        }
        .foregroundStyle(Theme.ink)
    }

    private var tabs: some View {
        TabView {
            TVDashboardView()
                .tabItem { Text("Home") }
            TVLogView()
                .tabItem { Text("Log") }
            TVProgressView()
                .tabItem { Text("Progress") }
        }
    }
}

/// Full-screen centered message for the loading / signed-out / empty states.
struct TVStatusView: View {
    var title: String
    var message: String
    var showsProgress: Bool

    var body: some View {
        VStack(spacing: 24) {
            Text("CURRIMUS").font(.sg(20, weight: .bold)).kerning(4)
                .foregroundStyle(Theme.signal)
            Text(title).font(.sg(40, weight: .semibold)).kerning(-0.8)
            Text(message)
                .font(.sg(24)).foregroundStyle(Theme.bright)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 760)
                .lineSpacing(6)
            if showsProgress {
                ProgressView().tint(Theme.signal).padding(.top, 8)
            }
        }
        .padding(60)
    }
}
