import SwiftUI

@main
struct CurrimusApp: App {
    @StateObject private var store = RunStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FontLoader.registerAll()
        RunSync.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Theme.signal)
                // Small type scales (see Font.sg); this is the ceiling that
                // keeps the fixed numeric grids intact at the top end.
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                // Pick up runs other apps recorded on every foreground, so the
                // totals never lag behind what the user actually ran. Silent:
                // the permission sheet is asked for on the first-launch
                // screen, where there is room to say what it is for. Raising
                // it here meant a cold start opened onto a Health dialog
                // before the app had shown a single word about itself.
                .task { await store.refreshImportedRuns() }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await store.refreshImportedRuns() }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: RunStore
    @State private var tab: AppTab = RootView.initialTab
    @State private var forceEmpty = DebugFlags.forcesEmptyState
    @State private var icons = TabIconSet()

    var body: some View {
        Group {
            // `allRuns`, not `runs`: someone arriving with years of runs in
            // Apple Health has a log to show from the first launch. Gating on
            // the runs Currimus recorded itself kept them on the welcome
            // screen until they happened to run with this app once.
            if store.allRuns.isEmpty || forceEmpty {
                // In its own stack, so the first-launch screen can reach
                // Settings — a fresh install has no tab bar to get there with.
                TabRoot { FirstLaunchView() }
            } else {
                // Native iOS 26 TabView → real Liquid Glass tab bar with the
                // press-hold-and-drag-between-tabs interaction, using the
                // exact design icons as template images.
                TabView(selection: $tab) {
                    Tab(value: AppTab.home) {
                        TabRoot(initial: Self.debugHomePath(store)) { HomeView() }
                    } label: {
                        Label { Text("Home") } icon: { icons.home }
                    }
                    Tab(value: AppTab.log) {
                        TabRoot { LogView() }
                    } label: {
                        Label { Text("Log") } icon: { icons.log }
                    }
                    Tab(value: AppTab.progress) {
                        TabRoot { ProgressScreen() }
                    } label: {
                        Label { Text("Progress") } icon: { icons.progress }
                    }
                }
                .tint(Theme.signal)
            }
        }
        .foregroundStyle(Theme.ink)
        .onAppear(perform: applyDemoStateOverrides)
    }

    // MARK: - DEBUG screenshot / demo routing (release ignores it)

    private static var initialTab: AppTab {
        switch DebugFlags.tab {
        case "log": return .log
        case "progress": return .progress
        default: return .home
        }
    }

    private static func debugHomePath(_ store: RunStore) -> [Route] {
        switch DebugFlags.push {
        case "race": return [.race]
        case "raceSetup": return [.raceSetup]
        case "records": return [.records]
        case "settings": return [.settings]
        case "pacerDefaults": return [.pacerDefaults]
        case "hrZones": return [.hrZones]
        case "gpsAccuracy": return [.gpsAccuracy]
        case "detailRoad": return store.runs.first { !$0.isTrail }.map { [.runDetail($0)] } ?? []
        case "detailTrail": return store.runs.first { $0.isTrail }.map { [.runDetail($0)] } ?? []
        default: return []
        }
    }

    private func applyDemoStateOverrides() {
        // Health has no data in the simulator, so the derived zone state can
        // only be seen by injecting one.
        if DebugFlags.zones == "derived" {
            store.zones = HRZones(
                maxHR: 187, overrides: nil, restingHR: 48,
                derivation: HRDerivation(
                    maxSource: .measured,
                    maxDate: Calendar.current.date(byAdding: .day, value: -12, to: .now),
                    age: 38, restingHR: 48, restingSampleDays: 60
                )
            )
        }
        switch DebugFlags.home {
        case "norace": store.race = nil
        case "raceday":
            if var race = store.race {
                race.date = Calendar.current.startOfDay(for: .now); store.race = race
            }
        default: break
        }
    }
}

/// One tab's navigation stack — owns its path, injects `pushRoute`, and hides
/// the tab bar (with swipe-back restored) on pushed screens.
struct TabRoot<Root: View>: View {
    @State private var path: [Route]
    private let root: Root

    init(initial: [Route] = [], @ViewBuilder root: () -> Root) {
        _path = State(initialValue: initial)
        self.root = root()
    }

    var body: some View {
        NavigationStack(path: $path) {
            root
                .navigationDestination(for: Route.self) { route in
                    routeDestination(route)
                        .environment(\.pushRoute) { path.append($0) }
                        .toolbar(.hidden, for: .tabBar)
                }
        }
        .environment(\.pushRoute) { path.append($0) }
    }
}

@MainActor
@ViewBuilder
func routeDestination(_ route: Route) -> some View {
    switch route {
    case .race: RaceView()
    case .raceSetup: RaceSetupView()
    case .runDetail(let run): RunDetailView(run: run)
    case .records: RecordsView()
    case .settings: SettingsScreen()
    case .pacerDefaults: PacerDefaultsView()
    case .hrZones: HRZonesView()
    case .gpsAccuracy: GPSAccuracyView()
    }
}
