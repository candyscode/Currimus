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
