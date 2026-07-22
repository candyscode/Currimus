import SwiftUI

struct RaceView: View {
    @EnvironmentObject private var store: RunStore
    @Environment(\.pushRoute) private var push

    var body: some View {
        PushedScreen(title: "Race") {
            if let race = store.race {
                content(race)
            } else {
                Text("No race set.").font(.sg(16)).foregroundStyle(Theme.muted).padding(.top, 40)
            }
        }
    }

    private func content(_ race: Race) -> some View {
        let longest = store.longestRun?.distanceKm ?? 0
        // Capped: the label reads "how much of race day you have covered", and
        // an ultra runner training for a 10 K was told they were at 340 % of
        // it, which reads as a broken percentage rather than a compliment.
        let longestPct = min(Int((longest / race.distance.km * 100).rounded()), 100)
        return VStack(alignment: .leading, spacing: 0) {
            Text("\(race.name.uppercased()) · \(race.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()).uppercased())")
                .kicker(13, color: Theme.bright, tracking: 0.12)

            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("\(race.daysUntil())").font(.stat(136)).kerning(-6.8)
                Text("DAYS").font(.sg(24, weight: .semibold)).kerning(2.4).foregroundStyle(Theme.signal)
            }
            .padding(.top, 4)

            Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 24) {
                GridRow {
                    BigDetailStat(value: Format.clock(race.goalTime), label: "GOAL TIME").gx()
                    BigDetailStat(value: Format.pace(race.requiredPace), label: "REQUIRED /KM", accent: true).gx()
                }
                GridRow {
                    if let p = store.prediction {
                        BigDetailStat(value: Format.clock(p.time), label: "PREDICTED · \(p.basisLabel.replacingOccurrences(of: " PR", with: ""))").gx()
                    } else {
                        BigDetailStat(value: "—", label: "PREDICTED").gx()
                    }
                    BigDetailStat(value: "\(Format.km(longest, decimals: 1)) km",
                                  label: "LONGEST · \(longestPct)%").gx()
                }
            }
            .padding(.top, 34)

            Divider().overlay(Theme.hairline).padding(.top, 30).padding(.bottom, 24)

            HStack(alignment: .firstTextBaseline) {
                Text("LAST 4 WEEKS").kicker(13, color: Theme.bright, tracking: 0.12)
                Spacer()
                Text(verbatim: "\(Int(store.last4WeeksKm)) km · \(last4Delta)")
                    .font(.stat(13)).foregroundStyle(Theme.signal)
                    .lineLimit(1).fixedSize()
            }
            WeekVolumeBars(items: store.last4Weeks()).padding(.top, 18)

            Text(predictionNote(race)).font(.sg(13)).foregroundStyle(Theme.muted)
                .lineSpacing(4).padding(.top, 18)

            Button { push(.raceSetup) } label: {
                GlassCard(cornerRadius: 20, padding: EdgeInsets(top: 18, leading: 22, bottom: 18, trailing: 22)) {
                    HStack { Text("Edit race").font(.sg(16, weight: .semibold)); Spacer(); Chevron() }
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 26)
        }
    }

    private var last4Delta: String {
        let cal = Calendar.current
        let now = store.last4WeeksKm
        let prevRuns = store.runs.filter {
            guard let start = cal.date(byAdding: .weekOfYear, value: -8, to: .now),
                  let end = cal.date(byAdding: .weekOfYear, value: -4, to: .now) else { return false }
            return $0.date >= start && $0.date < end
        }
        let prev = prevRuns.reduce(0) { $0 + $1.distanceKm }
        guard prev > 0 else { return "—" }
        let pct = Int(((now - prev) / prev * 100).rounded())
        return "\(pct >= 0 ? "+" : "")\(pct)%"
    }

    private func predictionNote(_ race: Race) -> String {
        guard let p = store.prediction else {
            return "Add a shorter benchmark run and the prediction appears."
        }
        let extra = p.underTrained ? " Your longest run is still short of the distance, so treat it as optimistic." : ""
        return "Prediction uses your \(p.basisLabel) (Riegel). It improves as races and long runs come in — no plans, no coaching, just where you stand.\(extra)"
    }
}

struct BigDetailStat: View {
    var value: String
    var label: String
    var accent: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.stat(34)).kerning(-0.5).foregroundStyle(accent ? Theme.signal : Theme.ink).lineLimit(1)
            Text(label).kicker(13, color: Theme.bright, tracking: 0.12).fixedSize()
        }
    }
}

private extension View { func gx() -> some View { frame(maxWidth: .infinity, alignment: .leading) } }

// MARK: - Race Setup

struct RaceSetupView: View {
    @EnvironmentObject private var store: RunStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var distance: RaceDistance = .marathon
    @State private var date: Date = Calendar.current.date(byAdding: .day, value: 42, to: .now)!
    @State private var goalTime: TimeInterval = 3 * 3600 + 59 * 60
    @State private var loaded = false

    private var requiredPace: TimeInterval { goalTime / distance.km }
    private var daysUntil: Int {
        Race(name: name, distance: distance, date: date, goalTime: goalTime).daysUntil()
    }

