import SwiftUI

@main
struct CurrimusApp: App {
    @StateObject private var store = RunStore()

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
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: RunStore
    @State private var tab: AppTab = RootView.initialTab
    @State private var forceEmpty = UserDefaults.standard.bool(forKey: "empty")
    @State private var icons = TabIconSet()

    var body: some View {
        Group {
            if store.runs.isEmpty || forceEmpty {
                FirstLaunchView()
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
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "tab") {
        case "log": return .log
        case "progress": return .progress
        default: return .home
        }
        #else
        return .home
        #endif
    }

    private static func debugHomePath(_ store: RunStore) -> [Route] {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "push") {
        case "race": return [.race]
        case "raceSetup": return [.raceSetup]
        case "records": return [.records]
        case "settings": return [.settings]
        case "pacerDefaults": return [.pacerDefaults]
        case "hrZones": return [.hrZones]
        case "detailRoad": return store.runs.first { !$0.isTrail }.map { [.runDetail($0)] } ?? []
        case "detailTrail": return store.runs.first { $0.isTrail }.map { [.runDetail($0)] } ?? []
        default: return []
        }
        #else
        return []
        #endif
    }

    private func applyDemoStateOverrides() {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "home") {
        case "norace": store.race = nil
        case "raceday":
            if var race = store.race {
                race.date = Calendar.current.startOfDay(for: .now); store.race = race
            }
        default: break
        }
        #endif
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
    }
}
