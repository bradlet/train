//
//  FavoritesUITests.swift
//  TrainUITests
//
//  Functional UI tests for favorite cardio sessions. Favorites live only in
//  the cardio record and schedule sheets (never on Home): starting a quick add
//  from the "Start from Favorite" menu, and managing favorites from that
//  menu's "Manage Favorites…" entry. Also covers the duration preset pills.
//
//  These tests launch with `-uiTestSeed`, which seeds a single favorite —
//  "Test Favorite Run" (Tempo Run, 4 mi, 32:00) — see `UITestFixtures.swift`.
//

import XCTest

final class FavoritesUITests: XCTestCase {

    /// Name of the favorite seeded by `UITestFixtures.seedFavorites`.
    private let seededFavorite = "Test Favorite Run"

    // MARK: - Lifecycle

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    /// Launches the app with the UI test seed. Home is the first tab.
    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTestSeed")
        app.launch()
        return app
    }

    /// Opens Home's Quick Record "log workout" sheet.
    @MainActor
    private func openQuickAdd(in app: XCUIApplication) {
        let button = app.buttons["home.logWorkout"]
        if !button.waitForExistence(timeout: 3) || !button.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Quick Record should be on Home")
        button.tap()
    }

    /// Asserts the record form shows the seeded favorite's name and distance.
    @MainActor
    private func assertRecordFormShowsSeededFavorite(in app: XCUIApplication) {
        let nameField = app.textFields["workoutForm.nameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "record form should appear")
        XCTAssertEqual(nameField.value as? String, seededFavorite)
        XCTAssertEqual(app.textFields["workoutForm.distanceField"].value as? String, "4.0")
    }

    // MARK: - Tests

    @MainActor
    func testHomeHasNoFavoritesCard() {
        let app = launchApp()
        XCTAssertTrue(app.buttons["home.logWorkout"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["home.favorites.edit"].exists, "favorites no longer live on Home")
        XCTAssertFalse(app.staticTexts["Favorites"].exists, "favorites no longer live on Home")
    }

    @MainActor
    func testQuickAddStartsFromFavoriteMenu() {
        let app = launchApp()

        openQuickAdd(in: app)
        let menu = app.buttons["favoriteMenu.button"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "favorite menu should head a quick add")
        menu.tap()

        let item = app.buttons["favoriteMenu.item.\(seededFavorite)"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "seeded favorite should be in the menu")
        item.tap()

        assertRecordFormShowsSeededFavorite(in: app)
    }

    @MainActor
    func testManageFromMenuAddsFavoriteThatAppearsInMenu() {
        let app = launchApp()

        openQuickAdd(in: app)
        let menu = app.buttons["favoriteMenu.button"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        let manage = app.buttons["favoriteMenu.manage"]
        XCTAssertTrue(manage.waitForExistence(timeout: 5), "menu should offer Manage Favorites")
        manage.tap()

        XCTAssertTrue(
            app.buttons["manageFavorites.row.\(seededFavorite)"].waitForExistence(timeout: 5),
            "the seeded favorite should be listed"
        )

        app.buttons["manageFavorites.add"].tap()
        let nameField = app.textFields["favoriteForm.nameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "favorite form should appear")
        nameField.tap()
        // The name starts as the type's default; clear it before typing.
        let current = nameField.value as? String ?? ""
        nameField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        nameField.typeText("Pool Swim")
        app.buttons["favoriteForm.saveButton"].tap()

        XCTAssertTrue(
            app.buttons["manageFavorites.row.Pool Swim"].waitForExistence(timeout: 5),
            "the new favorite should be listed"
        )
        app.buttons["manageFavorites.done"].tap()

        menu.tap()
        XCTAssertTrue(
            app.buttons["favoriteMenu.item.Pool Swim"].waitForExistence(timeout: 5),
            "the new favorite should appear in the sheet's menu"
        )
    }

    @MainActor
    func testDurationPillSetsWheels() {
        let app = launchApp()

        openQuickAdd(in: app)
        let pill = app.buttons["duration.preset.45"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5), "duration pills should head the wheels")
        pill.tap()

        XCTAssertTrue(pill.isSelected, "the tapped pill should show as selected")
        XCTAssertEqual(app.pickerWheels.element(boundBy: 1).value as? String, "45m")
    }
}
