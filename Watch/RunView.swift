import SwiftUI

/// The one glance: time, distance, pace, zone. Tap to pause.
struct RunView: View {
    @ObservedObject var session: RunSession

    var body: some View {
        ZStack {
            if session.type == .pacer {
                PacerRunView(session: session)
            } else {
                quickRun
            }

            if let alert = session.kilometerAlert {
                KilometerAlertView(alert: alert)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.kilometerAlert)
        .contentShape(Rectangle())
        .onTapGesture { session.pause() }
    }

    private var quickRun: some View {
        let zone = session.currentZone
        return VStack(alignment: .leading, spacing: 0) {
            RunHeader(
                title: zone >= 5 ? "MAX" : "RUN",
                titleColor: zone >= 5 ? Theme.signal : Theme.muted,
                titleWeight: zone >= 5 ? .semibold : .regular,
                heartRate: session.heartRate,
                hrColor: zone >= 5 ? Theme.signal : (zone == 4 ? Theme.ink : Theme.muted)
            )

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 0) {
                Text(Format.clock(session.elapsed))
                    .font(.stat(52))
                    .kerning(-2.3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                HStack(alignment: .top, spacing: 18) {
                    BigStat(value: Format.km(session.distanceKm), label: "KM")
                    BigStat(value: Format.pace(session.rollingPace), label: "PACE /KM", valueColor: Theme.signal)
                }
                .padding(.top, 11)
            }

            Spacer(minLength: 0)

            ZoneBar(zone: zone)
            HStack {
                Text("ZONE").kicker(7.5, tracking: 0.12)
                Spacer()
                Text("\(zone)")
                    .font(.stat(7.5))
                    .foregroundStyle(zone >= 3 ? Theme.signal : Theme.ink)
            }
            .padding(.top, 4.5)
        }
        .padding(EdgeInsets(top: 2, leading: 22, bottom: 26, trailing: 22))
    }
}

struct RunHeader: View {
    var title: String
    var titleColor: Color = Theme.muted
    var titleWeight: Font.Weight = .regular
    var heartRate: Int
    var hrColor: Color = Theme.muted
    var hrWeight: Font.Weight = .regular
    /// Leading mark before the title (the trail triangle).
    var mark: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 5) {
                if mark {
                    TriangleMark()
                        .fill(Theme.signal)
                        .frame(width: 8, height: 7)
                }
                Text(title)
                    .font(.sg(8.5, weight: titleWeight))
                    .kerning(8.5 * 0.14)
                    .foregroundStyle(titleColor)
            }
            Spacer()
            Text("♥\u{FE0E} \(heartRate)")
                .font(.stat(8.5, weight: hrWeight))
                .foregroundStyle(hrColor)
        }
    }
}

struct BigStat: View {
    var value: String
    var label: String
    var valueColor: Color = Theme.ink
    var size: CGFloat = 21
    var labelSize: CGFloat = 7.5

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.stat(size))
                .foregroundStyle(valueColor)
                .lineLimit(1)
            Text(label).kicker(labelSize, tracking: 0.12)
        }
    }
}

/// Auto kilometer alert — shows for 5 s over the run screen.
struct KilometerAlertView: View {
    var alert: RunSession.KilometerAlert

    var body: some View {
        VStack(spacing: 0) {
            Text("KILOMETER").kicker(8.5, tracking: 0.16)
            Text("\(alert.km)")
                .font(.stat(65))
                .kerning(-3.25)
                .padding(.top, 3)
            Text(Format.pace(alert.splitSeconds))
                .font(.stat(20))
                .foregroundStyle(Theme.signal)
                .padding(.top, 10)
            Text("\(Format.paceDelta(alert.deltaVsAvg)) vs avg")
                .font(.stat(8, weight: .regular))
                .foregroundStyle(Theme.muted)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }
}

struct PausedView: View {
    @ObservedObject var session: RunSession
    var onEnd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RunHeader(
                title: "PAUSED", titleColor: Theme.signal, titleWeight: .semibold,
                heartRate: session.heartRate
            )

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 0) {
                Text(Format.clock(session.elapsed))
                    .font(.stat(42))
                    .kerning(-1.9)
                    .foregroundStyle(Theme.dim)
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    StatInline(value: Format.km(session.distanceKm), unit: "km", size: 13, color: Theme.dim)
                    StatInline(value: Format.pace(session.averagePace), unit: "/km", size: 13, color: Theme.dim)
                }
                .padding(.top, 8)
            }

            Spacer(minLength: 0)

            // Design ratio: End 1 : Resume 1.4.
            GeometryReader { proxy in
                let endWidth = (proxy.size.width - 7) / 2.4
                HStack(spacing: 7) {
                    Button(action: onEnd) {
                        Text("End")
                            .font(.sg(11, weight: .semibold))
                            .frame(width: endWidth, height: 40)
                            .background(Theme.button, in: Capsule())
                            .overlay(Capsule().stroke(Theme.buttonBorder, lineWidth: 0.5))
                    }
                    Button(action: { session.resume() }) {
                        Text("Resume")
                            .font(.sg(11, weight: .bold))
                            .foregroundStyle(Theme.bg)
                            .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40)
                            .background(Theme.signal, in: Capsule())
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(height: 40)
        }
        .padding(EdgeInsets(top: 2, leading: 22, bottom: 23, trailing: 22))
    }
}
