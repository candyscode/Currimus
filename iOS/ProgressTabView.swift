import SwiftUI

struct ProgressTabView: View {
    @EnvironmentObject private var store: RunStore

    private let trend = SampleData.paceTrend

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Progress")
                    .font(.sg(26, weight: .semibold))
                    .kerning(-0.5)

                Text("AVG PACE · LAST 12 WEEKS").kicker(12).padding(.top, 26)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Format.pace(trend.last ?? 0))
                        .font(.stat(36))
                        .kerning(-1)
                    Text("/km").font(.sg(13)).foregroundStyle(Theme.muted)
                    Spacer()
                    Text("−\(Format.pace((trend.first ?? 0) - (trend.last ?? 0))) since April")
                        .font(.stat(13))
                        .foregroundStyle(Theme.signal)
                }
                .padding(.top, 8)

                PaceTrendChart(paces: trend)
                    .padding(.top, 16)
                HStack {
                    ForEach(["Apr", "May", "Jun", "Jul"], id: \.self) { month in
                        Text(month).font(.sg(11)).foregroundStyle(Theme.muted)
                        if month != "Jul" { Spacer() }
                    }
                }
                .padding(.top, 4)

                Divider().overlay(Theme.hairline).padding(.vertical, 26)

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Heart rate at 5:30 pace").font(.sg(14))
                        Text("Same effort, less work")
                            .font(.sg(11.5))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    (Text("143 ").foregroundStyle(Theme.ink)
                        + Text("−5").font(.stat(13)).foregroundStyle(Theme.signal))
                        .font(.stat(22))
                }

                Divider().overlay(Theme.hairline).padding(.vertical, 22)

                Text("MONTHLY KM").kicker(12).padding(.bottom, 14)
                MonthlyBars(totals: store.monthlyTotals(count: 6))

                Divider().overlay(Theme.hairline).padding(.top, 24)

                NavigationLink(value: "records") {
                    HStack {
                        Text("Records").font(.sg(14))
                        Spacer()
                        Text("\(store.records.first?.value ?? "") 5k ›")
                            .font(.stat(14, weight: .regular))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.top, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(28)
        }
        .background(Theme.bg)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: String.self) { destination in
            if destination == "records" { RecordsView() }
        }
    }
}

struct PaceTrendChart: View {
    /// Sec/km, oldest first. Slower is drawn lower.
    var paces: [TimeInterval]

    var body: some View {
        let top = (paces.max() ?? 1) + 8
        let bottom = (paces.min() ?? 0) - 8
        let points = paces.enumerated().map { index, pace in
            CGPoint(
                x: Double(index) / Double(max(paces.count - 1, 1)),
                y: (pace - bottom) / (top - bottom)
            )
        }
        return ZStack(alignment: .topLeading) {
            VStack {
                ForEach(0..<3, id: \.self) { line in
                    Theme.hairline.frame(height: 1)
                    if line < 2 { Spacer() }
                }
            }
            LineChart(points: points)
                .stroke(Theme.signal, style: .init(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            GeometryReader { proxy in
                if let last = points.last {
                    Circle().fill(Theme.signal).frame(width: 9, height: 9)
                        .position(
                            x: last.x * proxy.size.width,
                            y: (1 - last.y) * proxy.size.height
                        )
                }
                Text(Format.pace(top)).font(.stat(9, weight: .regular)).foregroundStyle(Theme.faint)
                    .position(x: 14, y: 6)
                Text(Format.pace(bottom)).font(.stat(9, weight: .regular)).foregroundStyle(Theme.faint)
                    .position(x: 14, y: proxy.size.height - 6)
            }
        }
        .frame(height: 100)
    }
}

struct MonthlyBars: View {
    var totals: [(month: Date, km: Double)]

    var body: some View {
        let maxKm = max(totals.map(\.km).max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(totals.enumerated()), id: \.offset) { index, item in
                let isCurrent = index == totals.count - 1
                VStack(spacing: 7) {
                    Text("\(Int(item.km))")
                        .font(.stat(11, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? Theme.signal : Theme.muted)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isCurrent ? Theme.signal : Theme.track)
                        .frame(height: max(item.km / maxKm * 66, 4))
                    Text(item.month.formatted(.dateTime.month(.abbreviated)))
                        .font(.sg(11, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? Theme.ink : Theme.muted)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct RecordsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: RunStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(title: "Progress") { dismiss() }

                Text("Records")
                    .font(.sg(26, weight: .semibold))
                    .kerning(-0.5)
                    .padding(.top, 16)

                if let newest = store.records.first(where: \.isNew) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("NEW · \(newest.label.uppercased())").kicker(12, color: Theme.signal)
                            Spacer()
                            Text(newest.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                .font(.sg(12))
                                .foregroundStyle(Theme.muted)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(newest.value).font(.stat(40)).kerning(-1)
                            Text(newest.delta ?? "")
                                .font(.stat(13, weight: .regular))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(.vertical, 20)
                    .padding(.horizontal, 22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cardBorder, lineWidth: 1))
                    .padding(.top, 22)
                }

                VStack(spacing: 0) {
                    ForEach(Array(store.records.filter { !$0.isNew }.enumerated()), id: \.element.id) { index, record in
                        if index > 0 { Theme.hairline.frame(height: 1) }
                        HStack(alignment: .firstTextBaseline) {
                            Text(record.label).font(.sg(14))
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(record.value).font(.stat(17))
                                Text(record.date.formatted(.dateTime.day().month(.abbreviated)))
                                    .font(.sg(11))
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                        .padding(.vertical, 16)
                    }
                }
                .padding(.top, 18)

                Text("Records come from your runs automatically. No badges, no confetti.")
                    .font(.sg(12))
                    .foregroundStyle(Theme.muted)
                    .lineSpacing(3)
                    .padding(.top, 14)
            }
            .padding(28)
        }
        .background(Theme.bg)
        .toolbar(.hidden, for: .navigationBar)
    }
}
