import SwiftUI

/// The month ticks under a trend chart, at the position of the first week
/// that falls in each month.
///
/// This used to be the literal `["Apr", "May", "Jun", "Jul"]`, straight out
/// of the design — correct in the month the design was drawn, and wrong in
/// every month since. It sat under both charts, so the axis and the line
/// above it described different periods.
struct TrendMonthAxis: View {
    /// A weekly chart: one tick at the first week of each month it covers.
    var weeks: Int?
    /// A monthly chart: the months themselves, oldest first. Twelve labels in
    /// a row would collide, so every third one is drawn.
    var months: [Date]?
    /// Enough for an abbreviated month at 12 pt, in any locale that keeps
    /// them to three or four characters.
    private let labelWidth: CGFloat = 38

    init(weeks: Int) { self.weeks = weeks }
    init(months: [Date]) { self.months = months }

    private var ticks: [(label: String, fraction: Double)] {
        if let months { return monthTicks(months) }
        return weekTicks(weeks ?? 0)
    }

    /// Four labels at 0, ⅓, ⅔ and 1 of the width — the oldest month, the
    /// newest, and two evenly between them.
    ///
    /// It used to take every third month from the oldest and then force the
    /// last one in regardless. Over twelve months that put labels at 0, 3, 6, 9
    /// and 11, so the final gap was two months wide where every other one was
    /// three (CUR-45). Stepping back from the end instead gives equal gaps but
    /// drops the oldest month — and the headline right above names that same
    /// month ("since <the first month of the window that carries a value>"), so
    /// an axis starting two months later would contradict it. So the
    /// *positions* are fixed and even, and each label is the month nearest that
    /// position: eleven months do not divide into three equal whole steps, and
    /// half a month of rounding is invisible where a whole month of unevenness
    /// was not.
    private func monthTicks(_ months: [Date]) -> [(String, Double)] {
        guard months.count > 1 else { return [] }
        let last = Double(months.count - 1)
        let ticks = min(months.count, 4)
        return (0..<ticks).map { k in
            let fraction = Double(k) / Double(ticks - 1)
            let index = Int((fraction * last).rounded())
            return (months[index].formatted(.dateTime.month(.abbreviated)), fraction)
        }
    }

    /// One label per month the window covers, spread evenly across the axis.
    ///
    /// The labels used to sit where each month actually began, which is
    /// truthful and looks broken: months are four or five weeks long, so over
    /// twelve weeks May→Jun came out half the width of Jul→Aug (CUR-45). Even
    /// spacing costs the tick its exact position — it now says *which* months
    /// the line covers rather than where each one starts — which is what a
    /// chart headed "LAST 12 WEEKS" is asking of it anyway.
    private func weekTicks(_ weeks: Int) -> [(String, Double)] {
        let calendar = Calendar.runWeek
        var seenMonths: Set<Int> = []
        var labels: [String] = []
        for offset in (0..<weeks).reversed() {
            guard let week = calendar.date(byAdding: .weekOfYear, value: -offset, to: .now)
            else { continue }
            let month = calendar.component(.month, from: week)
            guard seenMonths.insert(month).inserted else { continue }
            labels.append(week.formatted(.dateTime.month(.abbreviated)))
        }
        return Self.spacedEvenly(labels)
    }

    /// Labels at 0, 1/(n-1) … 1. A single label sits at the start rather than
    /// dividing by zero.
    static func spacedEvenly(_ labels: [String]) -> [(String, Double)] {
        guard labels.count > 1 else { return labels.map { ($0, 0) } }
        return labels.enumerated().map { index, label in
            (label, Double(index) / Double(labels.count - 1))
        }
    }

    var body: some View {
        let ticks = ticks
        return GeometryReader { proxy in
            // Offset rather than `position`, so the first and last labels stay
            // inside the chart's width instead of hanging off both ends.
            ForEach(Array(ticks.enumerated()), id: \.offset) { _, tick in
                Text(tick.label)
                    .font(.sg(12)).foregroundStyle(Theme.muted)
                    .frame(width: labelWidth, alignment: .leading)
                    .offset(x: tick.fraction * max(proxy.size.width - labelWidth, 0))
            }
        }
        .frame(height: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Covering \(ticks.map(\.label).joined(separator: " to "))")
    }
}

struct ProgressScreen: View {
    @EnvironmentObject private var store: RunStore
    @Environment(\.pushRoute) private var push
    @State private var view: RunStore.LogFilter = .road   // .road or .trail
    @State private var explaining: Explanation?

