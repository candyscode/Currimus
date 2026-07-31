import SwiftUI

struct RaceView: View {
    @EnvironmentObject private var store: RunStore
    @Environment(\.pushRoute) private var push
    @State private var explaining: Explanation?

    var body: some View {
        PushedScreen(title: "Race") {
            if let race = store.race {
                content(race)
            } else {
                Text("No race set.").font(.sg(16)).foregroundStyle(Theme.muted).padding(.top, 40)
            }
        }
        .explanationSheet($explaining)
        // The sheet Andi called too big (CUR-38); it sizes itself to its text
        // now, and a tap on the ⓘ cannot be injected into a screenshot.
        .onAppear {
            if DebugFlags.opensExplanation, let race = store.race, !race.isPast {
                explaining = estimateExplanation(race)
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

            // A race that has been run counts the other way. This used to
            // show its countdown straight through zero — "-3 DAYS", 136 pt.
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("\(race.isPast ? race.daysSince : race.daysUntil())")
                    .font(.stat(136)).kerning(-6.8)
                Text(race.isPast ? "DAYS AGO" : "DAYS")
                    .font(.sg(24, weight: .semibold)).kerning(2.4)
                    .foregroundStyle(Theme.signal)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.top, 4)

            // Every forecast is a field with its own label, and every field can
            // be asked where it came from.
            //
            // There used to be one "PREDICTED" tile and a paragraph underneath
            // holding *both* numbers in bold inside its sentences. A time in the
            // middle of a sentence is not a field: it cannot be read at a
            // glance, it cannot be compared with the one beside it, and the
            // sentence has to be read to the end to learn there were two.
            Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 24) {
                GridRow {
                    ExplainedStat(value: Format.clock(race.goalTime), label: "GOAL TIME").gx()
                    ExplainedStat(value: Format.pace(race.requiredPace),
                                  label: "REQUIRED /KM", accent: true).gx()
                }
                if race.isPast {
                    GridRow {
                        ExplainedStat(value: store.raceResult.map { Format.clock($0.duration) } ?? "—",
                                      label: store.raceResult == nil ? "NO RUN THAT DAY" : "YOUR TIME",
                                      accent: store.raceResult != nil).gx()
                        longestStat(longest, pct: longestPct).gx()
                    }
                } else {
                    // One estimate, from the training. Two used to sit here —
                    // Riegel's scaling of a past effort beside Tanda's reading
                    // of the last eight weeks — and two forecasts for the same
                    // race is a question, not an answer (Andi, CUR-38).
                    GridRow {
                        ExplainedStat(value: store.raceEstimate.map { Format.clock($0.time) } ?? "—",
                                      label: "ESTIMATION",
                                      explanation: estimateExplanation(race),
                                      onExplain: { explaining = $0 }).gx()
                        longestStat(longest, pct: longestPct).gx()
                    }
                }
            }
            .padding(.top, 34)

            Divider().overlay(Theme.hairline).padding(.top, 30).padding(.bottom, 24)

            HStack(alignment: .firstTextBaseline) {
                Text("LAST 4 WEEKS").kicker(13, color: Theme.bright, tracking: 0.12)
                Spacer()
                // Signal marks the direction, it does not decorate the row:
                // four weeks of *less* running before a race is a taper or a
                // problem, and either way it is not good news to be coloured.
                let delta = last4Delta
                Text(verbatim: "\(Int(store.last4WeeksKm)) km\(delta.map { " · \($0.text)" } ?? "")")
                    .font(.stat(13))
                    .foregroundStyle(delta?.isUp == true ? Theme.signal : Theme.bright)
                    .lineLimit(1).fixedSize()
            }
            // The bars carry their own value labels on top, so 18 pt put the
            // first number almost against the heading.
            WeekVolumeBars(items: store.last4Weeks()).padding(.top, 30)

            if let note = predictionNote(race) {
                Explainer(markdown: note, top: 18)
            }

            Button { push(.raceSetup) } label: {
                GlassCard(cornerRadius: 20, padding: EdgeInsets(top: 18, leading: 22, bottom: 18, trailing: 22)) {
                    HStack { Text("Edit race").font(.sg(16, weight: .semibold)); Spacer(); Chevron() }
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 26)
        }
    }

    /// The last four weeks against the four before them.
    ///
    /// Both sides read `allRuns`. The previous window used to filter
    /// `store.runs` — Currimus' own recordings only — while the current one
    /// counted everything, so anyone whose runs come from another app was
    /// comparing their whole log against a fraction of it and reading a
    /// triple-digit increase that had not happened.
    ///
    /// Both sides now also read the *same grid*, which they did not. The current
    /// window was a set of calendar weeks and the previous one a raw 28-day
    /// span, so on a Monday this compared 22 days against 28 — a −21 % bias
    /// before a single kilometre was counted — with a seven-day hole between
    /// them that belonged to neither. Both are four rolling seven-day buckets
    /// now, adjacent, and the bars above are the same four.
    private var last4Delta: (text: String, isUp: Bool)? {
        let previous = store.previous4WeeksKm
        guard previous > 0 else { return nil }
        let pct = Int(((store.last4WeeksKm - previous) / previous * 100).rounded())
        return ("\(pct >= 0 ? "+" : "")\(pct)%", pct >= 0)
    }

