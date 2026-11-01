import XCTest

final class TabBarUITests: XCTestCase {
    @MainActor private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore"] + extra
        app.launch()
        return app
    }

    /// AT-31: native Sign in with Apple button, no email/password/forgot-password.
    @MainActor func testSignInShowsOnlyAppleButton() {
        let app = launch(["-uiTestSignedOut", "-skipBrandIntro"])
        XCTAssertTrue(app.buttons["rentro.signin.apple"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields.count + app.secureTextFields.count, 0)
        XCTAssertFalse(app.buttons["Forgot password?"].exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists)   // nothing protected before auth
    }

    /// AT-11 / AT-36: exactly Home, Rentals, Devices, Map, Settings; no More.
    @MainActor func testFiveTabsWithSettingsAsFifth() {
        let app = launch(["-uiTestSignedIn", "-seedSample"])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        let names = app.tabBars.firstMatch.buttons.allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(names, ["Home", "Rentals", "Devices", "Map", "Settings"])
        XCTAssertFalse(app.tabBars.buttons["More"].exists)
    }

    /// AT-12 persistence half + AT-13: appearance choice and "No matches" / Clear Filters.
    @MainActor func testAppearanceSelectionAndNoMatchesClear() {
        let app = launch(["-uiTestSignedIn", "-seedSample"])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Settings"].tap()
        app.buttons["rentro.settings.appearance"].tap()
        app.buttons["rentro.appearance.dark"].tap()
        XCTAssertTrue(app.buttons["rentro.appearance.dark"].isSelected)
        app.buttons["rentro.appearance.system"].tap()   // restore so other tests/screens stay in System
        app.navigationBars.buttons.firstMatch.tap()

        app.tabBars.buttons["Rentals"].tap()
        let search = app.textFields["rentro.rentals.search"]
        search.tap(); search.typeText("zzzz")
        XCTAssertTrue(app.staticTexts["No matches"].waitForExistence(timeout: 2))
        app.buttons["Clear Filters"].tap()
        XCTAssertFalse(app.staticTexts["No matches"].exists)
    }

    /// S02 → S14: new owner creates a business, sees the empty state, adds a device. (Duplicate unit code: DomainTests.)
    @MainActor func testBusinessSetupThenAddDevice() {
        let app = launch(["-uiTestSignedIn"])
        let name = app.textFields["rentro.setup.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Test Rental")
        app.staticTexts["Business name"].tap()   // dismiss keyboard so Create is hittable
        app.buttons["rentro.setup.create"].tap()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Devices"].tap()
        XCTAssertTrue(app.staticTexts["No devices yet"].waitForExistence(timeout: 3))
        app.buttons["Add Device"].tap()
        add(app, code: "IP-021", model: "iPhone 15 Pro")
        XCTAssertTrue(app.staticTexts["iPhone 15 Pro"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["No devices yet"].exists)
    }

    /// F01 + F03 (AT-03, AT-05, AT-07): book, hand over, return, entirely through the UI.
    @MainActor func testBookPickupAndReturn() {
        let app = launch(["-uiTestSignedIn", "-seedSample"])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Rentals"].tap()
        app.buttons["rentro.rentals.new"].tap()

        let customer = app.buttons["rentro.new.customer.Andi Pratama"]
        XCTAssertTrue(customer.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["rentro.new.continue1"].isEnabled)     // a customer is required
        customer.tap()
        app.buttons["rentro.new.continue1"].tap()

        // IP-001 is out for days, so it is booked for the default window; IP-002 is free.
        let booked = app.buttons["rentro.new.device.IP-001"]
        XCTAssertTrue(booked.waitForExistence(timeout: 5))
        XCTAssertFalse(booked.isEnabled)
        app.buttons["rentro.new.device.IP-002"].tap()
        app.buttons["rentro.new.continue2"].tap()
        app.buttons["rentro.new.continue3"].tap()
        app.buttons["rentro.new.confirm"].tap()

        XCTAssertTrue(app.staticTexts["Rental confirmed"].waitForExistence(timeout: 5))
        app.buttons["rentro.new.view"].tap()
        XCTAssertTrue(app.buttons["rentro.detail.pickup"].waitForExistence(timeout: 5))
        app.buttons["rentro.detail.pickup"].tap()
        app.buttons["rentro.pickup.confirm"].tap()

        XCTAssertTrue(app.buttons["rentro.detail.return"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["rentro.detail.pickup"].exists)       // no stale lifecycle action
        app.buttons["rentro.detail.return"].tap()
        app.buttons["rentro.return.confirm"].tap()
        XCTAssertTrue(app.staticTexts["Returned"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["rentro.detail.return"].exists)
    }

    /// S27 + S24 + S21 + S29/S30: secondary routes work, read-state persists, settings save.
    @MainActor func testAlertsPaymentsCustomersAndSettings() {
        let app = launch(["-uiTestSignedIn", "-seedSample"])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        app.buttons["rentro.home.alerts"].tap()
        XCTAssertTrue(app.staticTexts["Overdue rental"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Pickup today"].exists || app.staticTexts["Return due today"].exists)
        app.navigationBars.buttons.firstMatch.tap()

        app.buttons["rentro.home.customers"].tap()
        XCTAssertTrue(app.staticTexts["Andi Pratama"].waitForExistence(timeout: 5))
        let search = app.textFields["rentro.customers.search"]
        search.tap(); search.typeText("zzzz")
        XCTAssertTrue(app.staticTexts["No matches"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.firstMatch.tap()

        app.buttons["rentro.home.payments"].tap()
        XCTAssertTrue(app.staticTexts["Rental revenue"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        app.tabBars.buttons["Settings"].tap()
        app.buttons["rentro.settings.policies"].tap()
        let rate = app.textFields["rentro.policies.rate"]
        XCTAssertTrue(rate.waitForExistence(timeout: 5))
        rate.tap(); rate.clearAndType("300000")
        app.staticTexts["Default daily rate"].tap()
        app.buttons["rentro.policies.save"].tap()
        app.buttons["rentro.settings.policies"].tap()
        XCTAssertEqual(app.textFields["rentro.policies.rate"].value as? String, "300.000")   // grouped when not editing
    }

    // MARK: tracker, admin side (S18, S19, S20, Pair Tracker)

    /// S18 / S19: real points become pins; a pin opens the device sheet; the list is the pin-free alternative.
    @MainActor func testMapShowsReportedPinsSheetAndList() {
        let app = launch(["-uiTestSignedIn", "-seedSample"])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Map"].tap()
        let summary = app.staticTexts["rentro.map.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertEqual(summary.label, "1 recent · 1 aging · 1 stale · 4 not reported")
        let pin = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'IP-001' AND label CONTAINS 'last reported'")).firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 8))
        pin.tap()
        XCTAssertTrue(app.descendants(matching: .any)["rentro.map.sheet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Device Details"].exists)
        XCTAssertTrue(app.staticTexts["Location recent"].exists)

        app.buttons["List"].tap()
        XCTAssertTrue(app.staticTexts["No location received"].firstMatch.waitForExistence(timeout: 3))     // unreported units stay listed
        XCTAssertTrue(app.staticTexts["May no longer be current"].firstMatch.exists)                        // stale is worded honestly
    }

    /// S15 / S20: the latest point, its history, and deleting that history.
    @MainActor func testDeviceLocationHistoryAndDelete() {
        let app = launch(["-uiTestSignedIn", "-seedSample"])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Devices"].tap()
        app.staticTexts["iPhone 15 Pro"].firstMatch.tap()
        let card = app.descendants(matching: .any)["rentro.device.location"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.label.contains("Last reported"), card.label)
        app.buttons["rentro.device.history"].tap()
        XCTAssertTrue(app.staticTexts["No movement is inferred between reported points."].waitForExistence(timeout: 3))
        app.buttons["rentro.history.delete"].tap()
        app.sheets.buttons["Delete history"].tap()
        XCTAssertTrue(app.staticTexts["No history"].waitForExistence(timeout: 3))
    }

    /// Without a backend the sheet says so instead of showing a code nothing can claim.
    @MainActor func testPairTrackerIsHonestWhenNotConfigured() {
        let app = launch(["-uiTestSignedIn", "-seedSample"])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Devices"].tap()
        app.staticTexts["iPhone 15"].firstMatch.tap()
        app.buttons["rentro.device.pair"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["rentro.pair.error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Pairing needs iCloud setup"].exists)
        XCTAssertFalse(app.staticTexts["rentro.pair.code"].exists)
        XCTAssertFalse(app.buttons["rentro.pair.new"].isEnabled)
    }

    /// Tracker Sync without a container: the honest state, the safety warning, and no button that cannot work.
    @MainActor func testTrackerSyncIsHonestWithoutAnICloudContainer() {
        let app = launch(["-uiTestSignedIn", "-seedSample"])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Settings"].tap()
        app.buttons["rentro.settings.fleet"].tap()
        let status = app.descendants(matching: .any)["rentro.fleet.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("iCloud isn't set up in this build"), status.label)
        XCTAssertFalse(app.buttons["rentro.fleet.share"].exists)                 // no dead button
        XCTAssertTrue(app.staticTexts["rentro.fleet.warning"].exists)            // the dedicated-Apple-ID warning is always shown
    }

    /// B03: the first-run intro plays on the signed-out path, then hands over to Sign In by itself.
    @MainActor func testBrandIntroPlaysThenShowsSignIn() {
        let app = launch(["-uiTestSignedOut", "-resetBrandIntro", "-brandIntroHold"])
        XCTAssertTrue(app.descendants(matching: .any)["rentro.intro"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["rentro.signin.apple"].exists)                         // the intro really is in front
        XCTAssertTrue(app.buttons["rentro.signin.apple"].waitForExistence(timeout: 14))   // and it hands over without any tap
        XCTAssertFalse(app.descendants(matching: .any)["rentro.intro"].exists)
    }

    @MainActor func testTappingTheIntroSkipsIt() {
        let app = launch(["-uiTestSignedOut", "-resetBrandIntro", "-brandIntroHold"])
        let intro = app.descendants(matching: .any)["rentro.intro"]
        XCTAssertTrue(intro.waitForExistence(timeout: 5))
        intro.tap()
        XCTAssertTrue(app.buttons["rentro.signin.apple"].waitForExistence(timeout: 2))     // seconds before the 8 s hold would end
    }

    /// B03 / AT-32: once seen, a relaunch goes straight to Sign In (no repeat intro).
    @MainActor func testSecondLaunchSkipsTheIntro() {
        let first = launch(["-uiTestSignedOut", "-resetBrandIntro", "-brandIntroHold"])
        let intro = first.descendants(matching: .any)["rentro.intro"]
        XCTAssertTrue(intro.waitForExistence(timeout: 5)); intro.tap()
        XCTAssertTrue(first.buttons["rentro.signin.apple"].waitForExistence(timeout: 2))
        first.terminate()
        let second = launch(["-uiTestSignedOut"])
        XCTAssertTrue(second.buttons["rentro.signin.apple"].waitForExistence(timeout: 4))
        XCTAssertFalse(second.descendants(matching: .any)["rentro.intro"].exists)
    }

    /// B03 / AT-32: a signed-in owner goes straight to the app; the intro is never in the way.
    @MainActor func testSignedInOwnerNeverSeesTheIntro() {
        let app = launch(["-uiTestSignedIn", "-seedSample", "-resetBrandIntro", "-brandIntroHold"])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["rentro.intro"].exists)
    }

    /// One-minute codes: a code, a live countdown, and a new code on demand.
    @MainActor func testPairTrackerShowsCodeCountdownAndIssuesANewCode() {
        let app = launch(["-uiTestSignedIn", "-seedSample", "-adminLoopback"])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Devices"].tap()
        app.staticTexts["iPhone 15"].firstMatch.tap()
        app.buttons["rentro.device.pair"].tap()
        let code = app.staticTexts["rentro.pair.code"]
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        let first = code.label
        XCTAssertNotNil(PairingCodeShape.normalize(first), first)
        let countdown = app.staticTexts["rentro.pair.countdown"]
        XCTAssertTrue(countdown.label.hasPrefix("Expires in "), countdown.label)
        app.buttons["rentro.pair.new"].tap()
        let changed = NSPredicate(format: "label != %@", first)
        expectation(for: changed, evaluatedWith: app.staticTexts["rentro.pair.code"]); waitForExpectations(timeout: 5)
    }

    @MainActor private func add(_ app: XCUIApplication, code: String, model: String) {
        let c = app.textFields["rentro.device.unitcode"]
        XCTAssertTrue(c.waitForExistence(timeout: 3))
        c.tap(); c.typeText(code)
        let m = app.textFields["rentro.device.model"]
        m.tap(); m.typeText(model)
        app.staticTexts["Unit code"].tap()   // dismiss keyboard
        app.buttons["rentro.device.save"].tap()
    }

    /// One app, two roles: first launch asks, each role can switch back from its entry screen.
    @MainActor func testRolePickerChoosesAndSwitchesRole() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetDeviceRole", "-skipBrandIntro"]
        app.launch()
        let tracker = app.buttons["rentro.role.tracker"]
        XCTAssertTrue(tracker.waitForExistence(timeout: 5))
        tracker.tap()
        XCTAssertTrue(app.buttons["rentro.tracker.pair.manual"].waitForExistence(timeout: 5))
        app.buttons["rentro.role.change"].tap()
        app.buttons["rentro.role.owner"].tap()
        XCTAssertTrue(app.buttons["rentro.signin.apple"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["rentro.role.change"].exists)
    }

    /// Localization: with Indonesian selected the tab bar and key screens are translated, and tab identity is unchanged.
    @MainActor func testIndonesianTabsAndSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-uiTestSignedIn", "-seedSample", "-AppleLanguages", "(id)", "-AppleLocale", "id_ID"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        let names = app.tabBars.firstMatch.buttons.allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(names, ["Beranda", "Sewa", "Perangkat", "Peta", "Pengaturan"])
        app.tabBars.buttons["Pengaturan"].tap()
        XCTAssertTrue(app.staticTexts["Preferensi"].waitForExistence(timeout: 3) || app.staticTexts["PREFERENSI"].exists)
    }
}

private extension XCUIElement {
    func clearAndType(_ text: String) {
        guard let current = value as? String else { typeText(text); return }
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + text)
    }
}

/// UI tests are a separate module: same alphabet and shape as `PairingCode`, checked independently.
enum PairingCodeShape {
    static func normalize(_ s: String) -> String? {
        let t = s.uppercased().filter { $0 != "-" && !$0.isWhitespace }
        return t.count == 8 && t.allSatisfy("ABCDEFGHJKLMNPQRSTUVWXYZ23456789".contains) ? t : nil
    }
}
