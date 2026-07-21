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
        let longestPct = Int((longest / race.distance.km * 100).rounded())
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

    private var realismNote: String {
        let tempo = store.runs.filter { $0.classification == .tempo }
        guard let avg = tempo.map(\.paceSecPerKm).min() else {
            return "Set a goal and see the pace it needs."
        }
        return requiredPace >= avg
            ? "Your tempo runs average \(Format.pace(avg)) — the goal is realistic."
            : "Faster than your best tempo (\(Format.pace(avg))) — ambitious, but that is the point."
    }

    private func fieldLabel(_ t: String) -> some View { Text(t).kicker(13, color: Theme.bright, tracking: 0.12) }

    private func save() {
        var race = store.race ?? Race(name: name, distance: distance, date: date, goalTime: goalTime)
        race.name = name; race.distance = distance; race.date = date; race.goalTime = goalTime
        store.race = race
        dismiss()
    }
}

/// A three-row goal-time wheel, 5-minute steps. Drag or tap the neighbours.
struct GoalTimeWheel: View {
    @Binding var seconds: TimeInterval
    private let step: TimeInterval = 300
    @State private var drag: CGFloat = 0

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
        .gesture(DragGesture()
            .onChanged { v in
                let d = v.translation.height - drag
                if abs(d) > 20 { shift(d > 0 ? 1 : -1); drag = v.translation.height }
            }
            .onEnded { _ in drag = 0 })
    }

    private func neighbour(_ value: TimeInterval) -> some View {
        Button { withAnimation(.snappy(duration: 0.18)) { seconds = clamp(value) } } label: {
            Text(Format.clock(value)).font(.stat(22)).foregroundStyle(Color(hex: 0x575757))
                .frame(maxWidth: .infinity).padding(.vertical, 7)
        }
        .buttonStyle(.plain)
    }

    private func shift(_ dir: Int) { withAnimation(.snappy(duration: 0.18)) { seconds = clamp(seconds + Double(dir) * step) } }
    private func clamp(_ v: TimeInterval) -> TimeInterval { min(max(v, 900), 6 * 3600) }
}
