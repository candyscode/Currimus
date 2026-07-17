import SwiftUI

@main
struct CurrimusWatchApp: App {
    @StateObject private var store = RunStore()

    init() {
        FontLoader.registerAll()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(store)
        }
    }
}

struct WatchRootView: View {
    @EnvironmentObject private var store: RunStore
    @StateObject private var session = RunSession()
    @State private var finishedRun: Run?

    var body: some View {
        // NavigationStack + hidden bar removes the system clock so the layout
        // can own the full canvas, exactly like the design frames.
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                // The top safe area stays — the system clock owns that corner
                // (it cannot be hidden); sides and bottom are full-bleed like
                // the design frames.
                content
                    .ignoresSafeArea(edges: [.horizontal, .bottom])
            }
            .foregroundStyle(Theme.ink)
            .toolbar(.hidden, for: .navigationBar)
            .persistentSystemOverlays(.hidden)
        }
        .onAppear(perform: handleLaunchRoute)
    }

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .idle:
            WatchHomeView(
                lastRun: store.lastRun,
                onStart: { start(.quick) },
                onTrail: { start(.trail) },
                onPacer: {
                    session.pacerTarget = store.pacerTargetSecPerKm
                    session.setupPacer()
                }
            )
        case .pacerSetup:
            PacerSetupView(session: session) {
                store.pacerTargetSecPerKm = session.pacerTarget
                start(.pacer)
            }
        case .countdown(let n):
            CountdownView(count: n)
        case .running:
            if session.type == .trail {
                TrailRunPager(session: session)
            } else {
                RunView(session: session)
            }
        case .paused:
            PausedView(session: session) { finish() }
        case .finished:
            if let run = finishedRun {
                SummaryView(run: run) {
                    finishedRun = nil
                    session.reset()
                }
            }
        }
    }

    /// Demo / screenshot routing, e.g. `-screen run` | `pacer-set` | `pacer-run`
    /// | `trail` | `elevation` | `kmalert` | `paused` | `summary` | `trail-summary`.
    private func handleLaunchRoute() {
        #if DEBUG
        session.zones = store.zones
        session.pacerTarget = store.pacerTargetSecPerKm
        switch UserDefaults.standard.string(forKey: "screen") {
        case "run": session.debugFastForward(.quick, seconds: 2537)
        case "pacer-set": session.setupPacer()
        case "pacer-run": session.debugFastForward(.pacer, seconds: 1684)
        case "trail", "elevation": session.debugFastForward(.trail, seconds: 4500)
        case "kmalert": session.debugFastForward(.quick, seconds: 2593, keepAlert: true)
        case "paused": session.debugFastForward(.quick, seconds: 2537, paused: true)
        case "summary":
            session.debugFastForward(.quick, seconds: 2537)
            finishedRun = session.end()
        case "trail-summary":
            session.debugFastForward(.trail, seconds: 6728)
            finishedRun = session.end()
        default: break
        }
        #endif
    }

    private func start(_ type: RunType) {
        session.zones = store.zones
        session.kilometerAlertEnabled = store.kilometerAlert
        session.begin(type)
    }

    private func finish() {
        let run = session.end()
        finishedRun = run
        store.add(run)
    }
}
