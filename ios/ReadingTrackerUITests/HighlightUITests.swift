import XCTest

final class HighlightUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func openEPUB() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-library", "-import-samples"]
        app.launch()
        let book = app.descendants(matching: .any)["book-The Lighthouse Keeper"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 15))
        book.tap()
        XCTAssertTrue(app.staticTexts["reader-progress"].waitForExistence(timeout: 15))
        sleep(1) // let the page finish laying out before selecting text
        return app
    }

    /// Long-presses a word in the book and waits for the selection menu.
    private func selectWord(in app: XCUIApplication, at offset: CGVector) {
        let page = app.otherElements["reader-content"]
        page.coordinate(withNormalizedOffset: offset).press(forDuration: 1.2)
        // iOS sometimes only shows the menu after a tap on the selection.
        if !menuItem("Highlight", in: app).waitForExistence(timeout: 3) {
            page.coordinate(withNormalizedOffset: offset).tap()
        }
    }

    /// The selection menu's item, which iOS shows as a menu item or a button depending on layout.
    private func menuItem(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let item = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ AND (elementType == %d OR elementType == %d)",
                        title, XCUIElement.ElementType.menuItem.rawValue, XCUIElement.ElementType.button.rawValue)
        ).firstMatch
        return item
    }

    func testHighlightsAndAddsANote() {
        let app = openEPUB()
        selectWord(in: app, at: CGVector(dx: 0.5, dy: 0.28))
        let note = menuItem("Note", in: app)
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()

        // The editor opens ready to type a note.
        let field = app.textFields["highlight-note"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("A note about this")
        app.buttons["Pink"].tap()
        app.buttons["Done"].tap()

        // It's listed under Notes with its note.
        app.otherElements["reader-content"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).tap()
        XCTAssertTrue(app.buttons["Contents and Bookmarks"].waitForExistence(timeout: 5))
        app.buttons["Contents and Bookmarks"].tap()
        app.segmentedControls.buttons["Notes"].tap()
        let entry = app.buttons.matching(NSPredicate(format: "label CONTAINS 'A note about this'")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Export Notes"].exists)

        // Delete it from the list.
        entry.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'No highlights yet'")).firstMatch.waitForExistence(timeout: 5))
    }

    func testTheSelectionMenuOffersLookUp() {
        let app = openEPUB()
        selectWord(in: app, at: CGVector(dx: 0.5, dy: 0.28))
        XCTAssertTrue(menuItem("Highlight", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(menuItem("Look Up", in: app).exists)
    }
}
