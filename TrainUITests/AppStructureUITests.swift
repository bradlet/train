//
//  AppStructureUITests.swift
//  TrainUITests
//
//  The two-flow app structure (#12): Home · Cardio · Strength, each
//  discipline split into Plan | Progress, and Settings — with import and
//  export under Data — reachable from a gear on every tab.
//

import XCTest

final class AppStructureUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launches with the deterministic UI test seed.
    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTestSeed")
        app.launch()
        return app
    }

    /// Cardio opens on Plan (the weekly calendar) and switches to Progress
    /// (the former History tab's workout log).
    @MainActor
    func testCardioSwitchesBetweenPlanAndProgress() {
        let app = launch()
        app.tabBars.buttons["Cardio"].tap()

        let segment = app.segmentedControls["cardio.segment"]
        XCTAssertTrue(segment.waitForExistence(timeout: 5), "Cardio should show Plan | Progress")
        XCTAssertTrue(segment.buttons["Plan"].isSelected, "Cardio opens on Plan")

        segment.buttons["Progress"].tap()
        XCTAssertTrue(
            app.staticTexts["Recent Workouts"].waitForExistence(timeout: 5),
            "Progress shows the workout log"
        )

        segment.buttons["Plan"].tap()
        XCTAssertFalse(app.staticTexts["Recent Workouts"].waitForExistence(timeout: 2))
    }

    /// Strength opens on the board; its Progress segment is a placeholder
    /// until the lift list lands (#16).
    @MainActor
    func testStrengthProgressShowsThePlaceholder() {
        let app = launch()
        app.tabBars.buttons["Strength"].tap()

        let segment = app.segmentedControls["strength.segment"]
        XCTAssertTrue(segment.waitForExistence(timeout: 5), "Strength should show Plan | Progress")
        XCTAssertTrue(app.buttons["strength.libraryButton"].exists, "Plan shows the board")

        segment.buttons["Progress"].tap()
        XCTAssertTrue(
            app.staticTexts["Lift progress is coming"].waitForExistence(timeout: 5),
            "Strength → Progress shows its placeholder"
        )
    }

    /// Every tab has the Settings gear, and Settings holds the data actions
    /// that used to sit in History's toolbar menu.
    @MainActor
    func testSettingsGearOnEveryTabOpensDataSection() {
        let app = launch()
        for tab in ["Home", "Cardio", "Strength"] {
            app.tabBars.buttons[tab].tap()
            let gear = app.buttons["settingsButton"]
            XCTAssertTrue(gear.waitForExistence(timeout: 5), "\(tab) should have the Settings gear")
            gear.tap()

            XCTAssertTrue(
                app.navigationBars["Settings"].waitForExistence(timeout: 5),
                "Gear on \(tab) should open Settings"
            )
            app.swipeUp()
            for id in ["settings.exportWorkouts", "settings.importWorkouts", "settings.importHealth"] {
                XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 3), "\(id) should be in Settings → Data")
            }
            app.buttons["settings.doneButton"].tap()
        }
    }
}
