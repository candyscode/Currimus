import SwiftUI

/// Always-On (wrist-down) support for the live run screens.
///
/// When the wrist drops during a workout the system dims the panel, holds the
/// LTPO display at 1 Hz and sets `isLuminanceReduced`. The app cannot set that
/// rate — it complies with it by not asking to redraw more often, and by
/// lighting fewer, dimmer pixels. On OLED a black pixel is an off pixel.
///
/// The reduced screen is deliberately *not* a different screen: every element
/// keeps its exact position, so a wrist-raise re-lights the same frame instead
/// of re-flowing it. (Design: "Watch Screens - Always-On".)

/// The redraw cadence for a live run.
///
/// Apple allows an app with an active workout session at most one update per
/// second while the wrist is down. We only ever render whole seconds, so 1 Hz
/// is also right when the wrist is up — asking for 30 Hz would burn power
/// redrawing pixels that cannot change.
struct RunMetricsSchedule: TimelineSchedule {
    var start: Date

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> PeriodicTimelineSchedule.Entries {
        PeriodicTimelineSchedule(from: start, by: 1).entries(from: startDate, mode: mode)
    }
}

/// Drives a live run screen: redraws on the workout cadence and publishes the
/// matching palette to everything inside.
///
/// `content` receives the elapsed time for the frame being drawn. It is read
/// at draw time rather than pushed from a timer, so the seconds stay correct
/// even though the app is only woken once a second with the wrist down.
struct RunTimeline<Content: View>: View {
    @ObservedObject var session: RunSession
    @Environment(\.isLuminanceReduced) private var systemDimmed
    @Environment(\.alwaysOnReduced) private var reducedEnabled
    @ViewBuilder var content: (TimeInterval) -> Content

    private var dimmed: Bool { (systemDimmed || AlwaysOn.forcedForDebug) && reducedEnabled }

    var body: some View {
        TimelineView(RunMetricsSchedule(start: session.startedAt)) { _ in
            content(session.displayElapsed)
                .environment(\.runPalette, RunPalette(dimmed: dimmed))
        }
    }
}

enum AlwaysOn {
    /// The watch simulator has no always-on state and `simctl` cannot set
    /// `isLuminanceReduced`, so `-aod 1` forces the reduced appearance to make
    /// it reviewable. The 1 Hz cadence itself only exists on real hardware.
    static var forcedForDebug: Bool {
        #if DEBUG
        // Read as a string like `-screen`: `bool(forKey:)` does not pick the
        // value up out of the launch-argument domain here.
        return UserDefaults.standard.string(forKey: "aod") == "1"
        #else
        return false
        #endif
    }
}
