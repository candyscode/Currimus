import WidgetKit
import SwiftUI

// The bundle, the timeline providers and the widget configurations. The views
// they render live in `WidgetSurfaces.swift`, which the watch app compiles too.

@main
struct CurrimusWidgets: WidgetBundle {
    init() {
        FontLoader.registerAll()
    }

    var body: some Widget {
        WeekWidget()
        DistanceWidget()
    }
}

struct WeekProvider: TimelineProvider {
    private func entry() -> WeekEntry {
        // Reads the shared defaults directly rather than building a RunStore:
        // a timeline provider has no business activating WatchConnectivity,
        // and the store is main-actor bound.
        let snapshot = WeekSnapshot.current()
        return WeekEntry(
            date: .now,
            weekKm: snapshot.weekKm,
            goalKm: snapshot.goalKm,
            lastPace: snapshot.lastPace,
            runCount: snapshot.runCount
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

struct DistanceProvider: TimelineProvider {
    private func entry() -> DistanceEntry {
        DistanceEntry(date: .now, totals: DistanceTotals.current())
    }

    func placeholder(in context: Context) -> DistanceEntry { entry() }

    func getSnapshot(in context: Context, completion: @escaping (DistanceEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DistanceEntry>) -> Void) {
        // Same half-hour cadence as the week widget. Both are cheap reads of
        // the app group, and neither number can move without the app having
        // run — a finished run refreshes the timelines directly.
        completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(1800))))
    }
}

/// Week, month and year distance side by side — no goals, no judgement, just
/// how far the legs have carried you over three horizons.
struct DistanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CurrimusDistance", provider: DistanceProvider()) { entry in
            DistanceWidgetView(entry: entry)
                .containerBackground(Theme.bg, for: .widget)
        }
        .configurationDisplayName("Distance")
        .description("Kilometers run this week, this month and this year.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}