    var body: some View {
        PushedScreen(title: "Target race") {
            VStack(alignment: .leading, spacing: 0) {
                fieldLabel("NAME")
                TextField("Race name", text: $name)
                    .font(.sg(16)).tint(Theme.signal)
                    .padding(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))
                    .background(Theme.glassCardFill, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.glassCardStroke, lineWidth: 1))
                    .padding(.top, 10)

                fieldLabel("DISTANCE").padding(.top, 26)
                SegmentChips(
                    options: RaceDistance.allCases.map { ($0, $0.short) },
                    selection: $distance,
                    flexible: [.marathon: 1.3]
                )
                .padding(.top, 12)

                fieldLabel("DATE").padding(.top, 26)
                HStack {
                    Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                        .font(.sg(16))
                    Spacer()
                    DatePicker("", selection: $date, in: Date()..., displayedComponents: .date)
                        .labelsHidden().tint(Theme.signal)
                }
                .padding(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 16))
                .background(Theme.glassCardFill, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.glassCardStroke, lineWidth: 1))
                .padding(.top, 10)
                Text("\(daysUntil) days").font(.stat(13, weight: .semibold)).foregroundStyle(Theme.signal)
                    .frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 6)

                fieldLabel("GOAL TIME").padding(.top, 20)
                GoalTimeWheel(seconds: $goalTime).padding(.top, 6)

                HStack(alignment: .firstTextBaseline) {
                    Text("That is").font(.sg(14)).foregroundStyle(Theme.bright)
                    Spacer()
                    Text("\(Format.pace(requiredPace)) \(Text("/km").font(.sg(14)).foregroundStyle(Theme.bright))")
                        .font(.stat(26)).foregroundStyle(Theme.signal)
                }
                .padding(.top, 18)
                Text(realismNote).font(.sg(13)).foregroundStyle(Theme.muted).lineSpacing(3).padding(.top, 6)

                Button(action: save) {
                    Text("Save race").font(.sg(17, weight: .bold)).foregroundStyle(Theme.bg)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Theme.signal, in: Capsule())
                }
                .buttonStyle(.plain).padding(.top, 24)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let r = store.race {
                name = r.name; distance = r.distance; date = r.date; goalTime = r.goalTime
            } else {
                name = "My race"
            }
        }
    }

    /// Sanity-checks the goal against the fastest sustained effort on record.
    ///
    /// The number here is `min` — the *best* tempo run, not the average one.
    /// The sentence used to call it the average, so it named one statistic and
    /// showed another, and the two differ by exactly the amount that decides
    /// whether a goal is ambitious.
    private var realismNote: String {
        let tempoPaces = store.allRuns
            .filter { !$0.isTrail && $0.classification == .tempo }
            .map(\.paceSecPerKm)
        guard let best = tempoPaces.min() else {
            return "Set a goal and see the pace it needs."
        }
        return requiredPace >= best
            ? "Your best tempo run is \(Format.pace(best)) /km, so the goal sits inside what you have already held."
            : "Faster than your best tempo (\(Format.pace(best)) /km) — ambitious, but that is the point."
    }

    private func fieldLabel(_ t: String) -> some View { Text(t).kicker(13, color: Theme.bright, tracking: 0.12) }

    private func save() {
        var race = store.race ?? Race(name: name, distance: distance, date: date, goalTime: goalTime)
        race.name = name; race.distance = distance; race.date = date; race.goalTime = goalTime
        store.race = race
        dismiss()
    }
}

/// A three-row goal-time wheel, one minute per step. Drag, or tap a neighbour.
struct GoalTimeWheel: View {
    @Binding var seconds: TimeInterval
    // One minute, not five. At five, the reachable times were 4:25, 4:30, …
    // and 4:26 simply did not exist — the whole complaint.
    private let step: TimeInterval = 60
    // How far the finger travels for one step. The old wheel fired a step
    // every time the delta since the last one crossed 20 pt and then reset its
    // baseline, so a single slow slide rattled through several steps at once;
    // a light flick jumped minutes. This maps total travel to an absolute
    // offset from where the drag began, so the number tracks the finger.
    private let pointsPerStep: CGFloat = 16
    @State private var anchor: TimeInterval?

    var body: some View {
        VStack(spacing: 0) {
            neighbour(seconds + step)
            HStack { Spacer()
                Text(Format.clock(seconds)).font(.stat(48)).kerning(-1.4)
                    .contentTransition(.numericText())
                Spacer() }
                .padding(.vertical, 10)
                .overlay(alignment: .top) { Theme.buttonBorder.frame(height: 1) }
                .overlay(alignment: .bottom) { Theme.buttonBorder.frame(height: 1) }
            neighbour(seconds - step)
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 1)
            .onChanged { v in
                let base = anchor ?? seconds
                anchor = base
                // Larger values sit above centre, so dragging down brings them
                // in — a positive translation raises the time.
                let steps = (v.translation.height / pointsPerStep).rounded()
                seconds = clamp(base + steps * step)
            }
            .onEnded { _ in anchor = nil })
        // The neighbour buttons are the visual affordance; for VoiceOver the
        // whole thing is one adjustable value, which is how a time field should
        // read out loud.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Goal time")
        .accessibilityValue(Format.clock(seconds))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: seconds = clamp(seconds + step)
            case .decrement: seconds = clamp(seconds - step)
            @unknown default: break
            }
        }
    }

    private func neighbour(_ value: TimeInterval) -> some View {
        Button { withAnimation(.snappy(duration: 0.18)) { seconds = clamp(value) } } label: {
            Text(Format.clock(value)).font(.stat(22)).foregroundStyle(Color(hex: 0x575757))
                .frame(maxWidth: .infinity).padding(.vertical, 7)
        }
        .buttonStyle(.plain)
    }

    private func clamp(_ v: TimeInterval) -> TimeInterval { min(max(v, 900), 6 * 3600) }
}