    var body: some View {
        TabScreen(topInset: 8) { EmptyView() } content: {
            VStack(alignment: .leading, spacing: 0) {
                Text("Progress").font(.sg(38, weight: .semibold)).kerning(-0.8).padding(.top, 6)

                // No trail runs means the Trail half of this screen is a set
                // of empty charts and a 0 m/h headline. Offering the tab at
                // all invites the user to go and find that out.
                if hasTrailRuns {
                    SegmentChips(options: [(.road, "Road"), (.trail, "Trail")], selection: $view)
                        .frame(maxWidth: 180, alignment: .leading)
                        .padding(.top, 18)
                }

                if view == .road || !hasTrailRuns { roadContent } else { trailContent }
            }
        }
        .explanationSheet($explaining)
    }

    // MARK: - Road

    private var roadContent: some View {
        let series = RunAnalytics.weeklyAvgPace(runs: store.allRuns, weeks: 12, roadOnly: true)
        let road12 = last12WeekRoad
        let avg = road12.km > 0 ? road12.time / road12.km : 0
        // Smoothed at both ends, like the zone-2 block below already was.
        //
        // This used to be newest week minus oldest week — two single data
        // points on a line that wanders ten seconds a week on its own, so the
        // headline swung on whichever two weeks happened to sit at the edges.
        // Two charts on one screen were answering the same question two
        // different ways, and this was the one that answered it with noise.
        let change = RunAnalytics.trendChange(series)
        return VStack(alignment: .leading, spacing: 0) {
            Text("AVG PACE · LAST 12 WEEKS").kicker(13, color: Theme.bright, tracking: 0.12).padding(.top, 24)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Format.pace(avg)).font(.stat(64)).kerning(-2.6)
                Text("/km").font(.sg(16)).foregroundStyle(Theme.bright)
                Spacer()
                if let change {
                    // Exactly no change is not an improvement, and "+0:00"
                    // is not a sentence anyone reads as "the same".
                    trendDelta(Int(change.rounded()) == 0 ? String(localized: "unchanged")
                                                          : Format.paceDelta(change),
                               improved: change < 0, since: firstWeekMonth(of: series))
                }
            }
            .padding(.top, 8)
            TrendChart(values: series, headroom: 8, lowerIsBetter: true,
                       accessibilityTitle: "Average pace per week, last 12 weeks",
                       format: { Format.pace($0) },
                       describe: { "\(Format.pace($0)) per kilometre" })
                .padding(.top, 18)
            monthAxis.padding(.top, 4)

            divider
            zoneTwoBlock

            divider
            driftRow

            divider
            Text("MONTHLY KM").kicker(13, color: Theme.bright, tracking: 0.12).padding(.bottom, 14)
            MonthBars(items: store.monthlyTotals(count: 6).map { (shortMonth($0.month), $0.km) },
                      unit: "km") { "\(Int($0))" }

