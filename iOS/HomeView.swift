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
                // Zones are re-derived from Health on every launch. When they
                // actually moved, this is where the runner finds out — first
                // thing on the first screen, and gone with one tap.
                if let notice = store.zoneNotice {
                    NoticeCard(systemImage: "heart.text.square", text: notice,
                               action: { push(.hrZones) },
                               onDismiss: { store.zoneNotice = nil })
                        .padding(.bottom, 24)
                }

                if let race = store.race, !race.isPast {
                    if race.isToday { raceDayHeadline(race) } else { raceHeadline(race) }
                    Divider().overlay(Theme.hairline).padding(.vertical, 24)
                    weekBlock(headline: false)
                } else {
                    weekBlock(headline: true)
                    // A race that has been run used to vanish from here
                    // entirely — no result, and no offer of a next one, since
                    // the prompt below only appeared when there was no race at
                    // all. The runner was left with nothing but a week block.
                    if let race = store.race, race.isPast {
                        pastRaceRow(race)
                    } else if store.race == nil {
                        setupRaceRow
                    }
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
                // "RACE DAY" is what the day itself is called, and this is the
                // headline for every day that is not it — six weeks out it read
                // "RACE DAY · FREIBURG MARATHON" over "42 DAYS".
                Text("TARGET RACE · \(race.name.uppercased())").kicker(13, color: Theme.bright, tracking: 0.12)
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
            // The same number the Race screen calls ESTIMATION, under the same
            // word. It used to be `prediction.headline` — the slower of two
            // models, one of which no longer exists — so Home and Race could
            // print two different finishes for one race.
            if let estimate = store.raceEstimate {
                StatBlock(value: Format.clock(estimate.time), label: "ESTIMATION")
            }
        }
    }

    // MARK: - Week block

    @ViewBuilder
    private func weekBlock(headline: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("THIS WEEK").kicker(13, color: Theme.bright, tracking: 0.12)
            Spacer()
            // The goal is stated here and was only settable three taps away,
            // behind a screen that does not mention it. Same menu as Settings.
            WeeklyGoalMenu(goalKm: $store.weeklyGoalKm) {
                HStack(spacing: 5) {
                    Text("goal \(Int(store.weeklyGoalKm)) km")
                        .font(.stat(13, weight: .regular))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(Theme.muted)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
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

    private func pastRaceRow(_ race: Race) -> some View {
        Button { push(.race) } label: {
            GlassCard(cornerRadius: 20, padding: EdgeInsets(top: 16, leading: 22, bottom: 16, trailing: 22)) {
                HStack {
                    Text(race.daysSince == 0
                         ? "\(race.name) was today"
                         : "\(race.name) · \(Format.plural(race.daysSince, "day", "days")) ago")
                        .font(.sg(15)).foregroundStyle(Theme.bright)
                        .lineLimit(1)
                    Spacer()
                    Chevron()
                }
            }
            .padding(.top, 18)
        }
        .buttonStyle(.plain)
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

    /// The same row the Log draws, for the same reason a run has one name.
    ///
    /// This used to be a `RecentRow` of its own, and it disagreed with the Log
    /// about the same run in two ways. It coloured the pace below a fixed
    /// 5:10 /km — exactly the threshold the Log had already thrown out, because
    /// it means nothing without knowing the runner's level, so a slow runner
    /// never saw an accent and a fast one saw it on everything. And it printed
    /// `classification.label` for imported runs, which have no splits and no
    /// zones to classify from, so every one of them read "Easy" here and named
    /// its source over in the Log. `LogRowText` answers both questions once,
    /// and the store has already cached it.
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
                    Button { push(.runDetail(run)) } label: {
                        LogRow(text: store.logText(for: run,
                                                   prTag: store.benchmarkHolders[run.id]),
                               isFastestPaceOfMonth: store.fastestPaceOfMonthHolders.contains(run.id))
                    }
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
                        // A run without heart rate has no dominant zone, and
                        // "Z0" names a zone that does not exist.
                        CardStat(value: run.dominantZone > 0 ? "Z\(run.dominantZone)" : "–",
                                 label: "MOSTLY", accent: run.dominantZone > 0)
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

