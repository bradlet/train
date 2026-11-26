//
//  StrengthBoardAidsUITests.swift
//  TrainUITests
//
//  Functional UI tests for the board's planning aids (#18): the muscle
//  balance strip reflects the week's active plan, and copying a day adds its
//  cards to another day without moving the board.
//
//  `-uiTestSeed` plans chest and back today, shoulders and a Chest Press
//  group tomorrow, hamstrings yesterday, and an offloaded quads lift.
//

import XCTest

final class StrengthBoardAidsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchOnBoard() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTestSeed")
        app.launch()
        app.tabBars.buttons["Strength"].tap()
        return app
    }

    /// Push, pull and posterior are planned; quads (only offloaded) and
    /// core are not.
    @MainActor
    func testBalanceStripShowsCoveredAndMissingRegions() {
        let app = launchOnBoard()
        let push = app.descendants(matching: .any)["strength.balance.Push"]
        XCTAssertTrue(push.waitForExistence(timeout: 5), "the balance strip shows")
        XCTAssertEqual(push.label, "Push: planned")
        XCTAssertEqual(app.descendants(matching: .any)["strength.balance.Posterior"].label, "Posterior: planned")
        XCTAssertEqual(app.descendants(matching: .any)["strength.balance.Quads"].label, "Quads: missing", "offloaded cards don't count")
        XCTAssertEqual(app.descendants(matching: .any)["strength.balance.Core"].label, "Core: missing")
    }

    /// Copying today onto tomorrow adds both lifts there and leaves the
    /// board on today.
    @MainActor
    func testCopyDayAddsTheLaneToAnotherDay() {
        let app = launchOnBoard()
        let weekday = Calendar.current.component(.weekday, from: Date())
        let today = weekday - 1
        let tomorrow = weekday % 7
        let tomorrowChip = app.buttons["strength.dayChip.\(tomorrow)"]
        XCTAssertTrue(tomorrowChip.waitForExistence(timeout: 5))
        XCTAssertTrue(tomorrowChip.label.contains("2"), "tomorrow starts with two cards")

        app.buttons["strengthDayColumn.copyDay.\(today)"].tap()
        let target = app.buttons[Calendar.current.weekdaySymbols[tomorrow]]
        XCTAssertTrue(target.waitForExistence(timeout: 5), "the menu lists the other days")
        target.tap()

        XCTAssertTrue(app.descendants(matching: .any)["transientNotice"].waitForExistence(timeout: 5), "the copy is confirmed")
        let updated = NSPredicate(format: "label CONTAINS '4'")
        expectation(for: updated, evaluatedWith: tomorrowChip)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.descendants(matching: .any)["strengthDayColumn.\(today)"].exists, "the board stays on today")
    }
}
