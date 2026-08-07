import XCTest

/// What the complications read out of the app group.
///
/// A widget provider never builds a `RunStore`, so nothing else covers these
/// buckets — and a widget that disagrees with the screen behind it is worse
/// than no widget. The week is Monday-first (`Calendar.runWeek`); month and
/// year follow the device calendar, exactly as `RunStore` does.
final class WidgetSnapshotTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults.standard

    override func setUp() {
        super.setUp()
        suiteName = "com.currimus.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func run(_ km: Double, _ date: Date) -> Run {
        Run(date: date, name: "Run", distanceKm: km, duration: km * 300, avgHR: 150)
    }

    private func write(_ runs: [Run], key: String = AppDefaults.runsKey) {
        defaults.set(try! JSONEncoder().encode(runs), forKey: key)
    }

    private func push(_ totals: DistanceTotals) {
        defaults.set(try! JSONEncoder().encode(totals), forKey: AppDefaults.totalsKey)
    }

    // MARK: - What the iPhone pushes

    /// The watch cannot add these up itself — its HealthKit store holds what it
    /// recorded plus a short synced window, not a history (CUR-46). So when the
    /// phone has spoken, its numbers win outright over anything the watch could
    /// work out from its own log.
    func testThePhonesTotalsReplaceTheWatchsOwnArithmetic() {
        let now = Date()
        write([run(6, now)])
        push(DistanceTotals(weekKm: 42, monthKm: 180, yearKm: 1400,
                            pushedAt: now.addingTimeInterval(60)))
        let totals = DistanceTotals.current(defaults: defaults, now: now)
        XCTAssertEqual(totals.yearKm, 1400, accuracy: 0.001)
        XCTAssertEqual(totals.weekKm, 42, accuracy: 0.001,
                       "the local run is older than the push, so it is already in it")
    }

    /// A run recorded on the watch after the last push is the one thing the
    /// watch knows and the phone does not yet. It counts on top, so a run
    /// finished on the walk home shows before the phone has heard about it.
    func testARunNewerThanThePushIsAddedOnTop() {
        let now = Date()
        push(DistanceTotals(weekKm: 42, monthKm: 180, yearKm: 1400,
                            pushedAt: now.addingTimeInterval(-3600)))
        write([run(8, now)])
        let totals = DistanceTotals.current(defaults: defaults, now: now)
        XCTAssertEqual(totals.weekKm, 50, accuracy: 0.001)
        XCTAssertEqual(totals.yearKm, 1408, accuracy: 0.001)
    }

    /// Never twice. The push carries the moment it was taken, and everything at
    /// or before it is already counted in the numbers beside it.
    func testARunOlderThanThePushIsNotCountedTwice() {
        let now = Date()
        let earlier = now.addingTimeInterval(-7200)
        write([run(9, earlier)])
        push(DistanceTotals(weekKm: 9, monthKm: 9, yearKm: 9, pushedAt: now))
        let totals = DistanceTotals.current(defaults: defaults, now: now)
        XCTAssertEqual(totals.weekKm, 9, accuracy: 0.001)
    }

    /// A watch that has never heard from a phone still shows what it has.
    /// Short is better than blank.
    func testWithoutAPushTheWatchFallsBackToItsOwnLog() {
        let now = Date()
        write([run(6, now)])
        XCTAssertEqual(DistanceTotals.current(defaults: defaults, now: now).weekKm,
                       6, accuracy: 0.001)
    }

    // MARK: - Distance totals

    func testTotalsBucketRunsIntoWeekMonthAndYear() {
        // A Wednesday, deliberately mid-week and mid-month so every bucket has
        // room on both sides of "now".
        let now = DateComponents(calendar: .runWeek, year: 2026, month: 8, day: 5, hour: 12).date!
        write([
            run(10, now.addingTimeInterval(-86_400)),          // Tuesday, this week
            run(5, now.addingTimeInterval(-4 * 86_400)),       // Saturday before — last week, this month
            run(7, now.addingTimeInterval(-40 * 86_400)),      // June — this year only
            run(100, now.addingTimeInterval(-400 * 86_400)),   // last year — counted nowhere
        ])
        let totals = DistanceTotals.current(defaults: defaults, now: now)
        XCTAssertEqual(totals.weekKm, 10, accuracy: 0.001)
        XCTAssertEqual(totals.monthKm, 15, accuracy: 0.001)
        XCTAssertEqual(totals.yearKm, 22, accuracy: 0.001)
    }

    /// The Sunday of a running week belongs to the week that started six days
    /// earlier, not to the one starting the next day. `Calendar.current` would
    /// put it in the following week in en_US, and the widget would then
    /// disagree with every weekly total in the app.
    func testTheWeekIsMondayFirst() {
        let sunday = DateComponents(calendar: .runWeek, year: 2026, month: 8, day: 9, hour: 20).date!
        let monday = DateComponents(calendar: .runWeek, year: 2026, month: 8, day: 3, hour: 7).date!
        write([run(12, sunday), run(8, monday)])
        let totals = DistanceTotals.current(defaults: defaults, now: sunday)
        XCTAssertEqual(totals.weekKm, 20, accuracy: 0.001)
    }

    /// Imported runs count towards every total, the same union `RunStore`
    /// serves the app from — a widget that ignored Apple Health would read low
    /// for anyone who also runs with another app.
    func testTotalsIncludeImportedRuns() {
        let now = Date()
        write([run(6, now)])
        write([run(4, now)], key: AppDefaults.importedKey)
        let totals = DistanceTotals.current(defaults: defaults, now: now)
        XCTAssertEqual(totals.weekKm, 10, accuracy: 0.001)
        XCTAssertEqual(totals.yearKm, 10, accuracy: 0.001)
    }

    func testTotalsAreZeroWithoutARun() {
        XCTAssertEqual(DistanceTotals.current(defaults: defaults), .placeholder)
    }

    /// The widget's year total can only be right if the importer reads back at
    /// least a year — and its month total needs the month before this one, so
    /// a window measured in whole months has to clear thirteen (CUR-46). The
    /// recovery window is a different thing entirely: a safety net for a
    /// transfer that failed, not a second importer.
    func testTheImportWindowCoversAWholeYear() {
        let now = DateComponents(calendar: .runWeek, year: 2026, month: 8, day: 5).date!
        let start = HealthImport.importWindowStart(from: now)
        let months = Calendar.current.dateComponents([.month], from: start, to: now).month ?? 0
        XCTAssertGreaterThanOrEqual(months, 13)
        XCTAssertLessThan(HealthImport.recoveryWindowDays, 365,
                          "the recovery window is not the import window — see recoverOwnRuns")
    }

    // MARK: - Formatting

    /// Under 100 km a tenth is worth reading; past it, four glyphs plus a point
    /// plus a decimal do not fit a third of a rectangular complication.
    func testCompactDropsTheDecimalPastAHundred() {
        XCTAssertEqual(Format.compactKm(7), "7.0")
        XCTAssertEqual(Format.compactKm(84.24), "84.2")
        XCTAssertEqual(Format.compactKm(1204.4), "1204")
    }

    // MARK: - The week snapshot

    func testWeekSnapshotFallsBackToTheDefaultGoal() {
        let snapshot = WeekSnapshot.current(defaults: defaults)
        XCTAssertEqual(snapshot.goalKm, WeekSnapshot.placeholder.goalKm)
        XCTAssertEqual(snapshot.weekKm, 0)
    }
}
