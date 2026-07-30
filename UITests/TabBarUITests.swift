import XCTest

/// The tab bar around a pushed screen.
///
/// It stays there. CUR-36 #3 reported about half a second of empty space where
/// the bar goes after tapping Back, and the cause turned out to be the hiding
/// itself: SwiftUI restores the bar long after the pop animation has finished
/// and then snaps it in with no animation at all. Timed off a 60 Hz screen
/// recording frame by frame — 0.48 s in the simulator, 0.33 s on Andi's device.
/// Not hiding it is what removes that, and it is the platform's own default.
///
/// The timing itself is **not** asserted here, because this harness cannot see
/// it: `XCUIElement.tap()` returns only once the app has gone quiet, so any
/// measurement around it is dominated by that. It read 1.81 s against 1.82 s
/// for two implementations that differ plainly on screen. What is pinned below
/// is the decision, not the milliseconds.
///
/// The marking-mode case is not hypothetical either — it broke while looking
/// for the timing fix, because two `toolbar(_:for: .tabBar)` declarations in
/// one stack do not compose and the outer one silently wins.
final class TabBarUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ arguments: [String]) {
        app.launchArguments = ["-demo", "1"] + arguments
        app.launch()
    }

    /// The bar is there on the way in and on the way out, so there is no moment
    /// where it is missing — which was the whole complaint.
    func testTheTabBarStaysThroughAPushAndAPop() {
        // Straight onto the Race screen, so there is nothing to tap through
        // before the thing under test.
        launch(["-push", "race"])

        let back = app.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 10), "the race screen did not open")
        XCTAssertTrue(app.buttons["Home"].exists, "the bar must stay on a pushed screen")
        XCTAssertTrue(app.buttons["Progress"].exists)

        back.tap()
        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Progress"].exists)
    }

    /// Nothing ends up stranded underneath it.
    ///
    /// The bar floats over the content, so the last thing on a long pushed
    /// screen has to be reachable past it. The run detail ends in the one
    /// button on that screen that cannot be undone, which makes it the right
    /// thing to check.
    func testTheEndOfALongPushedScreenIsStillReachable() {
        launch(["-push", "detailRoad"])
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 10),
                      "the run detail did not open")

        let delete = app.buttons["Delete run"]
        for _ in 0..<8 where !delete.exists || !delete.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(delete.exists, "never reached the end of the screen")
        XCTAssertTrue(delete.isHittable, "the last control is stranded under the tab bar")
    }

    /// And it still switches tabs from a pushed screen, which is the reason the
    /// platform leaves it there in the first place.
    func testTheTabBarStillWorksFromAPushedScreen() {
        launch(["-push", "race"])
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 10))
        app.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["Progress"].waitForExistence(timeout: 5),
                      "the tab bar did not switch tabs")
    }

    /// The marking mode puts its own floating bar where the tab bar sits, so
    /// the tab bar has to be out of the way — not stacked above it.
    func testTheMarkingModeTakesTheTabBarsPlace() {
        launch(["-tab", "log", "-select", "1"])

        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10),
                      "the log did not open in its marking mode")
        XCTAssertFalse(app.buttons["Progress"].exists,
                       "the tab bar is still there under the delete bar")
    }

    /// The glyph buttons are named. They were not: VoiceOver announced the
    /// back, close and settings buttons as "button" and nothing else — which is
    /// also the only reason this file can find the back button at all.
    func testTheGlyphButtonsHaveNames() {
        launch(["-push", "race"])
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 10))
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5),
                      "Home's settings button is unnamed")
    }

    /// The derivations moved off the screen and behind a button, so the button
    /// has to actually produce them. Asserted end to end rather than by looking
    /// at a screenshot, which can only show that the ⓘ is drawn.
    func testAnInfoButtonOpensTheDerivationItPromises() {
        launch(["-push", "hrZones", "-zones", "derived"])

        let info = app.buttons["How your max heart rate is worked out"]
        XCTAssertTrue(info.waitForExistence(timeout: 10), "no way to ask where the max came from")
        info.tap()

        // The sheet leads with its own title and carries the explanation.
        XCTAssertTrue(app.staticTexts["MAX HEART RATE"].waitForExistence(timeout: 3),
                      "the sheet did not open")
        XCTAssertTrue(app.descendants(matching: .any)
            .containing(NSPredicate(format: "label CONTAINS[c] %@", "Apple Health has seen"))
            .firstMatch.waitForExistence(timeout: 3),
            "the sheet opened without the explanation in it")

        app.buttons["Close"].tap()
        XCTAssertTrue(info.waitForExistence(timeout: 3), "the sheet would not close")
    }
}
