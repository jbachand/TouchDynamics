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

    /// The tests measure the `.fluid` preset regardless of the demo's default.
    private func launch(mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-td-preset", "fluid", "-td-mode", mode]
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

    // MARK: Hold then scroll

    /// Mean luminance (0...255) of `rect` (screen points) in `image`.
    static func meanLuminance(of image: UIImage, in rect: CGRect, pointsWidth: CGFloat) -> Double {
        guard let cg = image.cgImage, pointsWidth > 0 else { return 0 }
        // Screenshots come back in pixels with a UIImage scale of 1; derive the
        // pixel density from the app's point width instead of the metadata.
        let scale = CGFloat(cg.width) / pointsWidth
        let pixelRect = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale).integral
        guard let cropped = cg.cropping(to: pixelRect) else { return 0 }
        let w = 32, h = 32
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        ctx.interpolationQuality = .medium
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum = 0.0
        for i in stride(from: 0, to: data.count, by: 4) {
            sum += 0.2126 * Double(data[i]) + 0.7152 * Double(data[i + 1]) + 0.0722 * Double(data[i + 2])
        }
        return sum / Double(w * h)
    }

    /// Waits until `element`'s frame stops changing (a scroll bounce settled).
    private func stableFrame(of element: XCUIElement, timeout: TimeInterval = 6) -> CGRect {
        let deadline = Date().addingTimeInterval(timeout)
        var previous = element.frame
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.35)
            let current = element.frame
            if current == previous { return current }
            previous = current
        }
        return previous
    }

    private func luminanceNow(_ rect: CGRect, pointsWidth: CGFloat) -> Double {
        Self.meanLuminance(of: XCUIScreen.main.screenshot().image, in: rect, pointsWidth: pointsWidth)
    }

    /// Holds `point` and samples `rect` mid-hold from a background thread.
    private func luminanceDuringHold(at point: XCUICoordinate, rect: CGRect, pointsWidth: CGFloat, name: String) -> Double {
        var sampled = 0.0
        let done = DispatchSemaphore(value: 0)
        let sampler = Thread {
            Thread.sleep(forTimeInterval: 0.9)
            let shot = XCUIScreen.main.screenshot()
            sampled = Self.meanLuminance(of: shot.image, in: rect, pointsWidth: pointsWidth)
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/td-shot-\(name).png"))
            done.signal()
        }
        sampler.start()
        point.press(forDuration: 1.6)
        done.wait()
        return sampled
    }

    func testHoldThenScrollLeavesTheRowResponsive() {
        let logPath = "/tmp/td-commands-holdscroll.txt"
        try? FileManager.default.removeItem(atPath: logPath)
        let app = XCUIApplication()
        app.launchArguments = ["-td-preset", "fluid", "-td-mode", "full", "-td-log", logPath]
        app.launch()
        let firstComment = app.staticTexts["This is exactly the kind of micro-interaction that makes an app feel alive."].firstMatch
        XCTAssertTrue(firstComment.waitForExistence(timeout: 15))

        // Baseline: a hold lights the row (darker in light appearance, brighter in dark).
        let width = app.frame.width
        var rect = stableFrame(of: firstComment)
        let point = firstComment.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        let rest = luminanceNow(rect, pointsWidth: width)
        let lit = luminanceDuringHold(at: point, rect: rect, pointsWidth: width, name: "hold-before")
        let samplerWorks = abs(lit - rest) > 4
        XCTAssertTrue(samplerWorks, "a hold illuminates the row (rest \(rest), lit \(lit))")
        Thread.sleep(forTimeInterval: 0.8)

        // Hold, then let the page scroll under the finger.
        let dragEnd = point.withOffset(CGVector(dx: 0, dy: -260))
        point.press(forDuration: 0.9, thenDragTo: dragEnd, withVelocity: .default, thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertLessThan(firstComment.frame.minY, rect.minY - 120, "the list scrolled during the hold")
        snapshot("after-hold-scroll")

        // Scroll back to the top without momentum and wait for it to settle.
        for _ in 0..<4 {
            let settled = stableFrame(of: firstComment, timeout: 4)
            if firstComment.exists, abs(settled.minY - rect.minY) <= 2 { break }
            let mid = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            mid.press(forDuration: 0.1, thenDragTo: mid.withOffset(CGVector(dx: 0, dy: 320)), withVelocity: .default, thenHoldForDuration: 0.3)
        }
        rect = stableFrame(of: firstComment)
        XCTAssertTrue(firstComment.isHittable, "first row is back on screen")
        XCTAssertEqual(rect.minY, firstComment.frame.minY, accuracy: 2, "the list has settled")

        // The same row must take a touch again (engine log), light again, and take a tap.
        let restAfter = luminanceNow(rect, pointsWidth: width)
        let litAfter = luminanceDuringHold(at: firstComment.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)), rect: rect, pointsWidth: width, name: "hold-after")
        let log = (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? ""
        let lines = log.split(separator: "\n").map(String.init)
        let illuminates = lines.filter { $0.hasPrefix("illuminate") }.count
        try? "rest=\(rest) lit=\(lit) restAfter=\(restAfter) litAfter=\(litAfter) width=\(width) illuminates=\(illuminates)\n".write(toFile: "/tmp/td-result-holdscroll-luminance.txt", atomically: true, encoding: .utf8)
        XCTAssertGreaterThanOrEqual(illuminates, 3, "the row took a touch-down after the hold-then-scroll: \(lines.suffix(8))")
        if samplerWorks {
            XCTAssertGreaterThan(abs(litAfter - restAfter), 4, "after a hold-then-scroll the row still illuminates (rest \(restAfter), lit \(litAfter))")
        }
        Thread.sleep(forTimeInterval: 0.8)
        checkTapTogglesLike(app, mode: "holdscroll")
    }

    func testScrollThenLiftRipples() {
        let logPath = "/tmp/td-commands.txt"
        try? FileManager.default.removeItem(atPath: logPath)
        let app = XCUIApplication()
        app.launchArguments = ["-td-preset", "fluid", "-td-mode", "full", "-td-log", logPath]
        app.launch()
        let firstComment = app.staticTexts["This is exactly the kind of micro-interaction that makes an app feel alive."].firstMatch
        XCTAssertTrue(firstComment.waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 0.5)

        // Hold, drag the content up with the finger, pause, lift.
        let start = firstComment.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: -220))
        start.press(forDuration: 0.6, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0.4)
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertLessThan(firstComment.frame.minY, 60, "the content scrolled with the finger")

        let log = (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? ""
        try? log.write(toFile: "/tmp/td-result-scrollripple.txt", atomically: true, encoding: .utf8)
        let lines = log.split(separator: "\n").map(String.init)
        XCTAssertTrue(lines.contains { $0.hasPrefix("illuminate") }, "touch-down illuminated")
        XCTAssertFalse(lines.contains { $0.hasPrefix("dissipate") }, "nothing dissipated during the scroll: \(lines)")
        let release = lines.first { $0.hasPrefix("release") }
        XCTAssertNotNil(release, "the lift produced a release, not a cancellation: \(lines)")
        XCTAssertTrue(release?.contains("ripple=true") == true, "the release ripples after a scroll: \(release ?? "none")")
        XCTAssertTrue(release?.contains("didScroll=true") == true, "the engine saw the scroll: \(release ?? "none")")
    }

    func testDoubleTapReversesThenRelaunches() {
        let logPath = "/tmp/td-commands-doubletap.txt"
        try? FileManager.default.removeItem(atPath: logPath)
        let app = XCUIApplication()
        app.launchArguments = ["-td-preset", "fluid", "-td-mode", "full", "-td-log", logPath]
        app.launch()
        let firstComment = app.staticTexts["This is exactly the kind of micro-interaction that makes an app feel alive."].firstMatch
        XCTAssertTrue(firstComment.waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 0.5)

        firstComment.doubleTap()
        Thread.sleep(forTimeInterval: 1.0)

        let log = (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? ""
        try? log.write(toFile: "/tmp/td-result-doubletap.txt", atomically: true, encoding: .utf8)
        let lines = log.split(separator: "\n").map(String.init)
        let kinds = lines.map { String($0.split(separator: " ").first ?? "") }
        let illuminates = kinds.filter { $0 == "illuminate" }.count
        let releases = kinds.filter { $0 == "release" }.count
        XCTAssertEqual(illuminates, 2, "both taps of a double tap reach the engine: \(lines)")
        XCTAssertEqual(releases, 2, "both taps release: \(lines)")
        XCTAssertEqual(kinds.filter { $0 == "illuminate" || $0 == "release" }, ["illuminate", "release", "illuminate", "release"], "press, lift, press again, lift: \(lines)")
        XCTAssertTrue(lines.filter { $0.hasPrefix("release") }.allSatisfy { $0.contains("ripple=true") })
    }

    /// A slow double tap: tap, pause, then press and hold so the pull-back
    /// runs to completion under the finger. Markers let a capture rig find it.
    func testSlowDoubleTapPullsTheWaveBack() {
        let logPath = "/tmp/td-commands-slowdouble.txt"
        try? FileManager.default.removeItem(atPath: logPath)
        let app = XCUIApplication()
        app.launchArguments = ["-td-preset", ProcessInfo.processInfo.environment["TD_PRESET"] ?? "fluid", "-td-mode", "full", "-td-log", logPath]
        app.launch()
        let firstComment = app.staticTexts["This is exactly the kind of micro-interaction that makes an app feel alive."].firstMatch
        XCTAssertTrue(firstComment.waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 1.0)
        let point = firstComment.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        marker("slow-tap1")
        point.tap()
        Thread.sleep(forTimeInterval: 0.25)
        marker("slow-press2")
        point.press(forDuration: 1.0)
        marker("slow-done")
        Thread.sleep(forTimeInterval: 0.8)

        let log = (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? ""
        try? log.write(toFile: "/tmp/td-result-slowdouble.txt", atomically: true, encoding: .utf8)
        let kinds = log.split(separator: "\n").map { String($0.split(separator: " ").first ?? "") }
        XCTAssertEqual(kinds.filter { $0 == "illuminate" }.count, 2, "both touches reached the engine: \(kinds)")
        XCTAssertEqual(kinds.filter { $0 == "release" }.count, 2, "both touches released: \(kinds)")
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
