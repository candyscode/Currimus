import SwiftUI

/// The full run log, grouped by month, newest first. Every row is a
/// `NavigationLink` so the Siri Remote moves focus down the list and clicking
/// opens the run's detail. Reuses the store's `runsByMonth` and
/// `benchmarkHolders` — the same grouping and PR tags the iPhone shows.
struct TVLogView: View {
    @EnvironmentObject private var store: RunStore
    @State private var path: [Run] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                let holders = store.benchmarkHolders
                let fastestOfMonth = store.fastestPaceOfMonthHolders
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    header

                    ForEach(store.runsByMonth(.all), id: \.month) { group in
                        Text(monthLabel(group).uppercased())
                            .kicker(20, color: Theme.bright, tracking: 0.12)
                            .padding(.top, 40).padding(.bottom, 8).padding(.horizontal, 28)

                        ForEach(group.runs) { run in
                            NavigationLink(value: run) {
                                TVLogRow(run: run, prTag: holders[run.id],
                                         isFastestPaceOfMonth: fastestOfMonth.contains(run.id))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 52)
                .padding(.vertical, 60)
            }
            .navigationDestination(for: Run.self) { TVRunDetailView(run: $0) }
        }
        // DEBUG screenshot routing (`-push detailRoad` / `detailTrail`), the
        // same switch the iPhone's TabRoot honours. Release ignores it.
        .onAppear { path = Self.debugPath(store) }
    }

    private static func debugPath(_ store: RunStore) -> [Run] {
        switch DebugFlags.push {
        case "detailRoad": return store.allRuns.first { !$0.isTrail }.map { [$0] } ?? []
        case "detailTrail": return store.allRuns.first { $0.isTrail }.map { [$0] } ?? []
        default: return []
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Runs").font(.sg(56, weight: .semibold)).kerning(-1)
            Spacer()
            Text(verbatim: "\(Calendar.current.component(.year, from: .now)) · \(Int(store.yearKm)) km")
                .font(.stat(20, weight: .regular)).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 28)
    }

    private func monthLabel(_ group: (month: Date, runs: [Run])) -> String {
        let name = group.month.formatted(.dateTime.month(.wide))
        let km = group.runs.reduce(0) { $0 + $1.distanceKm }
        return "\(name) · \(Format.km(km, decimals: 1)) km"
    }
}

#Preview {
    FontLoader.registerAll()
    return TVLogView()
        .environmentObject(RunStore(seeded: true))
        .preferredColorScheme(.dark)
}
