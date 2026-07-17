import SwiftUI

struct LogView: View {
    @EnvironmentObject private var store: RunStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Runs")
                        .font(.sg(26, weight: .semibold))
                        .kerning(-0.5)
                    Spacer()
                    if let current = store.runsByMonth.first {
                        Text(monthLine(current, upper: false))
                            .font(.stat(12, weight: .regular))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 20)

                Theme.hairline.frame(height: 1)

                ForEach(Array(store.runsByMonth.enumerated()), id: \.element.month) { index, group in
                    if index > 0 {
                        Text(monthLine(group, upper: true))
                            .kicker(12)
                            .padding(.horizontal, 28)
                            .padding(.top, 14)
                            .padding(.bottom, 6)
                    }
                    ForEach(group.runs) { run in
                        NavigationLink(value: run) { LogRow(run: run) }
                            .buttonStyle(.plain)
                        Theme.hairline.frame(height: 1)
                    }
                }
            }
            .padding(.top, 26)
        }
        .background(Theme.bg)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: Run.self) { RunDetailView(run: $0) }
    }

    private func monthLine(_ group: (month: Date, runs: [Run]), upper: Bool) -> String {
        let name = group.month.formatted(.dateTime.month(.wide))
        let km = group.runs.reduce(0) { $0 + $1.distanceKm }
        let text = "\(name) · \(Format.km(km, decimals: 1)) km"
        return upper ? text.uppercased() : text
    }
}

struct LogRow: View {
    var run: Run

    /// The design flags standout paces in Signal — anything under 5:10.
    private var isFast: Bool { run.paceSecPerKm < 310 }

    var body: some View {
        HStack(spacing: 14) {
            Text(run.date.formatted(.dateTime.weekday(.abbreviated)).uppercased()
                 + "\n" + run.date.formatted(.dateTime.day(.twoDigits).month(.twoDigits)))
                .font(.sg(11))
                .foregroundStyle(Theme.muted)
                .lineSpacing(3)
                .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if run.type == .trail {
                        TriangleMark()
                            .fill(Theme.signal)
                            .frame(width: 9, height: 8)
                    }
                    Text("\(Format.km(run.distanceKm)) km").font(.stat(16))
                }
                Text("\(Format.clock(run.duration)) · \(run.avgHR) bpm")
                    .font(.stat(11.5, weight: .regular))
                    .foregroundStyle(Theme.muted)
            }

            Spacer()

            Text(Format.pace(run.paceSecPerKm))
                .font(.stat(16))
                .foregroundStyle(isFast ? Theme.signal : Theme.ink)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 28)
        .contentShape(Rectangle())
    }
}
