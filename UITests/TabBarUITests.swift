import XCTest

/// The tab bar around a pushed screen.
///
/// CUR-36 #3 reports that the bar takes about half a second to come back after
/// Back is tapped. **That timing is not asserted here, because this harness
/// cannot see it.** `XCUIElement.tap()` returns only once the app has gone
/// quiet again, so any measurement taken around it is "tap synthesis plus the
/// app settling completely" — 1.81 s on this machine, and 1.82 s with the tab
/// bar's visibility driven from navigation state instead of from the pushed
/// view. Two implementations that differ on screen measure the same here, so a
/// threshold would assert nothing and fail on a slow morning.
///
/// What is asserted is what can be: the bar goes away, comes back, and the
/// log's marking mode still gets that space to put its own bar in. The last one
/// is not hypothetical — it broke while looking for the timing fix, because two
/// `toolbar(_:for: .tabBar)` declarations in one stack do not compose and the
/// outer one silently wins.
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

    func testAPushedScreenTakesTheTabBarWithItAndGivesItBack() {
        // Straight onto the Race screen, so there is nothing to tap through
        // before the thing under test.
        launch(["-push", "race"])

        let back = app.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 10), "the race screen did not open")
        XCTAssertFalse(app.buttons["Home"].exists, "a pushed screen must hide the tab bar")

        back.tap()
        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 5),
                      "the tab bar never came back")
        XCTAssertTrue(app.buttons["Progress"].exists)
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
