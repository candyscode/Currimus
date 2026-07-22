import Foundation

/// The launch-argument switches that drive demo content and the screenshot
/// routes (`-demo 1`, `-screen run`, `-tab log`, …).
///
/// One place, and it reads nothing at all in a Release build: every accessor
/// is a compile-time `false`/`nil` there, so the branches behind them are dead
/// code the optimiser drops. That is what makes "release builds contain none
/// of this" true rather than merely intended — it used to be spread across
/// call sites, three of which read `UserDefaults` in release and could put a
/// shipped app into a state nobody ever tests.
///
/// Values are read as strings, not `bool(forKey:)`: launch arguments land in
/// their own defaults domain, where `-demo 1` arrives as the string "1" and
/// `bool(forKey:)` does not pick it up.
enum DebugFlags {
    #if DEBUG
    static func string(_ key: String) -> String? {
        UserDefaults.standard.string(forKey: key)
    }
    #else
    static func string(_ key: String) -> String? { nil }
    #endif

    private static func isSet(_ key: String) -> Bool { string(key) == "1" }

    /// Seed the sample log instead of loading the real one, and never persist.
    static var seedsDemoContent: Bool { isSet("demo") }
    /// Force the first-launch screen even with a log present.
    static var forcesEmptyState: Bool { isSet("empty") }
    /// Force the always-on reduced appearance; the simulator has no real one.
    static var forcesAlwaysOnReduced: Bool { isSet("aod") }

    /// watchOS: which run screen to jump into.
    static var screen: String? { string("screen") }

    /// watchOS: play a named `RunScenario` (`-simulate marathon`). With `-at N`
    /// it jumps to km N; with `-finish 1` it jumps to the end and shows the
    /// summary; with `-speed N` it plays live at N× real time; bare, it plays
    /// live at the default speed.
    static var simulate: String? { string("simulate") }
    static var simAtKm: Double? { string("at").flatMap(Double.init) }
    static var simSpeed: Double? { string("speed").flatMap(Double.init) }
    static var simFinish: Bool { string("finish") == "1" }
    /// iOS: which tab to open, which screen to push, which state to inject.
    static var tab: String? { string("tab") }
    static var push: String? { string("push") }
    static var zones: String? { string("zones") }
    static var home: String? { string("home") }
}
