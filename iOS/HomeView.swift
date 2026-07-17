import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: RunStore

    private var weekDelta: String {
        guard store.lastWeekKmToDate > 0 else { return "" }
        let pct = Int(((store.weekKm - store.lastWeekKmToDate) / store.lastWeekKmToDate * 100).rounded())
        return "\(pct >= 0 ? "+" : "")\(pct)% vs last week"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("THIS WEEK").kicker(12)
                    Spacer()
                    NavigationLink(value: "settings") {
                        Text("Settings")
                            .font(.sg(13))
                            .foregroundStyle(Theme.muted)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Format.km(store.weekKm, decimals: 1))
                        .font(.stat(52))
                        .kerning(-1.5)
                    Text("km")
                        .font(.sg(17))
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Text(weekDelta)
                        .font(.stat(13))
                        .foregroundStyle(Theme.signal)
                }
                .padding(.top, 6)

                WeekBars(kmPerDay: store.weekByDay)
                    .padding(.top, 24)

                if let run = store.lastRun {
                    LastRunCard(run: run)
                        .padding(.top, 28)
                }
            }
            .padding(28)
        }
        .background(Theme.bg)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: String.self) { destination in
            switch destination {
            case "settings": SettingsView()
            case "pacer": PacerTargetView()
            case "records": RecordsView()
            default: EmptyView()
            }
        }
        .navigationDestination(for: Run.self) { RunDetailView(run: $0) }
    }
}

struct WeekBars: View {
    var kmPerDay: [Double]
    private let labels = ["M", "T", "W", "T", "F", "S", "S"]

    private var latestActive: Int? {
        kmPerDay.lastIndex(where: { $0 > 0 })
    }

    var body: some View {
        let maxKm = max(kmPerDay.max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(0..<7, id: \.self) { day in
                let ran = kmPerDay[day] > 0
                let isLatest = day == latestActive
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isLatest ? Theme.signal : (ran ? Theme.track : Theme.trackIdle))
                        .frame(height: ran ? max(kmPerDay[day] / maxKm * 64, 8) : 5)
                    Text(labels[day])
                        .font(.sg(11, weight: isLatest ? .semibold : .regular))
                        .foregroundStyle(isLatest ? Theme.ink : Theme.muted)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 92)
    }
}

struct LastRunCard: View {
    @EnvironmentObject private var store: RunStore
    var run: Run

    var body: some View {
        NavigationLink(value: run) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(run.name)
                        .font(.sg(14, weight: .semibold))
                    Spacer()
                    Text(run.date, format: .relative(presentation: .named))
                        .font(.sg(12))
                        .foregroundStyle(Theme.muted)
                }
                HStack(spacing: 26) {
                    CardStat(value: Format.km(run.distanceKm), label: "km")
                    CardStat(value: Format.pace(run.paceSecPerKm), label: "/km")
                    CardStat(value: "\(run.avgHR)", label: "avg hr")
                }
                .padding(.top, 16)
                ZoneHeatStrip(zoneSeconds: run.zoneSeconds, height: 6)
                    .padding(.top, 16)
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 22)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct CardStat: View {
    var value: String
    var label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.stat(22))
            Text(label)
                .font(.sg(11))
                .foregroundStyle(Theme.muted)
        }
    }
}
