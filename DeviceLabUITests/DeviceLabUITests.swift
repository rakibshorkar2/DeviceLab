import XCTest

final class DeviceLabUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTabBarExists() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Dashboard"].exists)
        XCTAssertTrue(app.tabBars.buttons["Monitor"].exists)
        XCTAssertTrue(app.tabBars.buttons["Diagnostics"].exists)
        XCTAssertTrue(app.tabBars.buttons["Benchmark"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
    }

    func testDashboardShowsHeader() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["DeviceLab"].waitForExistence(timeout: 10))
        // Header shows the OS label (e.g. "iOS 26.0").
        let osLabel = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'iOS'")).firstMatch
        XCTAssertTrue(osLabel.exists)
    }

    func testMonitorDetailOpens() throws {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Monitor"].tap()
        let cpuLabel = app.staticTexts["CPU"].firstMatch
        XCTAssertTrue(cpuLabel.waitForExistence(timeout: 10))
        cpuLabel.tap()
        XCTAssertTrue(app.navigationBars["CPU"].waitForExistence(timeout: 5))
    }

    func testDiagnosticsTabShowsCategories() throws {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Diagnostics"].tap()
        XCTAssertTrue(app.staticTexts["Full Device Check"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Display"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Touch"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Camera"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Microphone & Speaker"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Sensors"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Haptics"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Network"].firstMatch.exists)
    }

    func testFullDeviceCheckStarts() throws {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Diagnostics"].tap()
        let entry = app.staticTexts["Full Device Check"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        let start = app.buttons["Start"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        // The run leaves the idle state: the step list ("Progress" card) appears.
        XCTAssertTrue(app.staticTexts["Progress"].firstMatch.waitForExistence(timeout: 10))
    }

    func testBenchmarkTabShowsRunButtons() throws {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Benchmark"].tap()
        XCTAssertTrue(app.buttons["Run"].firstMatch.waitForExistence(timeout: 10))
    }

    func testSettingsLiveActivitiesNavigation() throws {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Settings"].tap()
        let cell = app.buttons["Live Activities & Dynamic Island"].firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 10))
        cell.tap()
        XCTAssertTrue(app.navigationBars["Live Activities"].waitForExistence(timeout: 5))
    }
}