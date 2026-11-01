import XCTest

final class TrackerUITests: XCTestCase {
    @MainActor private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-trackerLoopback"] + extra
        app.launch()
        return app
    }

    @MainActor private func devCode(_ app: XCUIApplication) -> String {
        let l = app.staticTexts["rentro.tracker.debug.code"]
        XCTAssertTrue(l.waitForExistence(timeout: 5))
        return l.label
    }

    @MainActor private func pair(_ app: XCUIApplication, code: String? = nil) {
        let c = code ?? devCode(app)
        app.buttons["rentro.tracker.pair.manual"].tap()
        let f = app.textFields["rentro.tracker.pair.code"]
        XCTAssertTrue(f.waitForExistence(timeout: 3))
        f.tap(); f.typeText(c)
        app.buttons["rentro.tracker.pair.submit"].tap()
    }

    @MainActor private func diag(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "rentro.tracker.diag.\(id)").firstMatch
    }

    @MainActor private func status(_ app: XCUIApplication) -> String {
        let s = app.staticTexts["rentro.tracker.status"]
        XCTAssertTrue(s.waitForExistence(timeout: 5))
        return s.label
    }

    @MainActor private func accept(_ app: XCUIApplication) {
        XCTAssertTrue(app.descendants(matching: .any)["rentro.tracker.consent.understood"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["rentro.tracker.consent.continue"].isEnabled)          // cannot continue unticked
        app.descendants(matching: .any)["rentro.tracker.consent.understood"].tap()
        app.buttons["rentro.tracker.consent.continue"].tap()
    }

    /// T01 → T02 → permission → T03 → T04: a real round trip through the in-process backend.
    /// Localization: the pair screen reads in Indonesian when the device language is Indonesian.
    @MainActor func testPairScreenIsIndonesian() {
        let app = launch(["-AppleLanguages", "(id)", "-AppleLocale", "id_ID"])
        XCTAssertTrue(app.buttons["rentro.tracker.pair.manual"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Hubungkan iPhone sewaan ini"].exists)
    }

    @MainActor func testPairConsentThenTestLocationMakesTrackingActive() {
        let app = launch()
        XCTAssertTrue(app.buttons["rentro.tracker.pair.manual"].waitForExistence(timeout: 5))
        pair(app)
        accept(app)
        XCTAssertEqual(status(app), "No recent signal")                 // consent + permission alone are not "active"
        app.buttons["rentro.tracker.home.diagnostics"].tap()
        XCTAssertTrue(diag(app, "upload").label.hasSuffix("Never"), diag(app, "upload").label)
        app.buttons["rentro.tracker.diag.test"].tap()
        let ok = NSPredicate(format: "label CONTAINS 'Just now'")
        expectation(for: ok, evaluatedWith: diag(app, "upload")); waitForExpectations(timeout: 5)
        XCTAssertTrue(diag(app, "measurement").label.contains("Just now"), diag(app, "measurement").label)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertEqual(status(app), "Tracking active")
    }

    /// AT-41: consent withheld → nothing is collected and the device says so.
    @MainActor func testDecliningConsentShowsNotTrackingAndNeverAsksForPermission() {
        let app = launch()
        pair(app)
        XCTAssertTrue(app.buttons["rentro.tracker.consent.decline"].waitForExistence(timeout: 5))
        app.buttons["rentro.tracker.consent.decline"].tap()
        XCTAssertEqual(status(app), "Not tracking")
        XCTAssertTrue(app.buttons["rentro.tracker.home.review"].exists)
        XCTAssertFalse(app.switches["rentro.tracker.home.share"].exists)
        app.buttons["rentro.tracker.home.diagnostics"].tap()
        XCTAssertFalse(app.buttons["rentro.tracker.diag.test"].isEnabled)
    }

    /// OS permission denied after consent → honest degraded state with a way out.
    @MainActor func testDeniedPermissionShowsPermissionRequired() {
        let app = launch(["-fakeLocationDeny"])
        pair(app)
        accept(app)
        XCTAssertEqual(status(app), "Permission required")
        XCTAssertTrue(app.buttons["rentro.tracker.home.settings"].exists)
    }

    /// The owner has not shared the fleet with this Apple ID yet: say so, and do not offer a pairing that cannot work.
    @MainActor func testPairingIsBlockedWithAnHonestMessageUntilTheFleetIsShared() {
        let app = launch(["-fleetNotShared"])
        let msg = app.staticTexts["rentro.tracker.fleet.status"]
        XCTAssertTrue(msg.waitForExistence(timeout: 5))
        XCTAssertTrue(msg.label.contains("owner to share"), msg.label)
        XCTAssertFalse(app.buttons["rentro.tracker.pair.manual"].isEnabled)
    }

    @MainActor func testNoFleetMessageWhenLinked() {
        let app = launch()
        XCTAssertTrue(app.buttons["rentro.tracker.pair.manual"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["rentro.tracker.fleet.status"].exists)
        XCTAssertTrue(app.buttons["rentro.tracker.pair.manual"].isEnabled)
    }

    @MainActor func testWrongCodeShowsAnErrorAndStaysUnpaired() {
        let app = launch()
        pair(app, code: "ABCD-EFGH")
        XCTAssertTrue(app.staticTexts["rentro.tracker.pair.error"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["That code isn't valid. Check it and try again."].exists)
        XCTAssertFalse(app.staticTexts["rentro.tracker.status"].exists)
    }

    /// T05 / AT-44: unpair returns to the pair screen; the used code cannot pair again.
    @MainActor func testUnpairReturnsToPairAndTheOldCodeIsDead() {
        let app = launch()
        let code = devCode(app)
        pair(app, code: code)
        accept(app)
        _ = status(app)
        app.buttons["rentro.tracker.home.unpair"].tap()
        app.buttons["rentro.tracker.unpair.button"].tap()
        app.sheets.buttons["Unpair Device"].tap()
        XCTAssertTrue(app.buttons["rentro.tracker.pair.manual"].waitForExistence(timeout: 5))
        pair(app, code: code)
        XCTAssertTrue(app.staticTexts["This code was already used. Ask the rental business for a new one."].waitForExistence(timeout: 3))
    }
}

/// Dev tool: T01–T05 for Figma side-by-side QA. Appearance follows the simulator.
final class TrackerScreenshotTour: XCTestCase {
    @MainActor private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name; a.lifetime = .keepAlways
        add(a)
    }

    @MainActor func testTour() {
        let app = XCUIApplication()
        app.launchArguments = ["-trackerLoopback"]
        app.launch()
        let label = app.staticTexts["rentro.tracker.debug.code"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        let code = label.label
        shot("T01-pair")
        app.buttons["rentro.tracker.pair.manual"].tap()
        let f = app.textFields["rentro.tracker.pair.code"]
        XCTAssertTrue(f.waitForExistence(timeout: 3))
        f.tap(); f.typeText(code); shot("T01-pair-manual")
        app.buttons["rentro.tracker.pair.submit"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["rentro.tracker.consent.understood"].waitForExistence(timeout: 5))
        shot("T02-consent")
        app.descendants(matching: .any)["rentro.tracker.consent.understood"].tap()
        app.buttons["rentro.tracker.consent.continue"].tap()
        XCTAssertTrue(app.staticTexts["rentro.tracker.status"].waitForExistence(timeout: 5))
        shot("T03-home-no-signal")
        app.buttons["rentro.tracker.home.diagnostics"].tap()
        app.buttons["rentro.tracker.diag.test"].tap()
        _ = app.staticTexts["Just now"].firstMatch.waitForExistence(timeout: 5)
        shot("T04-diagnostics")
        app.navigationBars.buttons.firstMatch.tap(); shot("T03-home-active")
        app.buttons["rentro.tracker.home.unpair"].tap(); shot("T05-unpair")
    }
}


/// Same audit rules as the admin app (see AccessibilityAuditTests): contrast, clipping, element descriptions, hit regions, traits.
/// `.dynamicType` is left out: it flags deliberately capped chrome; real scaling is checked on XXXL screenshots.
final class TrackerAccessibilityTests: XCTestCase {
    private static let types: XCUIAccessibilityAuditType = [.contrast, .elementDetection, .hitRegion, .sufficientElementDescription, .textClipped, .trait]
    private var found: [String] = []
    /// Unlabelled system containers of the manual-code sheet, and caption text the audit mis-measures near the bottom bar.
    /// Checked by eye on the screenshots; keyed by screen and label so anything new still fails.
    private static let knownFalsePositives: Set<String> = ["std PairManual|", "XXXL PairManual|", "std Consent|Questions", "XXXL Consent|How location is used", "XXXL Pair|Pairing identifies the unit to Rentro. L",
        // Red Unpair button: token pair is 5.7:1 (ContrastTests) and legible on the screenshot, yet the audit still reports it.
        "std Unpair|Unpair Device", "XXXL Unpair|Unpair Device"]
    private func unexpected() -> [String] {
        found.filter { line in
            let f = line.components(separatedBy: " | ")
            let label = f.count > 3 ? f[3].components(separatedBy: " \'").dropFirst().joined(separator: " \'").dropLast() : ""
            return !Self.knownFalsePositives.contains("\(f[0])|\(label)")
        }
    }

    @MainActor private func audit(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.8)                  // let push/sheet transitions finish: contrast is measured on pixels
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let window = app.windows.firstMatch.frame
        do {
            try app.performAccessibilityAudit(for: Self.types) { issue in
                let frame = issue.element?.frame ?? .zero
                if issue.auditType == .contrast, issue.element?.isEnabled == false { return true }          // disabled controls are exempt
                if issue.auditType == .contrast || issue.auditType == .textClipped, frame.isEmpty || !window.contains(frame) { return true }   // screen-edge artefacts
                self.found.append("\(name) | \(issue.auditType.rawValue) | \(issue.compactDescription) | \(issue.element.map { "\($0.elementType.rawValue) '\($0.label.prefix(40))'" } ?? "-")")
                return true
            }
        } catch { found.append("\(name) | AUDIT ERROR \(error)") }
    }

    @MainActor private func tour(large: Bool) {
        let tag = large ? "XXXL" : "std"
        let app = XCUIApplication()
        app.launchArguments = ["-trackerLoopback"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let code = app.staticTexts["rentro.tracker.debug.code"]
        XCTAssertTrue(code.waitForExistence(timeout: 8))
        let c = code.label
        audit(app, "\(tag) Pair")
        app.buttons["rentro.tracker.pair.manual"].tap()
        let f = app.textFields["rentro.tracker.pair.code"]
        XCTAssertTrue(f.waitForExistence(timeout: 3))
        f.tap(); f.typeText(c); audit(app, "\(tag) PairManual")
        app.buttons["rentro.tracker.pair.submit"].tap()
        let understood = app.descendants(matching: .any)["rentro.tracker.consent.understood"]
        XCTAssertTrue(understood.waitForExistence(timeout: 5))
        audit(app, "\(tag) Consent")
        understood.tap(); app.buttons["rentro.tracker.consent.continue"].tap()
        XCTAssertTrue(app.staticTexts["rentro.tracker.status"].waitForExistence(timeout: 5))
        audit(app, "\(tag) Home")
        for _ in 0..<6 where !(app.buttons["rentro.tracker.home.diagnostics"].exists && app.buttons["rentro.tracker.home.diagnostics"].isHittable) { app.swipeUp() }
        app.buttons["rentro.tracker.home.diagnostics"].tap(); audit(app, "\(tag) Diagnostics")
        app.navigationBars.buttons.firstMatch.tap()
        for _ in 0..<6 where !(app.buttons["rentro.tracker.home.unpair"].exists && app.buttons["rentro.tracker.home.unpair"].isHittable) { app.swipeUp() }
        app.buttons["rentro.tracker.home.unpair"].tap(); audit(app, "\(tag) Unpair")
    }

    @MainActor func testStandardSizeHasNoAccessibilityIssues() { tour(large: false); XCTAssertEqual(unexpected(), [], "accessibility audit findings") }
    @MainActor func testLargestSizeHasNoAccessibilityIssues() { tour(large: true); XCTAssertEqual(unexpected(), [], "accessibility audit findings at the largest size") }
}
