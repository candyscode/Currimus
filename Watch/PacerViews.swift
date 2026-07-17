import SwiftUI

/// Step 1 · Target pace (required) — the crown scrolls the wheel.
struct PacerPaceView: View {
    @ObservedObject var session: RunSession
    var onNext: () -> Void
    @State private var crownValue: Double = 315

    private var target: TimeInterval { (crownValue / 5).rounded() * 5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 0) {
                Text("PACER").kicker(8, color: Theme.bright, tracking: 0.1)
                    .padding(.bottom, 6)
                Text(Format.pace(target + 5))
                    .font(.stat(12))
                    .foregroundStyle(Theme.ghost)
                Text(Format.pace(target))
                    .font(.stat(43))
                    .kerning(-1.9)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: target)
                Text(Format.pace(max(target - 5, 180)))
                    .font(.stat(12))
                    .foregroundStyle(Theme.ghost)

                Text("TARGET /KM · TURN CROWN")
                    .kicker(8, color: Theme.bright, tracking: 0.1)
                    .padding(.top, 7)
                (Text("at this pace: 10 km in ").foregroundStyle(Theme.bright)
                    + Text(Format.clock(target * 10)).foregroundStyle(Theme.ink))
                    .font(.stat(8.5, weight: .regular))
                    .padding(.top, 4)
            }

            Button(action: {
                session.pacerTarget = target
                onNext()
            }) {
                Text("Next")
                    .font(.sg(12.5, weight: .bold))
                    .foregroundStyle(Theme.bg)
                    .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40)
                    .background(Theme.signal, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
        }
        .padding(EdgeInsets(top: 2, leading: 22, bottom: 23, trailing: 22))
        .focusable()
        .digitalCrownRotation(
            $crownValue, from: 210, through: 480, by: 5,
            sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true
        )
        .onAppear { crownValue = session.pacerTarget }
    }
}

/// Step 2 · Distance (optional) — scroll up to Off and the pacer runs
/// open-ended: gauge and cumulative delta only, no finish forecast.
struct PacerDistanceView: View {
    @ObservedObject var session: RunSession
    var onStart: () -> Void
    /// Index into `options`; 0 = Off, then 5 km steps.
    @State private var crownValue = 2.0

    private let options: [Double?] = [nil] + stride(from: 5.0, through: 50.0, by: 5.0).map { $0 }

    private var index: Int { min(max(Int(crownValue.rounded()), 0), options.count - 1) }
    private var selection: Double? { options[index] }

    private func label(_ value: Double?) -> String {
        guard let value else { return "Off" }
        return "\(Int(value)) km"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 0) {
                Text("PACER · DISTANCE").kicker(8, color: Theme.bright, tracking: 0.1)
                    .padding(.bottom, 5)

                ghostRow(index - 2)
                ghostRow(index - 1)
                Group {
                    if let selection {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("\(Int(selection))")
                                .font(.stat(37))
                                .kerning(-1.5)
                            Text("km")
                                .font(.sg(15))
                                .foregroundStyle(Theme.bright)
                        }
                    } else {
                        Text("Off")
                            .font(.stat(37))
                            .kerning(-1.5)
                    }
                }
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.2), value: index)
                ghostRow(index + 1)

                Text("OPTIONAL · TURN CROWN")
                    .kicker(8, color: Theme.bright, tracking: 0.1)
                    .padding(.top, 6)
                Group {
                    if let selection {
                        (Text("at \(Format.pace(session.pacerTarget)) → finish ").foregroundStyle(Theme.bright)
                            + Text(Format.clock(selection * session.pacerTarget)).foregroundStyle(Theme.ink))
                    } else {
                        Text("open-ended — just run").foregroundStyle(Theme.bright)
                    }
                }
                .font(.stat(8.5, weight: .regular))
                .padding(.top, 3)
            }

            Button(action: {
                session.pacerDistanceKm = selection
                onStart()
            }) {
                Text("Start")
                    .font(.sg(12.5, weight: .bold))
                    .foregroundStyle(Theme.bg)
                    .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40)
                    .background(Theme.signal, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 11)
        }
        .padding(EdgeInsets(top: 2, leading: 22, bottom: 23, trailing: 22))
        .focusable()
        .digitalCrownRotation(
            $crownValue, from: 0, through: Double(options.count - 1), by: 1,
            sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true
        )
        .onAppear {
            if let existing = session.pacerDistanceKm,
               let existingIndex = options.firstIndex(of: existing) {
                crownValue = Double(existingIndex)
            }
        }
    }

    @ViewBuilder
    private func ghostRow(_ rowIndex: Int) -> some View {
        Text(rowIndex >= 0 && rowIndex < options.count ? label(options[rowIndex]) : " ")
            .font(.stat(11))
            .foregroundStyle(Theme.ghost)
            .lineSpacing(0)
            .padding(.vertical, 1)
    }
}

