import SwiftUI

/// One screen, three ways to run. Start stays primary; Trail and Pacer share
/// the quiet row. The design's "9:41" slot belongs to the system clock.
struct WatchHomeView: View {
    var lastRun: Run?
    var onStart: () -> Void
    var onTrail: () -> Void
    var onPacer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CURRIMUS")
                .font(.sg(9.5, weight: .bold))
                .kerning(9.5 * 0.06)

            Spacer(minLength: 0)

            if let run = lastRun {
                Text("LAST RUN").kicker(7.5)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    StatInline(value: Format.km(run.distanceKm), unit: "km")
                    StatInline(value: Format.pace(run.paceSecPerKm), unit: "/km")
                }
                .padding(.top, 4)
            }

            VStack(spacing: 6) {
                Button(action: onStart) {
                    Text("Start")
                        .font(.sg(12, weight: .bold))
                        .foregroundStyle(Theme.bg)
                        .frame(maxWidth: .infinity, minHeight: 39, maxHeight: 39)
                        .background(Theme.signal, in: Capsule())
                }
                HStack(spacing: 6) {
                    Button(action: onTrail) {
                        HStack(spacing: 4) {
                            TriangleMark()
                                .fill(Theme.signal)
                                .frame(width: 7, height: 6)
                            Text("Trail").font(.sg(9, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 29, maxHeight: 29)
                        .background(Theme.button, in: Capsule())
                        .overlay(Capsule().stroke(Theme.buttonBorder, lineWidth: 0.5))
                    }
                    Button(action: onPacer) {
                        Text("Pacer")
                            .font(.sg(9, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 29, maxHeight: 29)
                            .background(Theme.button, in: Capsule())
                            .overlay(Capsule().stroke(Theme.buttonBorder, lineWidth: 0.5))
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 13)
        }
        .padding(EdgeInsets(top: 2, leading: 22, bottom: 23, trailing: 22))
    }
}

struct StatInline: View {
    var value: String
    var unit: String
    var size: CGFloat = 12
    var color: Color = Theme.ink

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value).font(.stat(size)).foregroundStyle(color)
            Text(unit)
                .font(.sg(size * 0.58))
                .foregroundStyle(Theme.muted)
        }
    }
}

struct CountdownView: View {
    var count: Int

    var body: some View {
        VStack(spacing: 4) {
            Text("GET READY").kicker(7.5, tracking: 0.2)
            Text("\(count)")
                .font(.stat(100))
                .kerning(-5)
                .foregroundStyle(Theme.signal)
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: count)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