    private func longestStat(_ km: Double, pct: Int) -> some View {
        ExplainedStat(value: "\(Format.km(km, decimals: 1)) km", label: "LONGEST · \(pct)%")
    }

    /// The line that stays on the screen: only what has no field to hang on.
    ///
    /// Everything that explains a *number* moved into that number's own sheet.
    /// What is left is the empty state — where there is no number yet — and the
    /// account of a race that has been run.
    private func predictionNote(_ race: Race) -> String? {
        race.isPast ? resultNote(race) : nil
    }

    // MARK: - Where the estimate came from
    //
    // One model now, and it is the one that reads the work: Tanda takes the
    // weekly volume and the training pace of the last eight weeks. Riegel —
    // scaling a past 10 K onto the race — is gone from the screen (CUR-38). It
    // knew nothing about whether the training had been done, and standing next
    // to a second forecast it left the runner to decide which to believe.

    private func estimateExplanation(_ race: Race) -> Explanation {
        let title = String(localized: "Estimation")
        guard race.distance == .marathon else {
            return Explanation(
                title: title,
                body: String(localized: "This estimate reads your training — weekly volume and training pace over the last eight weeks — through \(Source.tanda.link), and that model is fitted on the marathon. Over a shorter race it would return a number without evidence behind it, so Currimus does not print one. Set a marathon as your race and the estimate appears."))
        }
        guard let training = store.raceEstimate else {
            return Explanation(
                title: title,
                body: String(localized: "Not enough training to read yet. This estimate needs at least \(Format.plural(RunAnalytics.minimumTrainingWeeks, "week", "weeks")) of running behind it, with eight road runs or more in the last eight weeks — a handful of runs in a fortnight describes a fortnight, not a marathon."))
        }
        var body = String(localized: "\(Int(training.weeklyKm)) km a week at \(Format.pace(training.meanPaceSecPerKm)) /km over the last \(Format.plural(training.weeksCovered, "week", "weeks")), read through \(Source.tanda.link). It reads the work you have put in — volume and everyday pace, not one hard day — and knows nothing about race sharpness or the weather.")
        if training.isExtrapolated {
            body += String(localized: "\n\nThis one is an extrapolation: your volume and pace sit outside the range that study covered, so read it as a direction rather than as a time.")
        }
        if (store.longestRun?.distanceKm ?? 0) < race.distance.km * 0.6 {
            body += String(localized: "\n\nYour longest run is still well short of the race, which the model cannot see: it reads the average week, not whether you have been that far in one go.")
        }
        return Explanation(title: title, body: body)
    }


    /// After the fact: how it went against the goal, or the plain admission
    /// that no run in the log looks like that race.
    private func resultNote(_ race: Race) -> String {
        guard let result = store.raceResult else {
            return String(localized: "That race day has passed, and no run in your log covers the distance on it. Set the next one when you have it.")
        }
        let delta = result.duration - race.goalTime
        let against: String
        if abs(delta) < 60 {
            against = String(localized: "within a minute of your goal")
        } else if delta < 0 {
            against = String(localized: "\(Format.clock(-delta)) inside your goal")
        } else {
            against = String(localized: "\(Format.clock(delta)) over your goal")
        }
        return String(localized: "\(Format.km(result.distanceKm, decimals: 1)) km in **\(Format.clock(result.duration))**, \(against) of \(Format.clock(race.goalTime)). Set the next race when you have one — this screen goes back to counting down.")
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
    @State private var confirmRemove = false

    private var requiredPace: TimeInterval { goalTime / distance.km }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
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
                Text(Format.plural(daysUntil, "day", "days"))
                    .font(.stat(13, weight: .semibold)).foregroundStyle(Theme.signal)
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
                // An empty name saves a race that renders as "RACE DAY · " with
                // nothing after it on Home. Blank is the one value this form
                // can be left in that produces a broken screen, so it is the
                // one the button refuses.
                .disabled(trimmedName.isEmpty)
                .opacity(trimmedName.isEmpty ? 0.4 : 1)

                // Setting a race was one-way: once it existed it took over
                // Home's headline and could only be edited, never cleared —
                // so a race that had passed, or plans that had changed, stayed
                // on the screen with no way off it.
                if store.race != nil {
                    Button(role: .destructive) { confirmRemove = true } label: {
                        Text("Remove race").font(.sg(16, weight: .semibold))
                            .foregroundStyle(Theme.signal)
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.plain).padding(.top, 6)
                }
            }
        }
        .confirmationDialog("Remove this race?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove race", role: .destructive) {
                store.race = nil
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Home goes back to your weekly volume. Your runs and records are untouched.")
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
        // Named for what it actually is. It used to say the goal "sits inside
        // what you have already held", comparing a marathon's required pace
        // against a tempo run of eight kilometres — which says very little
        // about forty-two.
        let distance = distance.short
        return requiredPace >= best
            ? "Slower than your best tempo pace (\(Format.pace(best)) /km), which is a start — a \(distance) asks you to hold it far longer."
            : "Faster than your best tempo pace (\(Format.pace(best)) /km), over a \(distance) — ambitious, but that is the point."
    }

    private func fieldLabel(_ t: String) -> some View { Text(t).kicker(13, color: Theme.bright, tracking: 0.12) }

    private func save() {
        var race = store.race ?? Race(name: name, distance: distance, date: date, goalTime: goalTime)
        race.name = trimmedName; race.distance = distance; race.date = date; race.goalTime = goalTime
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