/// Live pacing — the dot tells you everything; numbers confirm it.
struct PacerRunView: View {
    @ObservedObject var session: RunSession

    private enum PaceState { case onPace, fast, slow }

    private var state: PaceState {
        if session.paceDelta < -6 { return .fast }
        if session.paceDelta > 6 { return .slow }
        return .onPace
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 0) {
                Text(Format.pace(session.rollingPace))
                    .font(.stat(52))
                    .kerning(-2.3)
                    .foregroundStyle(state == .fast ? Theme.signal : Theme.ink)
                statusLine
                    .padding(.top, 4)

                HStack(alignment: .top, spacing: 18) {
                    BigStat(value: Format.clock(session.elapsed), label: "TIME", size: 13)
                    BigStat(
                        value: Format.km(session.distanceKm),
                        label: session.pacerDistanceKm.map { "/ \(Int($0)) KM" } ?? "KM",
                        size: 13
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        ZoneBar(zone: session.currentZone, height: 4, gap: 1.5)
                            .frame(width: 48)
                            .padding(.top, 5)
                        (Text("ZONE ").foregroundStyle(Theme.bright)
                            + Text(session.currentZone > 0 ? "\(session.currentZone)" : "–")
                                .foregroundStyle(Theme.ink).fontWeight(.semibold))
                            .font(.sg(8))
                            .kerning(8 * 0.1)
                            .padding(.top, 2)
                    }
                }
                .padding(.top, 12)
            }

            Spacer(minLength: 0)

            PacerGauge(delta: session.paceDelta, offTarget: state != .onPace)
            HStack {
                Text("FAST")
                    .kicker(state == .fast ? 7 : 8,
                            color: state == .fast ? Theme.signal : Theme.bright,
                            tracking: state == .fast ? 0.12 : 0.1)
                    .fontWeight(state == .fast ? .semibold : .regular)
                Spacer()
                footerCenter
                Spacer()
                Text("SLOW")
                    .kicker(state == .slow ? 7 : 8,
                            color: state == .slow ? Theme.signal : Theme.bright,
                            tracking: state == .slow ? 0.12 : 0.1)
                    .fontWeight(state == .slow ? .semibold : .regular)
            }
            .padding(.top, 3)
        }
        .padding(EdgeInsets(top: 2, leading: 22, bottom: 26, trailing: 22))
    }

    @ViewBuilder
    private var statusLine: some View {
        switch state {
        case .onPace:
            Text("PACER · ON TARGET \(Format.pace(session.pacerTarget))")
                .kicker(8, color: Theme.bright, tracking: 0.1)
        case .fast:
            Text("\(Format.pace(abs(session.paceDelta))) FAST · TARGET \(Format.pace(session.pacerTarget))")
                .kicker(7.5, color: Theme.signal, tracking: 0.12)
        case .slow:
            Text("\(Format.pace(session.paceDelta)) SLOW · TARGET \(Format.pace(session.pacerTarget))")
                .kicker(8, color: Theme.bright, tracking: 0.1)
        }
    }

    @ViewBuilder
    private var footerCenter: some View {
        if state == .onPace {
            Text("±\(Format.clock(abs(session.paceDelta)))")
                .font(.stat(7))
                .foregroundStyle(Theme.ink)
        } else if let forecast = session.finishForecast {
            Text("finish ~\(Format.clock(forecast))")
                .font(.stat(7, weight: .regular))
                .foregroundStyle(Theme.muted)
        } else {
            let ahead = -session.scheduleDelta
            Text(ahead >= 1
                 ? "overall \(Format.clock(ahead)) ahead"
                 : (ahead <= -1 ? "overall \(Format.clock(-ahead)) behind" : "on schedule"))
                .font(.stat(7, weight: .regular))
                .foregroundStyle(Theme.muted)
        }
    }
}

