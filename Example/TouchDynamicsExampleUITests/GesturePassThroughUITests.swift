import XCTest

/// Drives the example app through the real touch path: the window-level
/// observer is installed, and every native gesture must still work.
final class GesturePassThroughUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    /// Lets an external capture rig know where the test is.
    private func marker(_ name: String) {
        FileManager.default.createFile(atPath: "/tmp/td-marker-\(name)", contents: Data())
    }

    private func snapshot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: "/tmp/td-shot-\(name).png"))
    }

    private func launch(mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-td-mode", mode]
        app.launch()
        return app
    }

    private func firstLikes(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(identifier: "likes").firstMatch
    }

    /// Taps the first comment and reports whether the like count toggled.
    @discardableResult
    private func checkTapTogglesLike(_ app: XCUIApplication, mode: String) -> Bool {
        let firstComment = app.staticTexts["This is exactly the kind of micro-interaction that makes an app feel alive."].firstMatch
        XCTAssertTrue(firstComment.waitForExistence(timeout: 15), "[\(mode)] first comment visible")
        let likes = firstLikes(app)
        XCTAssertTrue(likes.waitForExistence(timeout: 5), "[\(mode)] likes label visible")
        let before = likes.label
        firstComment.tap()
        let toggled = NSPredicate(format: "label != %@", before)
        let changed = XCTWaiter().wait(for: [expectation(for: toggled, evaluatedWith: likes)], timeout: 3) == .completed
        let after = likes.label
        try? "mode=\(mode) before=\(before) after=\(after) toggled=\(changed)\n".write(toFile: "/tmp/td-result-\(mode).txt", atomically: true, encoding: .utf8)
        XCTAssertTrue(changed, "[\(mode)] tap toggled the like count (\(before) → \(after))")
        return changed
    }

    func testBaselineWithoutEffects() {
        let app = launch(mode: "off")
        checkTapTogglesLike(app, mode: "off")
    }

    func testObserverOnlyWithSilentEffects() {
        let app = launch(mode: "silent")
        checkTapTogglesLike(app, mode: "silent")
    }

    func testEffectsWithoutElasticity() {
        let app = launch(mode: "noelastic")
        checkTapTogglesLike(app, mode: "noelastic")
    }

    func testFullEffectsAndNativeGestures() {
        let app = launch(mode: "full")

        // Hold (illumination + press) then release (ripple).
        let firstComment = app.staticTexts["This is exactly the kind of micro-interaction that makes an app feel alive."].firstMatch
        XCTAssertTrue(firstComment.waitForExistence(timeout: 15))
        let point = firstComment.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        let background = Thread {
            Thread.sleep(forTimeInterval: 1.2)
            let png = XCUIScreen.main.screenshot().pngRepresentation
            try? png.write(to: URL(fileURLWithPath: "/tmp/td-shot-hold-bg.png"))
        }
        marker("press")
        background.start()
        point.press(forDuration: 2.5)
        marker("release")
        snapshot("ripple-1")
        snapshot("ripple-2")
        snapshot("ripple-3")
        Thread.sleep(forTimeInterval: 1.0)
        let likesAfterHold = firstLikes(app).label
        try? "after hold: \(likesAfterHold)\n".write(toFile: "/tmp/td-result-hold.txt", atomically: true, encoding: .utf8)

        checkTapTogglesLike(app, mode: "full")

        // Scrolling still works.
        app.scrollViews.firstMatch.swipeUp()
        XCTAssertTrue(app.staticTexts["ivy.builds"].firstMatch.waitForExistence(timeout: 3), "scroll passed through")
        snapshot("scrolled")

        // Controls: a SwiftUI Button under the effect still fires.
        app.tabBars.buttons["Controls"].tap()
        let tapped = app.buttons["Tapped 0×"]
        XCTAssertTrue(tapped.waitForExistence(timeout: 5), "controls tab")
        tapped.tap()
        XCTAssertTrue(app.buttons["Tapped 1×"].waitForExistence(timeout: 3), "button action passed through")

        // UIKit: UIButton control events, table scrolling, cell taps, reuse.
        app.tabBars.buttons["UIKit"].tap()
        let uikitButton = app.buttons["UIButton with TouchDynamics"]
        XCTAssertTrue(uikitButton.waitForExistence(timeout: 5), "uikit tab")
        uikitButton.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Fired at'")).firstMatch.waitForExistence(timeout: 3), "UIControl event passed through")
        let table = app.tables.firstMatch
        table.swipeUp()
        table.swipeUp()
        table.swipeDown()
        app.cells.element(boundBy: 3).tap()
        snapshot("uikit")

        // Containers: push, interactive pop from the edge, sheet.
        app.tabBars.buttons["Containers"].tap()
        let push = app.buttons["Push a detail (swipe back works)"]
        XCTAssertTrue(push.waitForExistence(timeout: 5), "containers tab")
        push.tap()
        XCTAssertTrue(app.navigationBars["Detail"].waitForExistence(timeout: 5), "push passed through")
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        let across = app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        edge.press(forDuration: 0.05, thenDragTo: across)
        XCTAssertTrue(app.navigationBars["Containers"].waitForExistence(timeout: 5), "interactive pop passed through")

        app.buttons["Present a sheet"].tap()
        XCTAssertTrue(app.navigationBars["Sheet"].waitForExistence(timeout: 5), "sheet presented")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Containers"].waitForExistence(timeout: 5), "sheet dismissed")
        marker("done")
    }
}
