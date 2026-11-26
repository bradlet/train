//
//  PlacementUITests.swift
//  TrainUITests
//
//  Functional UI tests for run-aware placement (#25): the ⚡ key toggle on
//  the workout forms, the cardio marker on the Strength day chips, and the
//  Arrange sheet. The `-uiTestSeed` week marks only tomorrow's long run as
//  key, and no leg day sits next to it, so the week already works.
//

import XCTest

final class PlacementUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTestSeed")
        app.launch()
        return app
    }

    /// The record form offers the ⚡ key toggle, off by default.
    @MainActor
    func testRecordFormHasTheKeyToggle() {
        let app = launch()
        let logWorkout = app.buttons["home.logWorkout"]
        XCTAssertTrue(logWorkout.waitForExistence(timeout: 5))
        logWorkout.tap()
        let toggle = app.switches["workoutForm.keyWorkoutToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "the form offers ⚡ Key workout")
        XCTAssertEqual(toggle.value as? String, "0", "nothing is key until the athlete says so")
    }

    /// Tomorrow's chip carries the key marker; Arrange says the week works.
    @MainActor
    func testKeyMarkerAndArrangeSheet() {
        let app = launch()
        app.tabBars.buttons["Strength"].tap()
        let tomorrow = Calendar.current.component(.weekday, from: Date()) % 7
        let chip = app.buttons["strength.dayChip.\(tomorrow)"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        XCTAssertEqual(chip.value as? String, "Key workout day")

        app.buttons["strength.moreMenu"].tap()
        let arrange = app.buttons["strength.arrangeWeek"]
        XCTAssertTrue(arrange.waitForExistence(timeout: 5))
        arrange.tap()
        XCTAssertTrue(app.staticTexts["Your week already works"].waitForExistence(timeout: 5)
                      || app.descendants(matching: .any)["arrange.alreadyWorks"].exists)
        XCTAssertFalse(app.buttons["arrange.apply"].isEnabled, "nothing to apply")
    }
}
