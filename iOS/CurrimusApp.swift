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
    @State private var tab: Tab = .home
    @State private var path: [Route] = []
    @State private var forceEmpty = UserDefaults.standard.bool(forKey: "empty")

    var body: some View {
        Group {
            if store.runs.isEmpty || forceEmpty {
                FirstLaunchView()
            } else {
                tabbed
            }
        }
        .foregroundStyle(Theme.ink)
        .onAppear(perform: handleLaunchRoute)
    }

    /// DEBUG screenshot / demo routing (release builds ignore all of this).
    private func handleLaunchRoute() {
        #if DEBUG
        let d = UserDefaults.standard
        switch d.string(forKey: "tab") {
        case "log": tab = .log
        case "progress": tab = .progress
        default: break
        }
        switch d.string(forKey: "home") {
        case "norace": store.race = nil
        case "raceday":
            if var race = store.race {
                race.date = Calendar.current.startOfDay(for: .now); store.race = race
            }
        default: break
        }
        guard path.isEmpty else { return }
        switch d.string(forKey: "push") {
        case "race": path = [.race]
        case "raceSetup": path = [.raceSetup]
        case "records": path = [.records]
        case "settings": path = [.settings]
        case "pacerDefaults": path = [.pacerDefaults]
        case "hrZones": path = [.hrZones]
        case "detailRoad": if let r = store.runs.first(where: { !$0.isTrail }) { path = [.runDetail(r)] }
        case "detailTrail": if let r = store.runs.first(where: { $0.isTrail }) { path = [.runDetail(r)] }
        default: break
        }
        #endif
    }

    private var tabbed: some View {
        NavigationStack(path: $path) {
            root
                .navigationDestination(for: Route.self) { route in
                    destination(route)
                        .environment(\.pushRoute) { path.append($0) }
                }
        }
        .environment(\.pushRoute) { path.append($0) }
        .overlay(alignment: .bottom) {
            if path.isEmpty {
                GlassTabBar(tab: $tab)
                    .padding(.bottom, 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var root: some View {
        switch tab {
        case .home: HomeView()
        case .log: LogView()
        case .progress: ProgressScreen()
        }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
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
}
