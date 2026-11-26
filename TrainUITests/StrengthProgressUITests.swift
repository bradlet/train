//
//  StrengthProgressUITests.swift
//  TrainUITests
//
//  Functional UI tests for Strength → Progress (#16): the lift list shows
//  every lift with history, a lift's detail shows its latest and best, a
//  session can be edited from there, and a board card's History item and
//  the record sheet both reach the same detail.
//
//  The `-uiTestSeed` fixtures give Test Lift 1 one 135 lb session.
//

import XCTest

final class StrengthProgressUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchOnStrength() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTestSeed")
        app.launch()
        app.tabBars.buttons["Strength"].tap()
        return app
    }

    @MainActor
    private func openProgress(_ app: XCUIApplication) {
        let progress = app.segmentedControls["strength.segment"].buttons["Progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        progress.tap()
    }

    /// The list shows the recorded lift; its detail shows the numbers, and
    /// editing a session updates them.
    @MainActor
    func testLiftListDetailAndEdit() {
        let app = launchOnStrength()
        openProgress(app)

        let row = app.buttons["strengthProgress.lift.Test Lift 1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "a lift with history is listed")
        XCTAssertFalse(app.buttons["strengthProgress.lift.Test Lift 2"].exists, "a lift without records is not")
        row.tap()

        let latest = app.staticTexts["liftDetail.latest"]
        XCTAssertTrue(latest.waitForExistence(timeout: 5))
        XCTAssertEqual(latest.label, "135 lb")
        XCTAssertEqual(app.staticTexts["liftDetail.sessions"].label, "1")

        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'liftDetail.record.'")).firstMatch.tap()
        let field = app.textFields["editRecord.valueField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "tapping a session edits it")
        XCTAssertEqual(field.value as? String, "135")
        app.buttons["editRecord.increment"].tap()
        app.buttons["editRecord.save"].tap()

        let updated = NSPredicate(format: "label == '140 lb'")
        expectation(for: updated, evaluatedWith: app.staticTexts["liftDetail.latest"])
        waitForExpectations(timeout: 5)
    }

    /// A board card's History item opens its lift's detail.
    @MainActor
    func testCardHistoryOpensTheLiftDetail() {
        let app = launchOnStrength()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Test Lift 1'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.press(forDuration: 1.2)
        let history = app.buttons["History"]
        XCTAssertTrue(history.waitForExistence(timeout: 5), "the card menu offers History")
        history.tap()
        XCTAssertTrue(app.staticTexts["liftDetail.latest"].waitForExistence(timeout: 5))
    }

    /// The record sheet links to the lift's history.
    @MainActor
    func testRecordSheetLinksToHistory() {
        let app = launchOnStrength()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Test Lift 1'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        let history = app.buttons["recordStrength.history"]
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        history.tap()
        XCTAssertTrue(app.staticTexts["liftDetail.best"].waitForExistence(timeout: 5))
    }
}
