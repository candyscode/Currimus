import SwiftUI

@main
struct CurrimusWatchApp: App {
    @StateObject private var store = RunStore()

    init() {
        FontLoader.registerAll()
        RunSync.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(store)
                // Keeps the shared store — and with it the complications — in
                // step with runs other apps recorded. Silent: the Health sheet
                // belongs at the start of a run, not over one already running.
                .task { await store.refreshImportedRuns() }
        }
    }
}

struct WatchRootView: View {
    @EnvironmentObject private var store: RunStore
    @StateObject private var session = RunSession()
    @State private var finishedRun: Run?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                // The top safe area stays — the system clock owns that line
                // (watchOS 10 rule); sides and bottom are full-bleed like the
                // design frames. Screen captions ride the top bar beside the
                // clock via .topBarCaption.
                content
                    .ignoresSafeArea(edges: [.horizontal, .bottom])
                    // One injection point for the whole run UI, overlays
                    // included — they have no session to read it from.
                    .environment(\.alwaysOnReduced, store.alwaysOnReduced)
            }
            .foregroundStyle(Theme.ink)
        }
        // The run scaffold and the summary scroller pick this up, so a
        // degraded recording shows on every screen without each one wiring it.
        .environment(\.recordingIssue, session.issues.first)
        .environment(\.runNotSaved, finishedRun.map { !$0.hasUsableDistance } ?? false)
        .onAppear(perform: handleLaunchRoute)
    }

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .idle:
            WatchHomeView(
                onStart: { start(.quick) },
                onTrail: { start(.trail) },
                onPacer: {
                    // Preload the iPhone's pacer defaults (pace + distance).
                    session.pacerTarget = store.pacerTargetSecPerKm
                    session.pacerDistanceKm = store.pacerDefaultDistanceKm
                    session.setupPacer()
                }
            )
        case .pacerPace:
            // Cancel from the first step drops back to Home — there was no way
            // out of pacer setup before except to start a run and end it.
            PacerPaceView(session: session, onCancel: { session.reset() }) {
                store.pacerTargetSecPerKm = session.pacerTarget
                session.confirmPacerPace()
            }
        case .pacerDistance:
            // Back returns to the pace step with the chosen pace intact.
            PacerDistanceView(session: session, onBack: { session.setupPacer() }) {
                start(.pacer)
            }
        case .preparing:
            PreparingView()
        case .blocked(let issue):
            RecordingBlockedView(issue: issue) { session.reset() }
        case .countdown(let n):
            CountdownView(count: n) { session.skipCountdown() }
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
                switch run.type {
                case .pacer:
                    PacerSummaryView(
                        run: run,
                        target: session.pacerTarget,
                        targetDistanceKm: session.pacerDistanceKm,
                        onDone: done
                    )
                case .trail:
                    TrailSummaryView(
                        run: run,
                        // The saved run owns its samples — the live session
                        // may already have been reset.
                        profile: RoutePoints.normalized(run.altitudeSamples ?? session.altitudeProfile),
                        onDone: done
                    )
                case .quick:
                    SummaryView(run: run, onDone: done)
                }
            }
        }
    }

    private func start(_ type: RunType) {
        session.zones = store.zones
        session.kilometerAlertEnabled = store.kilometerAlert
        session.countdownEnabled = store.countdownEnabled
        session.gpsAccuracy = store.gpsAccuracy
        session.begin(type)
    }

    private func finish() {
        let run = session.end()
        finishedRun = run
        // A recording that never measured a distance is a failed recording,
        // not a run. Showing the user what happened is honest; filing a
        // 0.00 km "Easy run" in the log is not.
        if run.hasUsableDistance { store.add(run) }
    }

    private func done() {
        finishedRun = nil
        session.reset()
    }

    /// Demo / screenshot routing (DEBUG builds only), e.g. `-screen run`.
    private func handleLaunchRoute() {
        #if DEBUG
        session.zones = store.zones
        session.pacerTarget = store.pacerTargetSecPerKm
        switch DebugFlags.screen {
        case "run": session.debugFastForward(.quick, seconds: 2537)
        // Long run: five-glyph KM value ("16.xx") — the grid's width edge.
        case "run-long": session.debugFastForward(.quick, seconds: 5537)
        case "pacer-set": session.setupPacer()
        case "pacer-distance":
            session.setupPacer()
            session.confirmPacerPace()
        case "pacer-run":
            session.pacerDistanceKm = 10
            session.debugFastForward(.pacer, seconds: 1684)
        case "pacer-run-nodist":
            session.pacerDistanceKm = nil
            session.debugFastForward(.pacer, seconds: 1684)
        case "pacer-summary":
            session.pacerDistanceKm = 10
            session.debugFastForward(.pacer, seconds: 3146)
            finishedRun = session.end()
        case "trail", "elevation", "elevation-noroute":
            session.debugFastForward(.trail, seconds: 4500)
        // Deterministic no-route profiles — the Y axis measured against known
        // numbers rather than a live simulation.
        // Extremes deliberately interior, so neither lands under the progress
        // dot and both ends of the curve stay measurable.
        case "elevation-known":
            session.debugFastForward(.trail, seconds: 4500)
            session.debugSetAltitudeProfile([760, 870, 700, 820, 780, 840, 730, 800])
        case "elevation-flat":
            session.debugFastForward(.trail, seconds: 4500)
            session.debugSetAltitudeProfile([706, 708, 705, 707.5, 706.2, 707, 705.5, 706.8])
        case "elevation-zero":
            session.debugFastForward(.trail, seconds: 4500)
            session.debugSetAltitudeProfile(Array(repeating: 705, count: 8))
        // Zone-pointer positions matching the design exploration.
        case "zone1": session.debugFastForward(.quick, seconds: 372); session.debugForceHR(104)   // Z1 · 45%
        case "zone2low": session.debugFastForward(.quick, seconds: 1100); session.debugForceHR(117) // Z2 · 12%
        case "zone2high": session.debugFastForward(.quick, seconds: 1480); session.debugForceHR(131) // Z2 · 88%
        case "zone5": session.debugFastForward(.quick, seconds: 2702); session.debugForceHR(183)     // Z5 · 62%
        case "trail-early":
            session.debugFastForward(.trail, seconds: 10)
        case "summary-empty":
            // The degenerate case a real recording can still produce once the
            // gate is passed: Health allowed the workout but refused the
            // distance read, so nothing ever moved. Not filed in the log.
            finishedRun = Run(
                date: .now, type: .quick, name: "Run",
                distanceKm: 0, duration: 19, avgHR: 0,
                splits: [], zoneSeconds: [0, 0, 0, 0, 0]
            )
            session.debugShowSummary()
        // The refusal screen — a run that never starts.
        case "blocked-health":
            session.debugBlock(.healthDenied)
        case "blocked-workout":
            session.debugBlock(.workoutFailed)
        case "blocked-unavailable":
            session.debugBlock(.healthUnavailable)
        // Degraded-recording banners, live and on the summary.
        // Health allowed the workout but withheld the distance read — the one
        // failure the gate cannot catch up front.
        case "issue-nodistance":
            session.debugFastForward(.quick, seconds: 2537)
            session.debugRaiseIssue(.noDistance)
        case "issue-location":
            session.debugFastForward(.trail, seconds: 4500)
            session.debugRaiseIssue(.locationDenied)
        case "issue-summary":
            session.debugFastForward(.quick, seconds: 2537)
            finishedRun = session.end()
            session.debugRaiseIssue(.noDistance)
        case "kmalert": session.debugFastForward(.quick, seconds: 2593, keepAlert: true)
        case "paused": session.debugFastForward(.quick, seconds: 2537, paused: true)
        case "summary":
            session.debugFastForward(.quick, seconds: 2537)
            finishedRun = session.end()
        case "trail-summary":
            session.debugFastForward(.trail, seconds: 6728)
            finishedRun = session.end()
        // Flat-profile edge cases the Y axis has to survive: a 3 m river-path
        // run, and a treadmill-flat one with no span at all.
        case "trail-summary-flat":
            finishedRun = debugFlatTrail(
                samples: [705, 705.4, 706, 705.6, 706.5, 707, 706.8, 707.6, 708])
            session.debugShowSummary()
        case "trail-summary-zero":
            finishedRun = debugFlatTrail(samples: Array(repeating: 705, count: 9))
            session.debugShowSummary()
        default: break
        }
        #endif
    }

    #if DEBUG
    private func debugFlatTrail(samples: [Double]) -> Run {
        let climb = zip(samples, samples.dropFirst())
            .reduce(0.0) { $0 + max($1.1 - $1.0, 0) }
        return Run(
            date: .now, type: .trail, name: "Trail",
            distanceKm: 0.1, duration: 30, avgHR: 121,
            splits: [], zoneSeconds: [12, 18, 0, 0, 0],
            climbMeters: climb, descentMeters: 0,
            highPointMeters: samples.max(), altitudeSamples: samples
        )
    }
    #endif
}
