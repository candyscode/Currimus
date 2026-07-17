import SwiftUI

/// Set the target pace with the crown, then start.
struct PacerSetupView: View {
    @ObservedObject var session: RunSession
    var onStart: () -> Void
    @State private var crownValue: Double = 315

    private var target: TimeInterval { (crownValue / 5).rounded() * 5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PACER").kicker(9)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 0) {
                Text(Format.pace(target + 5))
                    .font(.stat(13))
                    .foregroundStyle(Theme.ghost)
                Text(Format.pace(target))
                    .font(.stat(40))
                    .kerning(-1)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: target)
                Text(Format.pace(max(target - 5, 180)))
                    .font(.stat(13))
                    .foregroundStyle(Theme.ghost)
            }

            Text("TARGET /KM · TURN CROWN").kicker(7).padding(.top, 6)
            (Text("10 km in ").foregroundStyle(Theme.muted)
                + Text(Format.clock(target * 10)).foregroundStyle(Theme.ink))
                .font(.stat(10, weight: .regular))
                .padding(.top, 3)

            Button(action: {
                session.pacerTarget = target
                onStart()
            }) {
                Text("Start")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.bg)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Theme.signal, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
        .padding(.horizontal, 4)
        .focusable()
        .digitalCrownRotation(
            $crownValue, from: 210, through: 480, by: 5,
            sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true
        )
        .onAppear { crownValue = session.pacerTarget }
    }
}

/// Live pacing — the dot tells you everything; numbers confirm it.
struct PacerRunView: View {
    @ObservedObject var session: RunSession

    private enum State { case onPace, fast, slow }

    private var state: State {
        if session.paceDelta < -6 { return .fast }
        if session.paceDelta > 6 { return .slow }
        return .onPace
    }

    private var statusLine: String {
        switch state {
        case .onPace: return "PACE /KM · ON PACE"
        case .fast: return "\(Format.pace(abs(session.paceDelta))) FAST · EASE OFF"
        case .slow: return "\(Format.pace(session.paceDelta)) SLOW · PICK IT UP"
        }
    }

    private var footerCenter: String {
        switch state {
        case .onPace:
            return "±\(Format.clock(abs(session.paceDelta)))"
        case .fast:
            let ahead = -session.scheduleDelta
            return ahead >= 1 ? "overall \(Format.clock(ahead)) ahead" : "on schedule"
        case .slow:
            let finish = session.pacerTarget * 10 + max(session.scheduleDelta, 0)
            return "finish ~\(Format.clock(finish))"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RunHeader(title: "PACER \(Format.pace(session.pacerTarget))", heartRate: session.heartRate)

            Spacer(minLength: 0)

            Text(Format.pace(session.rollingPace))
                .font(.stat(44))
                .kerning(-1)
                .foregroundStyle(state == .fast ? Theme.signal : Theme.ink)
            Text(statusLine)
                .kicker(8, color: state == .onPace ? Theme.muted : Theme.signal)
                .padding(.top, 3)

            HStack(alignment: .top, spacing: 14) {
                BigStat(value: Format.clock(session.elapsed), label: "TIME", size: 14)
                BigStat(value: Format.km(session.distanceKm), label: "KM", size: 14)
                VStack(alignment: .leading, spacing: 3) {
                    ZoneBar(zone: session.currentZone, height: 4, gap: 2)
                        .frame(width: 44)
                        .padding(.top, 6)
                    HStack(spacing: 3) {
                        Text("ZONE").kicker(7)
                        Text("\(session.currentZone)").font(.stat(8))
                    }
                }
            }
            .padding(.top, 10)

            Spacer(minLength: 0)

            PacerGauge(delta: session.paceDelta, state: stateColorIsSignal)
            HStack {
                Text("FAST").kicker(7, color: state == .fast ? Theme.signal : Theme.muted)
                Spacer()
                Text(footerCenter)
                    .font(.stat(8, weight: .regular))
                    .foregroundStyle(state == .onPace ? Theme.ink : Theme.muted)
                Spacer()
                Text("SLOW").kicker(7, color: state == .slow ? Theme.signal : Theme.muted)
            }
            .padding(.top, 3)
        }
        .padding(.horizontal, 4)
    }

    private var stateColorIsSignal: Bool { state != .onPace }
}

/// Horizontal deviation gauge — center notch is the target; the dot is you.
/// Fast drifts left, slow drifts right.
struct PacerGauge: View {
    /// Seconds off target; negative = fast.
    var delta: TimeInterval
    var state: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            // ±30 s maps to full deflection.
            let fraction = max(-1, min(1, delta / 30))
            let x = width / 2 + fraction * (width / 2 - 8)

            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track).frame(height: 3).offset(y: 5)
                if state {
                    Rectangle()
                        .fill(Theme.signal.opacity(0.4))
                        .frame(width: abs(x - width / 2), height: 3)
                        .offset(x: min(x, width / 2), y: 5)
                }
                Rectangle()
                    .fill(Theme.muted)
                    .frame(width: 1.5, height: 12)
                    .offset(x: width / 2 - 0.75)
                Circle()
                    .fill(state ? Theme.signal : Theme.ink)
                    .frame(width: 9, height: 9)
                    .offset(x: x - 4.5, y: 2)
            }
            .animation(.easeInOut(duration: 0.6), value: fraction)
        }
        .frame(height: 13)
    }
}