            recordsCard(title: "Records", value: fiveKSummary)
        }
    }

    /// Twelve months of easy running, on its own axis.
    ///
    /// An overall average mixes tempo, intervals and easy running together, so
    /// it moves with what the block happened to contain rather than with
    /// fitness. Zone 2 pace does not: same heart rate, same effort, and a line
    /// that falls means the aerobic base is growing.
    ///
    /// Months, not weeks: this moves over a training block, and a month
    /// gathers enough easy running that one bad Tuesday is not a data point.
    @ViewBuilder
    private var zoneTwoBlock: some View {
        let months = RunAnalytics.monthlyZonePace(runs: store.allRuns, zone: 2,
                                                  zones: store.zones, months: 12)
        let series = months.map(\.pace)
        // Only months that produced a pace: one with a few hundred metres in
        // zone 2 has no pace to contribute but would still add its distance to
        // the denominator, tilting the headline fast.
        let counted = months.filter { $0.pace != nil }
        let km = counted.reduce(0) { $0 + $1.km }
        let seconds = counted.reduce(0.0) { $0 + ($1.pace ?? 0) * $1.km }
        // Time over distance across the whole window — the same arithmetic as
        // the overall pace above, so the two numbers can be read against each
        // other. It used to be the mean of the monthly means, which let a
        // month with one short run weigh as much as a month with twenty.
        let average = km > 0 ? seconds / km : 0
        let change = RunAnalytics.trendChange(series)

        Text("PACE IN ZONE 2 · LAST 12 MONTHS").kicker(13, color: Theme.bright, tracking: 0.12)
        if months.filter({ $0.pace != nil }).count >= 2 {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Format.pace(average)).font(.stat(40)).kerning(-1.6)
                Text("/km").font(.sg(15)).foregroundStyle(Theme.bright)
                Spacer()
                if let change {
                    // The first month that actually carries a point — the
                    // window may open months before the running does.
                    trendDelta(Format.paceDelta(change), improved: change <= 0,
                               since: counted.first?.month)
                }
            }
            .padding(.top, 6)
            TrendChart(values: series, headroom: 8, lowerIsBetter: true,
                       accessibilityTitle: "Average pace in zone 2 per month, last 12 months",
                       period: "months",
                       format: { Format.pace($0) },
                       describe: { "\(Format.pace($0)) per kilometre" })
                .padding(.top, 14)
            TrendMonthAxis(months: months.map(\.month)).padding(.top, 4)
            zoneTwoFootnote(months)
        } else {
            // A month or two of easy running is a data point, not a trend, and
            // a near-empty chart reads as a fault rather than as a log that
            // has not filled up yet.
            Text("Appears once a couple of months carry runs spent in zone 2. Runs from other apps count too.")
                .font(.sg(13)).foregroundStyle(Theme.muted).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
    }

    /// What the line rests on. A pace drawn from three easy runs and one drawn
    /// from forty look identical on a chart, and they are not the same claim.
    private func zoneTwoFootnote(_ months: [RunAnalytics.ZoneMonth]) -> some View {
        let runs = months.reduce(0) { $0 + $1.runs }
        let km = months.reduce(0) { $0 + $1.km }
        let unmeasured = months.reduce(0) { $0 + $1.unmeasured }
        let base = String(localized: "\(Format.plural(runs, "run", "runs")) · \(Format.km(km, decimals: 0)) km in zone 2")
        // Every point on this line is measured. Runs that cannot be — no GPS
        // track, or no heart-rate trace to pair it with — are left out rather
        // than estimated, and saying how many keeps that from looking like
        // runs going missing.
        return HStack(spacing: 2) {
            Text(unmeasured > 0
                 ? base + String(localized: " · \(unmeasured) not measured")
                 : base)
                .font(.sg(13)).foregroundStyle(Theme.muted).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            if unmeasured > 0 {
                InfoButton(label: "the unmeasured runs") {
                    explaining = Explanation(
                        title: String(localized: "Runs left out"),
                        body: String(localized: "\(Format.plural(unmeasured, "run", "runs")) spent time in zone 2 but could not be measured exactly — no heart-rate trace, or nothing in Health saying how the distance came. They are left out of the line rather than estimated onto it, and counted here instead, so the chart cannot quietly shrink without saying why."))
                }
                .padding(.leading, -6)
            }
        }
        .padding(.top, 10)
    }

    /// The card teases the 5 K record; without one it must not read "— 5K",
    /// which looks like a rendering fault rather than an empty log.
    private var fiveKSummary: String {
        guard let record = store.record(.fiveK), !record.isUnset else {
            return String(localized: "Nothing set yet")
        }
        return "\(record.value) 5K"
    }

    private var driftRow: some View {
        let reference = RunAnalytics.referencePace(runs: store.allRuns)
        let drift = reference.flatMap {
            RunAnalytics.hrAtPace(runs: store.allRuns, referencePaceSec: $0)
        }
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                // The pace comes from the runner's own easy runs, so the
                // heading names theirs instead of a number this app picked.
                Text(reference.map { "Heart rate at \(Format.pace($0)) /km" }
                     ?? "Heart rate at your steady pace")
                    .font(.sg(16))
                // The subtitle carries the empty state, says where the pace
                // came from, and — this is the part that was wrong — reads the
                // direction off the number instead of claiming an improvement
                // whichever way it went.
                Text(driftSubtitle(drift))
                    .font(.sg(13)).foregroundStyle(Theme.muted).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let drift {
                // Signal marks an improvement and nothing else, here as
                // everywhere else on this screen.
                let delta = Text(drift.delta <= 0 ? "\(drift.delta)" : "+\(drift.delta)")
                    .font(.stat(14))
                    .foregroundStyle(drift.delta <= 0 ? Theme.signal : Theme.bright)
                Text("\(drift.avg) \(delta)").font(.stat(26))
            }
        }
    }

    /// Where the number comes from, and which way it points.
    ///
    /// It used to read "Same effort, less work" in every case, including a
    /// heart rate that had gone *up* — which is the one reading a runner
    /// actually needs to notice.
    private func driftSubtitle(_ drift: (avg: Int, delta: Int)?) -> String {
        guard let drift else {
            return String(localized: "Your own median easy pace. Appears once a few easy runs sit near it.")
        }
        let median = String(localized: "Your own median easy pace, across the runs that sat near it.")
        if drift.delta < 0 {
            return median + String(localized: " Same pace, \(-drift.delta) bpm lower than it used to be.")
        }
        if drift.delta > 0 {
            return median + String(localized: " Same pace, \(drift.delta) bpm higher than it used to be. Heat, fatigue or a hard block will do that.")
        }
        return median + String(localized: " Same pace, same heart rate.")
    }

    // MARK: - Trail

    private var trailContent: some View {
        let climbSeries = RunAnalytics.weeklyClimbRate(runs: store.allRuns, weeks: 12)
        // Total climb over total hours, not the mean of the weekly rates.
        //
        // Averaging the rates let a week with one short outing weigh as much as
        // a week with four — the same mistake `gradeAdjustedSummary` argues
        // against a few functions away, and the same fix: the aggregate is the
        // sum over the sum.
        let avgRate = trail12WeekClimbRate
        let rateDelta = RunAnalytics.trendChange(climbSeries)
        return VStack(alignment: .leading, spacing: 0) {
            Text("CLIMB RATE · LAST 12 WEEKS").kicker(13, color: Theme.bright, tracking: 0.12).padding(.top, 24)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(Int(avgRate))").font(.stat(64)).kerning(-2.6)
                Text("m/h").font(.sg(16)).foregroundStyle(Theme.bright)
                Spacer()
                if let rateDelta {
                    // More metres per hour is the improvement here, so the
                    // sense of "better" is the opposite way round to pace.
                    trendDelta(Int(rateDelta) == 0
                               ? String(localized: "unchanged")
                               : "\(rateDelta >= 0 ? "+" : "−")\(Int(abs(rateDelta)))",
                               improved: rateDelta > 0, since: firstWeekMonth(of: climbSeries))
                }
            }
            .padding(.top, 8)
            TrendChart(values: climbSeries, headroom: 40, lowerIsBetter: false,
                       accessibilityTitle: "Climb rate per week, last 12 weeks",
                       format: { "\(Int($0))" },
                       describe: { "\(Int($0)) metres per hour" })
                .padding(.top, 18)
            monthAxis.padding(.top, 4)

            divider
            gapRow

            divider
            Text("MONTHLY CLIMB · M").kicker(13, color: Theme.bright, tracking: 0.12).padding(.bottom, 14)
            MonthBars(items: store.monthlyClimb(count: 6).map { (shortMonth($0.month), $0.climb) },
                      unit: "metres of climb") { climb in
                climb >= 1000 ? String(format: "%.1fk", climb / 1000) : "\(Int(climb))"
            }
            // The chart above this one is trail-only; these bars are not, and
            // the difference is worth a line rather than a guess.
            Text("Every metre climbed counts here, on trails and on the road — including runs another app recorded, where it saved the elevation. The climb rate above counts trail runs only.")
                .font(.sg(13)).foregroundStyle(Theme.muted).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            recordsCard(title: "Most climb", value: (store.mostClimbRun?.climbMeters).map {
                $0 > 0 ? "\(Int($0)) m" : String(localized: "Nothing set yet")
            } ?? String(localized: "Nothing set yet"))
        }
    }

    /// How the flat-equivalent pace was arrived at — and it is not always the
    /// same way, which is the part worth saying.
    private var gradeAdjustedExplanation: String {
        let trail = store.filteredRuns(.trail)
        let measured = trail.filter { RunAnalytics.hasMeasuredGradeAdjustment($0) }.count
        let base = String(localized: "Grade-adjusted pace is what your climbing would have cost you on the flat: every stretch of the run is converted using the energy a runner actually spends at that gradient, measured by \(Source.minetti.link) from −45 % to +45 %.")
        if measured == trail.count {
            return base
        }
        if measured == 0 {
            // No tracks at all: the rule of thumb is all there is, and it must
            // not be presented as the model above.
            return base + String(localized: " None of your trail runs carries a GPS track yet, so these use Currimus' own rule of thumb instead — roughly 0.4 s of the run's time attributed to each metre climbed, and less than half of that given back on the way down. Rebuild from Health in Settings to replace it with the real thing.")
        }
        return base + String(localized: " \(Format.plural(trail.count - measured, "run", "runs")) here has no GPS track, so it falls back to Currimus' own rule of thumb — roughly 0.4 s per metre climbed. Rebuild from Health in Settings to replace it.")
    }

    private var gapRow: some View {
        let summary = RunAnalytics.gradeAdjustedSummary(runs: store.filteredRuns(.trail))
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 2) {
                    Text("Grade-adjusted pace").font(.sg(16))
                    InfoButton(label: "grade-adjusted pace") {
                        explaining = Explanation(title: String(localized: "Grade-adjusted pace"),
                                                 body: gradeAdjustedExplanation)
                    }
                    .padding(.leading, -6)
                }
                Text(summary == nil
                     ? "Appears after a trail run that recorded elevation"
                     : "What your trail pace is worth on the flat")
                    .font(.sg(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let summary {
                Text("\(Format.pace(summary.adjusted)) \(Text(Format.paceDelta(summary.adjusted - summary.raw)).font(.stat(14)).foregroundStyle(Theme.signal))")
                    .font(.stat(26))
            }
        }
    }

    // MARK: - Shared

    private func recordsCard(title: String, value: String) -> some View {
        Button { push(.records) } label: {
            GlassCard(cornerRadius: 20, padding: EdgeInsets(top: 18, leading: 22, bottom: 18, trailing: 22)) {
                HStack {
                    Text(title).font(.sg(16, weight: .semibold))
                    Spacer()
                    Text(value).font(.stat(15, weight: .regular)).foregroundStyle(Theme.bright)
                    Chevron()
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 26)
    }

    private var hasTrailRuns: Bool { store.allRuns.contains(where: \.isTrail) }

    private var divider: some View { Divider().overlay(Theme.hairline).padding(.vertical, 24) }

    private var monthAxis: some View { TrendMonthAxis(weeks: 12) }

    /// The signed change across the chart above it.
    ///
    /// Signal is this app's "this is the number you came for" colour, so it
    /// marks an improvement and nothing else — a regression is stated plainly
    /// rather than dressed in the same accent. Which direction counts as an
    /// improvement differs per metric, hence the parameter.
    private func trendDelta(_ text: String, improved: Bool, since: Date? = nil) -> some View {
        let month = since?.formatted(.dateTime.month(.abbreviated)) ?? windowStartMonth
        return Text("\(text) since \(month)")
            .font(.stat(14))
            .foregroundStyle(improved ? Theme.signal : Theme.bright)
    }

    /// The month the twelve-week window actually starts in. This used to be
    /// "three months ago", which is a different month from the one the chart
    /// and its axis begin at.
    private var windowStartMonth: String {
        let calendar = Calendar.runWeek
        let start = calendar.date(byAdding: .weekOfYear, value: -11, to: .now) ?? .now
        return start.formatted(.dateTime.month(.abbreviated))
    }

    /// The month of the first week in a weekly series that actually carries a
    /// value — which is where "since <month>" has to point.
    ///
    /// The window opens twelve weeks ago whether or not the running does. Both
    /// weekly headlines fell back to the window's own start, so a runner whose
    /// log begins in June was told their pace had improved "since April". The
    /// zone-2 block already got this right by naming its first month; this is
    /// the same answer for a series indexed by week.
    private func firstWeekMonth<T>(of series: [T?]) -> Date? {
        guard let index = series.firstIndex(where: { $0 != nil }) else { return nil }
        return Calendar.runWeek.date(byAdding: .weekOfYear,
                                     value: index - (series.count - 1), to: .now)
    }

    /// Metres climbed per hour across the trail runs of the last twelve weeks.
    private var trail12WeekClimbRate: Double {
        let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -12, to: .now) ?? .now
        let runs = store.allRuns.filter { $0.isTrail && $0.date >= cutoff }
        let hours = runs.reduce(0.0) { $0 + $1.duration } / 3600
        guard hours > 0.01 else { return 0 }
        return runs.reduce(0.0) { $0 + ($1.climbMeters ?? 0) } / hours
    }

    private func shortMonth(_ date: Date) -> String { date.formatted(.dateTime.month(.abbreviated)) }

    /// Every figure on this screen reads `allRuns`, like Home, the Log and
    /// Records do. It used to read `runs`, so the one screen headed "Progress"
    /// was the only one that ignored everything recorded in another app.
    private var last12WeekRoad: (km: Double, time: TimeInterval) {
        let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -12, to: .now) ?? .now
        let runs = store.allRuns.filter { !$0.isTrail && $0.date >= cutoff }
        return (runs.reduce(0) { $0 + $1.distanceKm }, runs.reduce(0) { $0 + $1.duration })
    }
}
