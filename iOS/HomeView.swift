import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: RunStore
    @Environment(\.pushRoute) private var push

    var body: some View {
        TabScreen(topInset: 62) {
            HStack {
                Text("CURRIMUS").font(.sg(16, weight: .bold)).kerning(1.3)
                Spacer()
                GlassIconButton(systemImagePath: .settings) { push(.settings) }
            }
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                if let race = store.race, !race.isPast {
                    if race.isToday { raceDayHeadline(race) } else { raceHeadline(race) }
                    Divider().overlay(Theme.hairline).padding(.vertical, 24)
                    weekBlock(headline: false)
                } else {
                    weekBlock(headline: true)
                    if store.race == nil { setupRaceRow }
                }

                if let last = store.lastRun {
                    RunSummaryCard(run: last).padding(.top, 26)
                }

                recent
            }
        }
    }

    // MARK: - Race headline (countdown)

    private func raceHeadline(_ race: Race) -> some View {
        Button { push(.race) } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text("RACE DAY · \(race.name.uppercased())").kicker(13, color: Theme.bright, tracking: 0.12)
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text("\(race.daysUntil())")
                        .font(.stat(118)).kerning(-5.9)
                    Text("DAYS").font(.sg(21, weight: .semibold)).kerning(2)
                        .foregroundStyle(Theme.signal)
                    Spacer()
                    Chevron(size: 22).alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                }
                .padding(.top, 2)
                raceStats(race).padding(.top, 16)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func raceDayHeadline(_ race: Race) -> some View {
        Button { push(.race) } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text("RACE DAY · \(race.name.uppercased())").kicker(13, color: Theme.bright, tracking: 0.12)
                Text("Today\(Text(verbatim: ".").foregroundStyle(Theme.signal))")
                    .font(.stat(96)).kerning(-4.8)
                    .padding(.top, 6)
                raceStats(race, planLabel: true).padding(.top, 24)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func raceStats(_ race: Race, planLabel: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 28) {
            StatBlock(value: Format.clock(race.goalTime), label: "GOAL")
            StatBlock(value: Format.pace(race.requiredPace), label: planLabel ? "PLAN /KM" : "NEEDS /KM", accent: true)
            if let prediction = store.prediction {
                StatBlock(value: Format.clock(prediction.time), label: "PREDICTED")
            }
        }
    }

    // MARK: - Week block

    @ViewBuilder
    private func weekBlock(headline: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("THIS WEEK").kicker(13, color: Theme.bright, tracking: 0.12)
            Spacer()
            Text("goal \(Int(store.weeklyGoalKm)) km").font(.stat(13, weight: .regular)).foregroundStyle(Theme.muted)
        }
        HStack(alignment: .firstTextBaseline, spacing: headline ? 12 : 10) {
            Text(Format.km(store.weekKm, decimals: 1))
                .font(.stat(headline ? 96 : 52)).kerning(headline ? -4.8 : -2)
            Text("km").font(.sg(headline ? 20 : 17)).foregroundStyle(Theme.bright)
            Spacer()
            Text("\(Int((store.weekGoalFraction * 100).rounded()))%")
                .font(.stat(headline ? 16 : 14)).foregroundStyle(Theme.signal)
        }
        .padding(.top, headline ? 4 : 6)
        WeekBars(kmPerDay: store.weekByDay).padding(.top, headline ? 24 : 20)
    }

    private var setupRaceRow: some View {
        Button { push(.raceSetup) } label: {
            GlassCard(cornerRadius: 20, padding: EdgeInsets(top: 16, leading: 22, bottom: 16, trailing: 22)) {
                HStack {
                    Text("Training toward a race? Set it up")
                        .font(.sg(15)).foregroundStyle(Theme.bright)
                    Spacer()
                    Chevron()
                }
            }
            .padding(.top, 18)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recent

    private var recent: some View {
        // `allRuns`, matching the card above: `dropFirst` is meant to skip the
        // run that card is already showing, and that run is `allRuns.first`.
        // Reading `runs` here dropped the newest run Currimus recorded instead
        // — so whenever the freshest run was an imported one, this list
        // repeated the card and swallowed a run of its own.
        let rows = Array(store.allRuns.dropFirst().prefix(2))
        return VStack(alignment: .leading, spacing: 0) {
            if !rows.isEmpty {
                Text("RECENT").kicker(13, color: Theme.bright, tracking: 0.12).padding(.top, 26)
                ForEach(rows) { run in
                    Button { push(.runDetail(run)) } label: { RecentRow(run: run) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Shared pieces

struct StatBlock: View {
    var value: String
    var label: String
    var accent: Bool = false
    var size: CGFloat = 21

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.stat(size)).foregroundStyle(accent ? Theme.signal : Theme.ink).lineLimit(1)
            Text(label).kicker(13, color: Theme.bright, tracking: 0.12)
        }
    }
}

struct RunSummaryCard: View {
    @Environment(\.pushRoute) private var push
    var run: Run

    var body: some View {
        Button { push(.runDetail(run)) } label: {
            GlassCard {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(run.name).font(.sg(15, weight: .semibold))
                        Spacer()
                        Text(run.date, format: .relative(presentation: .named))
                            .font(.sg(13)).foregroundStyle(Theme.muted)
                    }
                    HStack(spacing: 26) {
                        CardStat(value: Format.km(run.distanceKm), label: "KM")
                        CardStat(value: Format.pace(run.paceSecPerKm), label: "/KM")
                        CardStat(value: "Z\(run.dominantZone)", label: "MOSTLY", accent: true)
                    }
                    .padding(.top, 14)
                    ZoneHeatStrip(zoneSeconds: run.zoneSeconds, height: 6).padding(.top, 16)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct CardStat: View {
    var value: String
    var label: String
    var accent: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.stat(24)).foregroundStyle(accent ? Theme.signal : Theme.ink)
            Text(label).kicker(12, color: Theme.bright, tracking: 0.1)
        }
    }
}

/// A compact recent/log row: date · name/detail · pace, full-width tap target.
struct RecentRow: View {
    var run: Run

    var body: some View {
        HStack(spacing: 14) {
            Text(run.date.formatted(.dateTime.weekday(.abbreviated)).uppercased()
                 + "\n" + run.date.formatted(.dateTime.day(.twoDigits).month(.twoDigits)))
                .font(.sg(12)).foregroundStyle(Theme.muted).lineSpacing(3)
                .frame(width: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(Format.km(run.distanceKm)) km").font(.stat(17))
                Text(run.classification.label).font(.sg(13)).foregroundStyle(Theme.bright)
            }
            Spacer()
            Text(Format.pace(run.paceSecPerKm)).font(.stat(17))
                .foregroundStyle(run.paceSecPerKm < 310 ? Theme.signal : Theme.ink)
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Theme.hairline.frame(height: 1) }
        .contentShape(Rectangle())
    }
}
