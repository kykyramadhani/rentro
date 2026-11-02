import XCTest

/// Business Profile region picker (nusawilayah data over jsDelivr, so this test needs the network).
final class WilayahUITests: XCTestCase {
    @MainActor func testPickRegionSaveAndReopen() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-uiTestSignedIn", "-seedSample"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Settings"].tap()
        app.staticTexts["Business Profile"].tap()

        for (level, name) in ["Bali", "Kabupaten Badung", "Kuta", "Tuban"].enumerated() {
            let picker = app.buttons["rentro.wilayah.\(level)"]
            XCTAssertTrue(picker.waitForExistence(timeout: 10))
            XCTAssertTrue(waitUntil { picker.isEnabled }, "level \(level) never loaded")
            picker.tap()
            app.buttons[name].firstMatch.tap()
        }
        XCTAssertTrue(app.staticTexts["80361"].waitForExistence(timeout: 5))
        app.buttons["rentro.profile.save"].tap()

        app.staticTexts["Business Profile"].tap()
        let village = app.buttons["rentro.wilayah.3"]
        XCTAssertTrue(village.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil { village.label.contains("Tuban") }, "saved village not restored: \(village.label)")
        XCTAssertTrue(app.staticTexts["80361"].exists)
    }

    private func waitUntil(_ condition: @escaping () -> Bool) -> Bool {
        let deadline = Date.now.addingTimeInterval(10)
        while Date.now < deadline { if condition() { return true }; RunLoop.current.run(until: .now + 0.2) }
        return false
    }
}
