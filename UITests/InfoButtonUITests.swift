import XCTest

/// The ⓘ beside a stat's label.
///
/// It is a 13 pt glyph with a much larger tap target built around it, and CUR-40
/// changed how that target is built: the target used to be a 30 pt *frame*,
/// which made the label row 30 pt tall and pushed "ESTIMATION" visibly below
/// "LONGEST · 50 %" beside it. It is now padding that is given back to the
/// layout afterwards, so the row is text-height again and the hit area lives
/// outside the reported bounds.
///
/// That is a hit-testing behaviour, not an arithmetic one — a unit test cannot
/// reach it and a screenshot only shows the alignment half. Hence this: tap
/// slightly off the glyph and the sheet still has to open.
final class InfoButtonUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-demo", "1", "-push", "race"]
        app.launch()
    }

    func testTheInfoTargetIsBiggerThanItsGlyph() {
        let info = app.buttons["How estimation is worked out"]
        XCTAssertTrue(info.waitForExistence(timeout: 10), "the race screen did not open")

        // Well outside the 13 pt glyph, inside the padding that used to be a
        // frame. `coordinate(withNormalizedOffset:)` is relative to the
        // element's own frame, so 1.4 is past its right edge.
        info.coordinate(withNormalizedOffset: CGVector(dx: 1.4, dy: 0.5)).tap()

        // The sheet's own Close button — the screen underneath has none, and
        // its "ESTIMATION" heading reads the same as the label just tapped.
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5),
                      "the explanation sheet did not open from the enlarged target")
    }
}
