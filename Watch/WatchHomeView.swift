import SwiftUI

/// One screen, three ways to run. Start stays primary; Trail and Pacer share
/// the quiet row. The system clock owns the top line (watchOS 10 rule) —
/// the wordmark lives in content. Big, edge-to-edge tap targets.
struct WatchHomeView: View {
    var onStart: () -> Void
    var onTrail: () -> Void
    var onPacer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CURRIMUS")
                .font(.sg(20, weight: .bold))
                .kerning(20 * 0.04)
                .padding(.top, 4)

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                Button(action: onStart) {
                    Text("Start")
                        .font(.sg(19, weight: .bold))
                        .foregroundStyle(Theme.bg)
                        .frame(maxWidth: .infinity, minHeight: 62, maxHeight: 62)
                        .background(Theme.signal, in: Capsule())
                }
                HStack(spacing: 8) {
                    Button(action: onTrail) {
                        HStack(spacing: 6) {
                            TriangleMark()
                                .fill(Theme.signal)
                                .frame(width: 10, height: 9)
                            Text("Trail").font(.sg(15, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
                        .background(Theme.button, in: Capsule())
                        .overlay(Capsule().stroke(Theme.buttonBorder, lineWidth: 0.75))
                    }
                    Button(action: onPacer) {
                        Text("Pacer")
                            .font(.sg(15, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
                            .background(Theme.button, in: Capsule())
                            .overlay(Capsule().stroke(Theme.buttonBorder, lineWidth: 0.75))
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
        }
        .padding(EdgeInsets(top: 2, leading: 12, bottom: 12, trailing: 12))
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
                .font(.sg(size * 0.66))
                .foregroundStyle(Theme.bright)
        }
    }
}

struct CountdownView: View {
    var count: Int

    var body: some View {
        VStack(spacing: 4) {
            Text("GET READY").kicker(7.5, tracking: 0.2)
            Text("\(count)")
                .font(.stat(85))
                .kerning(-4.25)
                .foregroundStyle(Theme.signal)
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: count)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
