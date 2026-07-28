import XCTest

/// The log's swipe-to-delete, driven by an actual finger.
///
/// This exists because the gesture broke twice and nothing could catch it: a
/// unit test cannot express a drag, `simctl` cannot inject one, and a
/// screenshot only shows a resting state. Both failures had the same shape —
/// the row slid open under the finger and snapped shut on release, so the
/// button was on screen and impossible to hit. `isHittable` after the swipe is
/// precisely that assertion.
final class SwipeToDeleteUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // The demo log, opened on the Log tab: deterministic content, and
        // nothing of the user's own is touched.
        app.launchArguments = ["-demo", "1", "-tab", "log"]
        app.launch()
    }

    /// The first row of the log — the newest run, whatever today's demo data
    /// happens to make it. Matched by identifier rather than by its text: the
    /// screen's own header ends in " km" too, and swiping that does nothing at
    /// all, which is a confusing way for this test to fail.
    private var firstRow: XCUIElement {
        let row = app.descendants(matching: .any).matching(identifier: "log-row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the log did not render a run")
        return row
    }

    func testSwipingARowLeftRevealsADeleteButtonThatCanBeTapped() {
        firstRow.swipeLeft()

        let delete = app.buttons["swipe-action"]
        XCTAssertTrue(delete.waitForExistence(timeout: 2), "the swipe revealed nothing")
        // The whole bug: it was there, and it went away again before it could
        // be pressed.
        XCTAssertTrue(delete.isHittable, "the delete tile is on screen but cannot be hit")

        delete.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 2),
                      "pressing delete did not ask for confirmation")
    }

    func testTheRevealedRowStaysOpenUntilItIsDismissed() {
        firstRow.swipeLeft()
        let delete = app.buttons["swipe-action"]
        XCTAssertTrue(delete.waitForExistence(timeout: 2))

        // A second of doing nothing at all must not close it.
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(delete.isHittable, "the row closed on its own")

        // A tap on the row puts it away rather than opening the run.
        firstRow.tap()
        XCTAssertFalse(delete.isHittable, "a tap on an open row should close it")
        XCTAssertFalse(app.navigationBars.buttons.firstMatch.exists,
                       "closing the row must not also push the run detail")
    }

    func testTappingAClosedRowOpensTheRun() {
        firstRow.tap()
        // The detail screen leads with the run's name and a back button; the
        // filter chips of the log are gone.
        XCTAssertFalse(app.buttons["All"].waitForExistence(timeout: 2),
                       "tapping a row did not leave the log")
    }
}
