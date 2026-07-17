import SwiftUI

/// Set the target pace with the crown, then start.
struct PacerSetupView: View {
    @ObservedObject var session: RunSession
    var onStart: () -> Void
    @State private var crownValue: Double = 315

    private var target: TimeInterval { (crownValue / 5).rounded() * 5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PACER").kicker(8.5)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 0) {
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

                Text("TARGET /KM · TURN CROWN").kicker(7, tracking: 0.12).padding(.top, 7)
                (Text("10 km in ").foregroundStyle(Theme.muted)
                    + Text(Format.clock(target * 10)).foregroundStyle(Theme.ink))
                    .font(.stat(8, weight: .regular))
                    .padding(.top, 4)
            }

            Button(action: {
                session.pacerTarget = target
                onStart()
            }) {
                Text("Start")
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

/// Live pacing — the dot tells you everything; numbers confirm it.
struct PacerRunView: View {
    @ObservedObject var session: RunSession

    private enum PaceState { case onPace, fast, slow }

    private var state: PaceState {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RunHeader(title: "PACER \(Format.pace(session.pacerTarget))", heartRate: session.heartRate)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 0) {
                Text(Format.pace(session.rollingPace))
                    .font(.stat(52))
                    .kerning(-2.3)
                    .foregroundStyle(state == .fast ? Theme.signal : Theme.ink)
                Text(statusLine)
                    .kicker(7.5, color: state == .fast ? Theme.signal : Theme.muted, tracking: 0.12)
                    .padding(.top, 4)

                HStack(alignment: .top, spacing: 18) {
                    BigStat(value: Format.clock(session.elapsed), label: "TIME", size: 13, labelSize: 6.5)
                    BigStat(value: Format.km(session.distanceKm), label: "KM", size: 13, labelSize: 6.5)
                    VStack(alignment: .leading, spacing: 3) {
                        ZoneBar(zone: session.currentZone, height: 4, gap: 1.5)
                            .frame(width: 48)
                            .padding(.top, 5)
                        HStack(spacing: 3) {
                            Text("ZONE").kicker(6.5, tracking: 0.1)
                            Text("\(session.currentZone)")
                                .font(.stat(6.5))
                                .foregroundStyle(Theme.ink)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(.top, 12)
            }

            Spacer(minLength: 0)

            PacerGauge(delta: session.paceDelta, offTarget: state != .onPace)
            HStack {
                Text("FAST")
                    .kicker(7, color: state == .fast ? Theme.signal : Theme.muted, tracking: 0.12)
                    .fontWeight(state == .fast ? .semibold : .regular)
                Spacer()
                footerCenter
                Spacer()
                Text("SLOW")
                    .kicker(7, color: state == .slow ? Theme.signal : Theme.muted, tracking: 0.12)
                    .fontWeight(state == .slow ? .semibold : .regular)
            }
            .padding(.top, 3)
        }
        .padding(EdgeInsets(top: 2, leading: 22, bottom: 26, trailing: 22))
    }

    @ViewBuilder
    private var footerCenter: some View {
        switch state {
        case .onPace:
            Text("±\(Format.clock(abs(session.paceDelta)))")
                .font(.stat(7))
                .foregroundStyle(Theme.ink)
        case .fast:
            let ahead = -session.scheduleDelta
            Text(ahead >= 1 ? "overall \(Format.clock(ahead)) ahead" : "on schedule")
                .font(.stat(7, weight: .regular))
                .foregroundStyle(Theme.muted)
        case .slow:
            let finish = session.pacerTarget * 10 + max(session.scheduleDelta, 0)
            Text("finish ~\(Format.clock(finish))")
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
