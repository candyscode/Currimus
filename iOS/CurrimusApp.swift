import SwiftUI

@main
struct CurrimusApp: App {
    @StateObject private var store = RunStore(
        seeded: !UserDefaults.standard.bool(forKey: "empty")
    )

    init() {
        FontLoader.registerAll()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}

enum Tab: String, CaseIterable {
    case home = "Home"
    case log = "Log"
    case progress = "Progress"
}

/// The iPhone only reads — running happens on the watch.
struct RootView: View {
    @EnvironmentObject private var store: RunStore
    @State private var tab: Tab = .home
    @State private var homePath = NavigationPath()
    @State private var logPath = NavigationPath()
    @State private var progressPath = NavigationPath()

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if store.runs.isEmpty {
                FirstLaunchView()
            } else {
                VStack(spacing: 0) {
                    Group {
                        switch tab {
                        case .home: NavigationStack(path: $homePath) { HomeView() }
                        case .log: NavigationStack(path: $logPath) { LogView() }
                        case .progress: NavigationStack(path: $progressPath) { ProgressTabView() }
                        }
                    }
                    .frame(maxHeight: .infinity)

                    tabBar
                }
            }
        }
        .foregroundStyle(Theme.ink)
        .onAppear(perform: handleLaunchRoute)
    }

    /// Demo / screenshot routing: `-tab log`, `-push detail|settings|records|pacer`.
    private func handleLaunchRoute() {
        if let name = UserDefaults.standard.string(forKey: "tab"),
           let target = Tab(rawValue: name.capitalized) {
            tab = target
        }
        switch UserDefaults.standard.string(forKey: "push") {
        case "detail":
            if let run = store.lastRun {
                tab = .log
                logPath.append(run)
            }
        case "settings":
            tab = .home
            homePath.append("settings")
        case "pacer":
            tab = .home
            homePath.append("settings")
            homePath.append("pacer")
        case "records":
            tab = .progress
            progressPath.append("records")
        default:
            break
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { item in
                Button {
                    tab = item
                } label: {
                    Text(item.rawValue)
                        .font(.sg(13, weight: tab == item ? .semibold : .regular))
                        .foregroundStyle(tab == item ? Theme.ink : Theme.muted)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 6)
        .background(alignment: .top) {
            Theme.hairline.frame(height: 1)
        }
        .background(Theme.bg)
    }
}

/// First launch — runs start on your watch.
struct FirstLaunchView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CURRIMUS")
                .font(.sg(19, weight: .bold))
                .kerning(1.2)

            Spacer()

            VStack(alignment: .leading, spacing: 18) {
                (Text("Time.\nDistance.\nZone.\n")
                    + Text("Pace.").foregroundStyle(Theme.signal))
                    .font(.sg(40, weight: .semibold))
                    .lineSpacing(4)
                    .kerning(-0.8)
                Text("The four things that matter, on your wrist. Everything else stays out of the way.")
                    .font(.sg(15))
                    .foregroundStyle(Theme.muted)
                    .lineSpacing(4)
                    .frame(maxWidth: 300, alignment: .leading)
            }

            Spacer()

            VStack(spacing: 6) {
                Text("Runs start on your watch")
                    .font(.sg(14, weight: .semibold))
                Text("Open Currimus on your Apple Watch — your first run will appear here.")
                    .font(.sg(12))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 22)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.buttonBorder, lineWidth: 1))
        }
        .padding(28)
    }
}
