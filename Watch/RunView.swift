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
        VStack(alignment: .leading, spacing: 0) {
            RunHeader(
                title: session.currentZone >= 5 ? "MAX" : "RUN",
                titleColor: session.currentZone >= 5 ? Theme.signal : Theme.muted,
                heartRate: session.heartRate,
                hrColor: session.currentZone >= 5 ? Theme.signal : Theme.muted
            )

            Spacer(minLength: 0)

            Text(Format.clock(session.elapsed))
                .font(.stat(46))
                .kerning(-1)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            HStack(alignment: .top, spacing: 18) {
                BigStat(value: Format.km(session.distanceKm), label: "KM")
                BigStat(value: Format.pace(session.rollingPace), label: "PACE /KM", valueColor: Theme.signal)
            }
            .padding(.top, 8)

            Spacer(minLength: 0)

            ZoneBar(zone: session.currentZone)
            HStack {
                Text("ZONE").kicker(8)
                Spacer()
                Text("\(session.currentZone)")
                    .font(.stat(9))
                    .foregroundStyle(session.currentZone >= 3 ? Theme.signal : Theme.ink)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 4)
    }
}

struct RunHeader: View {
    var title: String
    var titleColor: Color = Theme.muted
    var heartRate: Int
    var hrColor: Color = Theme.muted

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).kicker(9, color: titleColor)
            Spacer()
            Text("♥ \(heartRate)")
                .font(.stat(10, weight: .regular))
                .foregroundStyle(hrColor)
        }
    }
}

struct BigStat: View {
    var value: String
    var label: String
    var valueColor: Color = Theme.ink
    var size: CGFloat = 21

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.stat(size))
                .foregroundStyle(valueColor)
                .lineLimit(1)
            Text(label).kicker(7)
        }
    }
}

/// Auto kilometer alert — shows for 5 s over the run screen.
struct KilometerAlertView: View {
    var alert: RunSession.KilometerAlert

    var body: some View {
        VStack(spacing: 0) {
            Text("KILOMETER").kicker(9)
            Text("\(alert.km)")
                .font(.stat(62))
                .kerning(-2)
            Text(Format.pace(alert.splitSeconds))
                .font(.stat(20))
                .foregroundStyle(Theme.signal)
                .padding(.top, 6)
            Text("\(Format.paceDelta(alert.deltaVsAvg)) vs avg")
                .font(.stat(9, weight: .regular))
                .foregroundStyle(Theme.muted)
                .padding(.top, 2)
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
                title: "PAUSED", titleColor: Theme.signal,
                heartRate: session.heartRate
            )

            Spacer(minLength: 0)

            Text(Format.clock(session.elapsed))
                .font(.stat(37))
                .kerning(-1)
                .foregroundStyle(Theme.dim)
            HStack(spacing: 14) {
                StatInline(value: Format.km(session.distanceKm), unit: "km", size: 14)
                StatInline(value: Format.pace(session.averagePace), unit: "/km", size: 14)
            }
            .foregroundStyle(Theme.dim)
            .padding(.top, 4)

            Spacer(minLength: 0)

            HStack(spacing: 7) {
                Button(action: onEnd) {
                    Text("End")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Theme.button, in: Capsule())
                        .overlay(Capsule().stroke(Theme.buttonBorder, lineWidth: 1))
                }
                Button(action: { session.resume() }) {
                    Text("Resume")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.bg)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Theme.signal, in: Capsule())
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }
}
