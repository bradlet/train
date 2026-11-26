//
//  HybridWeekUITests.swift
//  TrainUITests
//
//  Functional UI tests for Home's hybrid week (#19): the strip shows both
//  tracks with progress, a lift cell opens that weekday on the Strength
//  board, and a hint can be dismissed for the week.
//

import XCTest

final class HybridWeekUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLiftCellOpensThatDayOnTheBoard() {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTestSeed")
        app.launch()
        XCTAssertTrue(app.staticTexts["home.weekProgress"].waitForExistence(timeout: 5), "Home shows the hybrid week")

        let tomorrow = Calendar.current.component(.weekday, from: Date()) % 7
        let cell = app.buttons["home.week.lift.\(tomorrow)"]
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "each day has a lift cell")
        if !cell.isHittable { app.swipeUp() }
        cell.tap()
        XCTAssertTrue(app.tabBars.buttons["Strength"].isSelected, "the Strength tab opens")
        let chip = app.buttons["strength.dayChip.\(tomorrow)"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["strengthDayColumn.\(tomorrow)"].waitForExistence(timeout: 5),
                      "the board shows that day")
    }

    /// A run cell opens Cardio → Plan.
    @MainActor
    func testRunCellOpensCardioPlan() {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTestSeed")
        app.launch()
        let today = Calendar.current.component(.weekday, from: Date()) - 1
        let cell = app.buttons["home.week.run.\(today)"]
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        if !cell.isHittable { app.swipeUp() }
        cell.tap()
        XCTAssertTrue(app.tabBars.buttons["Cardio"].isSelected, "the Cardio tab opens")
        XCTAssertTrue(app.segmentedControls["cardio.segment"].buttons["Plan"].isSelected, "on Plan")
    }
}
