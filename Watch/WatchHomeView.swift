import SwiftUI

/// One screen, three ways to run. Start stays primary; Trail and Pacer share
/// the quiet row.
struct WatchHomeView: View {
    var lastRun: Run?
    var onStart: () -> Void
    var onTrail: () -> Void
    var onPacer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The system clock owns the top-right corner on watchOS.
            Text("CURRIMUS")
                .font(.system(size: 12, weight: .bold))
                .kerning(0.8)

            Spacer(minLength: 0)

            if let run = lastRun {
                Text("LAST RUN").kicker(8)
                HStack(spacing: 12) {
                    StatInline(value: Format.km(run.distanceKm), unit: "km")
                    StatInline(value: Format.pace(run.paceSecPerKm), unit: "/km")
                }
                .padding(.top, 2)
            }

            VStack(spacing: 6) {
                Button(action: onStart) {
                    Text("Start")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.bg)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(Theme.signal, in: Capsule())
                }
                HStack(spacing: 6) {
                    Button(action: onTrail) {
                        HStack(spacing: 4) {
                            Text("▲").font(.system(size: 9)).foregroundStyle(Theme.signal)
                            Text("Trail").font(.system(size: 12, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(Theme.button, in: Capsule())
                        .overlay(Capsule().stroke(Theme.buttonBorder, lineWidth: 1))
                    }
                    Button(action: onPacer) {
                        Text("Pacer")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .background(Theme.button, in: Capsule())
                            .overlay(Capsule().stroke(Theme.buttonBorder, lineWidth: 1))
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
        }
        .padding(.horizontal, 4)
    }
}

struct StatInline: View {
    var value: String
    var unit: String
    var size: CGFloat = 15

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value).font(.stat(size))
            Text(unit)
                .font(.system(size: size * 0.58))
                .foregroundStyle(Theme.muted)
        }
    }
}

struct CountdownView: View {
    var count: Int

    var body: some View {
        VStack(spacing: 2) {
            Text("GET READY").kicker(9)
            Text("\(count)")
                .font(.stat(96))
                .foregroundStyle(Theme.signal)
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: count)
        }
    }
}
