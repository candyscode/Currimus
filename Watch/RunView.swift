import SwiftUI

/// The one glance: time, distance, pace, zone. The screen title lives in
/// content ("RUN" / "MAX"); the system clock owns the top line.
/// Tap to pause (the both-buttons hardware gesture pauses too).
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
        // Caption owned by the container so both Run and Pacer show it — a
        // consistent nav bar keeps their heroes at the same height. Hidden
        // while the kilometer alert owns the whole canvas.
        .topBarCaption {
            if session.kilometerAlert == nil {
                switch session.type {
                case .pacer:
                    TopBarCaption(text: "PACER")
                default:
                    if session.currentZone >= 5 {
                        TopBarCaption(text: "MAX", color: Theme.signal)
                    } else {
                        TopBarCaption(text: "RUN")
                    }
                }
            }
        }
    }

    private var quickRun: some View {
        let zone = session.currentZone
        return RunScaffold {
            VStack(alignment: .leading, spacing: 0) {
                Text(Format.clock(session.elapsed))
                    .font(.stat(52))
                    .kerning(-2.3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .animation(.linear(duration: 0.25), value: session.elapsed)
                HStack(alignment: .top, spacing: 20) {
                    BigStat(value: Format.km(session.distanceKm), label: "KM", size: 22)
                    BigStat(value: Format.pace(session.rollingPace), label: "PACE /KM", valueColor: Theme.signal, size: 22)
                }
                .padding(.top, 12)
            }
        } footer: {
            ZoneFooter(zone: zone)
        }
    }
}

struct BigStat: View {
    var value: String
    var label: String
    var valueColor: Color = Theme.ink
    var size: CGFloat = 21
    var labelSize: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.stat(size))
                .foregroundStyle(valueColor)
                .lineLimit(1)
            Text(label)
                .kicker(labelSize, color: Theme.bright, tracking: 0.1)
                .lineLimit(1)
                .fixedSize()
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
                .font(.stat(8.5, weight: .regular))
                .foregroundStyle(Theme.bright)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }
}

/// Same screen in every mode.
struct PausedView: View {
    @ObservedObject var session: RunSession
    var onEnd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(Format.clock(session.elapsed))
                    .font(.stat(42))
                    .kerning(-1.9)
                    .foregroundStyle(Theme.dim)
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    StatInline(value: Format.km(session.distanceKm), unit: "km", size: 15, color: Theme.dim)
                    StatInline(value: Format.pace(session.averagePace), unit: "/km", size: 15, color: Theme.dim)
                }
                .padding(.top, 8)
            }

            Spacer(minLength: 12)

            // Design ratio: End 1 : Resume 1.4.
            GeometryReader { proxy in
                let endWidth = (proxy.size.width - 8) / 2.4
                HStack(spacing: 8) {
                    Button(action: onEnd) {
                        Text("End")
                            .font(.sg(15, weight: .semibold))
                            .frame(width: endWidth, height: 50)
                            .background(Theme.button, in: Capsule())
                            .overlay(Capsule().stroke(Theme.buttonBorder, lineWidth: 0.75))
                    }
                    Button(action: { session.resume() }) {
                        Text("Resume")
                            .font(.sg(15, weight: .bold))
                            .foregroundStyle(Theme.bg)
                            .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
                            .background(Theme.signal, in: Capsule())
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(height: 50)
        }
        .padding(EdgeInsets(top: 6, leading: 20, bottom: 16, trailing: 20))
        .topBarCaption { TopBarCaption(text: "PAUSED", color: Theme.signal) }
    }
}