/// Horizontal deviation gauge — center notch is the target; the dot is you.
/// Fast drifts left, slow drifts right.
struct PacerGauge: View {
    /// Seconds off target; negative = fast.
    var delta: TimeInterval
    var offTarget: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            // ±30 s maps to full deflection.
            let fraction = max(-1, min(1, delta / 30))
            let x = width / 2 + fraction * (width / 2 - 7)

            ZStack(alignment: .topLeading) {
                Capsule().fill(Theme.track)
                    .frame(width: width, height: 2)
                    .offset(y: 5)
                if offTarget {
                    Rectangle()
                        .fill(Theme.signal.opacity(0.4))
                        .frame(width: abs(x - width / 2), height: 2)
                        .offset(x: min(x, width / 2), y: 5)
                }
                Rectangle()
                    .fill(Theme.muted)
                    .frame(width: 1, height: 8)
                    .offset(x: width / 2 - 0.5, y: 2)
                Circle()
                    .fill(offTarget ? Theme.signal : Theme.ink)
                    .frame(width: 7, height: 7)
                    .offset(x: x - 3.5, y: 2.5)
            }
            .animation(.easeInOut(duration: 0.6), value: fraction)
        }
        .frame(height: 12)
    }
}

/// Pacer summary — target vs. actual, Done → Home.
struct PacerSummaryView: View {
    var run: Run
    var target: TimeInterval
    var targetDistanceKm: Double?
    var onDone: () -> Void

    private var deltaSentence: (lead: String, delta: String, trail: String)? {
        guard let targetDistanceKm else { return nil }
        let targetTime = targetDistanceKm * target
        let delta = run.duration - targetTime
        guard abs(delta) >= 1 else { return ("Finished ", "right on", " the \(Format.clock(targetTime)) target.") }
        return (
            "Finished ",
            "\(Format.clock(abs(delta))) \(delta < 0 ? "ahead" : "behind")",
            " of the \(Format.clock(targetTime)) target."
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PACER COMPLETE").kicker(8, color: Theme.bright, tracking: 0.1)
                .padding(.top, 7)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(Format.km(run.distanceKm, decimals: 1))
                    .font(.stat(26))
                    .kerning(-1)
                Text("km").font(.sg(11)).foregroundStyle(Theme.bright)
            }
            .padding(.top, 4)

            HStack(alignment: .top, spacing: 14) {
                BigStat(value: Format.clock(run.duration), label: "TIME", size: 12.5, labelSize: 7.5)
                BigStat(value: Format.pace(run.paceSecPerKm), label: "AVG PACE", valueColor: Theme.signal, size: 12.5, labelSize: 7.5)
                BigStat(value: Format.pace(target), label: "TARGET", size: 12.5, labelSize: 7.5)
            }
            .padding(.top, 10)

            if let sentence = deltaSentence {
                (Text(sentence.lead)
                    + Text(sentence.delta).foregroundStyle(Theme.signal).fontWeight(.semibold)
                    + Text(sentence.trail))
                    .font(.stat(8, weight: .regular))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(2)
                    .padding(.top, 8)
            }

            Spacer(minLength: 0)

            Button(action: onDone) {
                Text("Done")
                    .font(.sg(9.5, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 31, maxHeight: 31)
                    .background(Theme.button, in: Capsule())
                    .overlay(Capsule().stroke(Theme.buttonBorder, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(EdgeInsets(top: 2, leading: 22, bottom: 22, trailing: 22))
    }
}
