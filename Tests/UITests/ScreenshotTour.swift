import XCTest

/// Dev tool: captures every Phase B screen for Figma side-by-side QA. Appearance follows the simulator (`simctl ui appearance`).
final class ScreenshotTour: XCTestCase {
    @MainActor private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name; a.lifetime = .keepAlways
        add(a)
    }

    @MainActor func testTour() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-uiTestSignedIn", "-seedSample", "-adminLoopback"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        shot("S03-home")
        app.tabBars.buttons["Rentals"].tap(); shot("S04-rentals")
        app.buttons["rentro.rentals.filter.overdue"].tap()
        app.staticTexts["Sarah Putri"].firstMatch.tap(); shot("S09-detail-overdue")
        app.buttons["rentro.detail.return"].tap(); shot("S11-return")
        app.navigationBars.buttons["Cancel"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["rentro.rentals.filter.all"].tap()

        app.buttons["rentro.rentals.new"].tap(); shot("S05-new-customer")
        app.buttons["rentro.new.customer.Andi Pratama"].tap()
        app.buttons["rentro.new.continue1"].tap(); shot("S06-new-device")
        app.buttons["rentro.new.device.IP-002"].tap()
        app.buttons["rentro.new.continue2"].tap(); shot("S07-new-price")
        app.buttons["rentro.new.continue3"].tap(); shot("S08-new-review")
        app.buttons["rentro.new.confirm"].tap()
        _ = app.staticTexts["Rental confirmed"].waitForExistence(timeout: 5); shot("S08-done")
        app.buttons["rentro.new.view"].tap()
        _ = app.buttons["rentro.detail.pickup"].waitForExistence(timeout: 5); shot("S09-detail-reserved")
        app.buttons["rentro.detail.pickup"].tap(); shot("S10-pickup")
        app.navigationBars.buttons["Cancel"].tap()

        app.tabBars.buttons["Home"].tap()
        app.buttons["rentro.home.alerts"].tap(); shot("S27-alerts")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["rentro.home.customers"].tap(); shot("S21-customers")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["rentro.home.payments"].tap(); shot("S24-payments")
        app.navigationBars.buttons.firstMatch.tap()

        app.tabBars.buttons["Devices"].tap(); shot("S14-devices")
        app.buttons["rentro.devices.add"].tap(); shot("S16-add-device")
        app.navigationBars.buttons["Cancel"].tap()
        app.tabBars.buttons["Settings"].tap(); shot("S28-settings")
        for (id, name) in [("profile", "S29-profile"), ("policies", "S30-policies"), ("notifications", "S32-notifications"),
                           ("privacy", "S34-privacy"), ("about", "S35-about")] {
            app.buttons["rentro.settings.\(id)"].tap(); shot(name)
            app.navigationBars.buttons.firstMatch.tap()
        }

        app.tabBars.buttons["Map"].tap()
        _ = app.staticTexts["rentro.map.summary"].waitForExistence(timeout: 5); shot("S18-map")
        let pin = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'IP-001' AND label CONTAINS 'last reported'")).firstMatch
        if pin.waitForExistence(timeout: 8) { pin.tap(); _ = app.descendants(matching: .any)["rentro.map.sheet"].waitForExistence(timeout: 5); shot("S19-map-sheet") }
        app.buttons["List"].tap(); shot("S18-map-list")
        app.tabBars.buttons["Devices"].tap()
        app.staticTexts["iPhone 15 Pro"].firstMatch.tap()
        _ = app.descendants(matching: .any)["rentro.device.location"].waitForExistence(timeout: 5); shot("S15-device-detail")
        app.buttons["rentro.device.history"].tap(); shot("S20-history")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["rentro.device.pair"].tap()
        _ = app.staticTexts["rentro.pair.code"].waitForExistence(timeout: 5); shot("T-admin-pair-tracker")
    }
}
