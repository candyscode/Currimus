import WidgetKit
import SwiftUI

@main
struct CurrimusWidgets: WidgetBundle {
    var body: some Widget {
        WeekWidget()
    }
}

struct WeekEntry: TimelineEntry {
    var date: Date
    var weekKm: Double
    var goalKm: Double
    var lastPace: TimeInterval
    var runCount: Int
}

struct WeekProvider: TimelineProvider {
    private func entry() -> WeekEntry {
        let store = RunStore()
        return WeekEntry(
            date: .now,
            weekKm: store.weekKm,
            goalKm: store.weeklyGoalKm,
            lastPace: store.lastRun?.paceSecPerKm ?? 0,
            runCount: store.runs(inWeekOf: .now).count
        )
    }

    func placeholder(in context: Context) -> WeekEntry { entry() }

    func getSnapshot(in context: Context, completion: @escaping (WeekEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(1800))))
    }
}

/// Weekly km vs goal — quiet accountability. Circular complication and
/// Smart Stack card.
struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CurrimusWeek", provider: WeekProvider()) { entry in
            WeekWidgetView(entry: entry)
                .containerBackground(Theme.bg, for: .widget)
        }
        .configurationDisplayName("This Week")
        .description("Weekly kilometers against your goal.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct WeekWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: WeekEntry

    var body: some View {
        switch family {
        case .accessoryRectangular: rectangular
        case .accessoryInline: Text("C · \(Format.km(entry.weekKm, decimals: 1)) km this week")
        default: circular
        }
    }

    private var circular: some View {
        VStack(spacing: 2) {
            Text("WEEK")
                .font(.system(size: 7, weight: .medium))
                .kerning(0.8)
                .foregroundStyle(Theme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(Int(entry.weekKm))").font(.stat(17))
                Text("km").font(.system(size: 9)).foregroundStyle(Theme.muted)
            }
            ProgressCapsule(fraction: entry.weekKm / max(entry.goalKm, 1))
                .frame(width: 30, height: 3)
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("THIS WEEK")
                    .font(.system(size: 8, weight: .medium))
                    .kerning(0.9)
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text("C").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.signal)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Format.km(entry.weekKm, decimals: 1)).font(.stat(19))
                Text("of \(Int(entry.goalKm)) km").font(.system(size: 9)).foregroundStyle(Theme.muted)
                Spacer()
                Text("last \(Format.pace(entry.lastPace)) /km")
                    .font(.stat(9, weight: .regular))
                    .foregroundStyle(Theme.muted)
            }
            ProgressCapsule(fraction: entry.weekKm / max(entry.goalKm, 1))
                .frame(height: 4)
        }
    }
}

struct ProgressCapsule: View {
    var fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(Theme.signal)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
    }
}
