import XCTest

/// Does the log scroll on the *first* try?
///
/// Andi, CUR-38: "Im Log geht oft das Scrollen nicht, dann muss man zwei oder
/// dreimal mit dem Finger ansetzen." Every row carries a drag gesture for
/// swipe-to-delete, sharing the touch with the scroll view — and a gesture that
/// takes the touch and then decides it did not want it is exactly how a scroll
/// gets eaten. Nothing but a real finger can show this: the gesture is the
/// subject, so a unit test has nothing to say and a screenshot even less.
final class LogScrollUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-demo", "1", "-tab", "log"]
        app.launch()
    }

    /// Bound by index rather than `firstMatch`: this has to stay the *same*
    /// row across the scroll, and `firstMatch` re-resolves to whatever is
    /// topmost afterwards.
    private var topRow: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "log-row").element(boundBy: 0)
    }

    /// The control: the same scroll, started from the screen rather than from a
    /// row. If this moves and the row-anchored one does not, the row's gesture
    /// is the thing eating it — and that is the whole diagnosis.
    func testTheLogScrollsWhenTheSwipeDoesNotStartOnARow() {
        XCTAssertTrue(topRow.waitForExistence(timeout: 10), "the log did not render a run")
        let before = topRow.frame.origin.y
        app.swipeUp()
        let moved = before - topRow.frame.origin.y
        XCTAssertGreaterThan(moved, 80, "even a screen-level swipe moved only \(moved) pt")
    }

    func testOneSwipeUpScrollsTheLog() {
        XCTAssertTrue(topRow.waitForExistence(timeout: 10), "the log did not render a run")
        let before = topRow.frame.origin.y

        app.descendants(matching: .any).matching(identifier: "log-row")
            .element(boundBy: 1).swipeUp()

        let after = topRow.frame.origin.y
        XCTAssertLessThan(after, before - 80,
                          "one swipe moved the log by \(before - after) pt — it did not scroll")
    }

    /// The same swipe, ten times over, from a row each time. One eaten scroll
    /// in ten is the complaint; a single pass can pass by luck.
    func testTenSwipesInARowAllScroll() {
        XCTAssertTrue(topRow.waitForExistence(timeout: 10), "the log did not render a run")
        var eaten = 0
        for attempt in 1...10 {
            let rows = app.descendants(matching: .any).matching(identifier: "log-row")
            guard let anchor = rows.allElementsBoundByIndex.first(where: { $0.isHittable }) else {
                return XCTFail("no row on screen to swipe from")
            }
            let before = anchor.frame.origin.y
            anchor.swipeUp()
            let moved = before - anchor.frame.origin.y
            if moved < 80 {
                eaten += 1
                print("swipe \(attempt) moved only \(moved) pt")
            }
            // Back to the top, so every attempt starts from the same place and
            // none of them can run out of log to scroll. From the screen rather
            // than from a row: the row that was at the top is off screen now.
            app.swipeDown()
            app.swipeDown()
        }
        XCTAssertEqual(eaten, 0, "\(eaten) of 10 swipes did not scroll the log")
    }
}
