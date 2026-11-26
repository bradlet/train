//
//  MovementGroupUITests.swift
//  TrainUITests
//
//  Functional UI tests for movement groups (#24): a group card offers its
//  up-next member, recording swaps to another member through the sheet's
//  picker, and a group can be added from the library's Groups chip.
//
//  The `-uiTestSeed` fixtures put a built-in Chest Press group card on
//  tomorrow's lane.
//

import XCTest

final class MovementGroupUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launches on the Strength tab showing tomorrow's lane.
    @MainActor
    private func launchOnTomorrow() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTestSeed")
        app.launch()
        app.tabBars.buttons["Strength"].tap()
        let tomorrow = Calendar.current.component(.weekday, from: Date()) % 7
        let chip = app.buttons["strength.dayChip.\(tomorrow)"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.tap()
        return app
    }

    /// The card shows the never-done first member, and recording a swapped
    /// member shows that member as done this week.
    @MainActor
    func testGroupCardOffersUpNextAndRecordsASwap() {
        let app = launchOnTomorrow()
        let member = app.staticTexts["strengthCard.member.Chest Press"]
        XCTAssertTrue(member.waitForExistence(timeout: 5), "the group card should render")
        XCTAssertEqual(member.label, "Up next: Barbell Bench Press")

        app.buttons.containing(NSPredicate(format: "identifier BEGINSWITH 'strengthCard.'"))
            .matching(NSPredicate(format: "label CONTAINS 'Chest Press'")).firstMatch.tap()

        let picker = app.buttons["recordStrength.memberPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "a group card's sheet offers its members")
        picker.tap()
        let incline = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Incline Dumbbell Press'")).firstMatch
        XCTAssertTrue(incline.waitForExistence(timeout: 5))
        incline.tap()

        let value = app.textFields["recordStrength.valueField"]
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        value.tap()
        value.typeText("50")
        app.buttons["recordStrength.save"].tap()

        XCTAssertTrue(
            app.staticTexts["strengthCard.member.Chest Press"].waitForExistence(timeout: 5)
        )
        let recorded = NSPredicate(format: "label == 'Incline Dumbbell Press'")
        expectation(for: recorded, evaluatedWith: app.staticTexts["strengthCard.member.Chest Press"])
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.descendants(matching: .any)["strengthCard.weekCheck.Chest Press"].exists)
    }

    /// The library's Groups chip lists groups and adds one to the day.
    @MainActor
    func testAddAGroupFromTheLibrary() {
        let app = launchOnTomorrow()
        app.buttons["strength.libraryButton"].tap()
        let chip = app.buttons["exerciseLibrary.filter.Groups"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.tap()

        let row = app.buttons["exerciseLibrary.group.Calves"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "built-in groups are listed")
        row.tap()
        let add = app.buttons["exerciseLibrary.addGroup"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()

        let member = app.staticTexts["strengthCard.member.Calves"]
        XCTAssertTrue(member.waitForExistence(timeout: 5), "the group card lands on the day")
        XCTAssertEqual(member.label, "Up next: Standing Calf Raise")
    }
}
