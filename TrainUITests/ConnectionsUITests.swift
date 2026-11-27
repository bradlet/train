//
//  ConnectionsUITests.swift
//  TrainUITests
//
//  Settings → Connections (#23): every connection has its card, the manual
//  CSV and Health actions are there, and each Progress segment offers its
//  own CSV export.
//

import XCTest

final class ConnectionsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launches with the deterministic fixture seed.
    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTestSeed")
        app.launch()
        return app
    }

    /// Opens Settings → Connections from Home.
    @MainActor
    private func openConnections(_ app: XCUIApplication) {
        app.buttons["settingsButton"].firstMatch.tap()
        let link = app.buttons["settings.connections"]
        for _ in 0..<6 where !link.isHittable { app.swipeUp() }
        link.tap()
        XCTAssertTrue(app.navigationBars["Connections"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testDashboardListsEveryConnectionAndItsActions() {
        let app = launch()
        openConnections(app)

        for id in ["googleSheets", "csvFile", "appleHealth"] {
            XCTAssertTrue(app.descendants(matching: .any)["connections.\(id)"].waitForExistence(timeout: 3), "\(id) card")
        }
        for id in ["settings.enableSheetsSync", "settings.exportWorkouts", "settings.importWorkouts",
                   "connections.csvAutoExport.setUp", "settings.importHealth", "connections.garmin.importFIT"] {
            let button = app.buttons[id]
            for _ in 0..<4 where !button.exists { app.swipeUp() }
            XCTAssertTrue(button.exists, "\(id) should be on the dashboard")
        }
        app.swipeUp()
        XCTAssertTrue(app.descendants(matching: .any)["connections.garmin"].exists, "Garmin card")
    }

    @MainActor
    func testEachProgressSegmentExportsItsOwnCSV() {
        let app = launch()
        app.tabBars.buttons["Cardio"].tap()
        app.segmentedControls["cardio.segment"].buttons["Progress"].tap()
        XCTAssertTrue(app.buttons["progress.exportCSV"].waitForExistence(timeout: 5), "Cardio → Progress export")

        app.tabBars.buttons["Strength"].tap()
        app.segmentedControls.firstMatch.buttons["Progress"].tap()
        XCTAssertTrue(app.buttons["progress.exportCSV"].waitForExistence(timeout: 5), "Strength → Progress export")
    }
}
