//
//  StrengthTargetUITests.swift
//  TrainUITests
//
//  Functional UI tests for steady-mode targets (#20): set a target from a
//  card's Edit Plan, see it on the card, record against it (the sheet starts
//  on the target), and take a light week (targets drop to 90%).
//

import XCTest

final class StrengthTargetUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTargetPrefillsRecordingAndLightWeekScalesIt() {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTestSeed")
        app.launch()
        app.tabBars.buttons["Strength"].tap()

        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Test Lift 1'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.press(forDuration: 1.2)
        app.buttons["Edit Plan"].tap()

        let field = app.textFields["editPlan.target.valueField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Edit Plan offers a target")
        field.tap()
        field.typeText("200")
        app.buttons["editPlan.save"].tap()

        let badge = app.staticTexts["strengthCard.target.Test Lift 1"]
        XCTAssertTrue(badge.waitForExistence(timeout: 5), "the card shows its target")
        XCTAssertTrue(badge.label.contains("200"))

        card.tap()
        let value = app.textFields["recordStrength.valueField"]
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        XCTAssertEqual(value.value as? String, "200", "recording starts on the target")
        XCTAssertTrue(app.descendants(matching: .any)["recordStrength.target"].firstMatch.exists)
        app.buttons["Cancel"].tap()

        app.buttons["strength.moreMenu"].tap()
        app.buttons["strength.lightWeek"].tap()
        XCTAssertTrue(app.staticTexts["strength.lightWeekBanner"].waitForExistence(timeout: 5))
        let light = NSPredicate(format: "label CONTAINS '180'")
        expectation(for: light, evaluatedWith: badge)
        waitForExpectations(timeout: 5)
    }
}
