import XCTest

final class ShelfUITests: XCTestCase {
    private let epubTitle = "The Lighthouse Keeper"
    private let pdfTitle = "Field Notes"

    override func setUp() {
        continueAfterFailure = false
    }

    private func book(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["book-\(title)"].firstMatch
    }

    private func menuItem(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ AND (elementType == %d OR elementType == %d)",
                        title, XCUIElement.ElementType.menuItem.rawValue, XCUIElement.ElementType.button.rawValue)
        ).firstMatch
    }

    private func enterName(_ name: String, in app: XCUIApplication) {
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        app.alerts.buttons["Save"].tap()
    }

    func testOrganizesBooksOnShelves() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-library", "-import-samples"]
        app.launch()
        XCTAssertTrue(book(epubTitle, in: app).waitForExistence(timeout: 15))

        // A new shelf opens straight away, empty.
        app.buttons["New Shelf"].tap()
        enterName("Favorites", in: app)
        let favorites = app.buttons["shelf-Favorites"]
        XCTAssertTrue(favorites.waitForExistence(timeout: 5))
        XCTAssertEqual(favorites.label, "Favorites, 0 books")
        XCTAssertTrue(favorites.isSelected)
        XCTAssertFalse(book(epubTitle, in: app).exists)
        XCTAssertTrue(app.staticTexts["No books on this shelf yet. Touch and hold a book to add it."].exists)

        // Add a book from its menu.
        app.buttons["shelf-all"].tap()
        XCTAssertTrue(book(epubTitle, in: app).waitForExistence(timeout: 5))
        book(epubTitle, in: app).press(forDuration: 1)
        XCTAssertTrue(menuItem("Shelves", in: app).waitForExistence(timeout: 5))
        menuItem("Shelves", in: app).tap()
        XCTAssertTrue(menuItem("Favorites", in: app).waitForExistence(timeout: 5))
        menuItem("Favorites", in: app).tap()
        let oneBook = NSPredicate(format: "label == %@", "Favorites, 1 book")
        wait(for: [expectation(for: oneBook, evaluatedWith: favorites)], timeout: 5)

        // The shelf shows only its books.
        favorites.tap()
        XCTAssertTrue(book(epubTitle, in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(book(pdfTitle, in: app).exists)

        // A new shelf made from a book's menu holds that book, without leaving this shelf.
        book(epubTitle, in: app).press(forDuration: 1)
        XCTAssertTrue(menuItem("Shelves", in: app).waitForExistence(timeout: 5))
        menuItem("Shelves", in: app).tap()
        XCTAssertTrue(menuItem("New Shelf…", in: app).waitForExistence(timeout: 5))
        menuItem("New Shelf…", in: app).tap()
        enterName("Lent Out", in: app)
        let lentOut = app.buttons["shelf-Lent Out"]
        XCTAssertTrue(lentOut.waitForExistence(timeout: 5))
        XCTAssertEqual(lentOut.label, "Lent Out, 1 book")
        XCTAssertTrue(favorites.isSelected)

        // Rename the shelf.
        app.buttons["Shelf Options"].tap()
        XCTAssertTrue(menuItem("Rename Shelf", in: app).waitForExistence(timeout: 5))
        menuItem("Rename Shelf", in: app).tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Favorites")
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Favorites".count) + "Best")
        app.alerts.buttons["Save"].tap()
        let best = app.buttons["shelf-Best"]
        XCTAssertTrue(best.waitForExistence(timeout: 5))
        XCTAssertTrue(best.isSelected)

        // The chosen shelf is remembered across launches.
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(best.waitForExistence(timeout: 15))
        XCTAssertTrue(best.isSelected)
        XCTAssertFalse(book(pdfTitle, in: app).exists)

        // Deleting the shelf keeps its books.
        app.buttons["Shelf Options"].tap()
        XCTAssertTrue(menuItem("Delete Shelf", in: app).waitForExistence(timeout: 5))
        menuItem("Delete Shelf", in: app).tap()
        let confirm = app.sheets.buttons["Delete Shelf"].exists ? app.sheets.buttons["Delete Shelf"] : menuItem("Delete Shelf", in: app)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(book(pdfTitle, in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(book(epubTitle, in: app).exists)
        XCTAssertFalse(best.exists)
    }

    func testSelectsBooksInBulk() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-library", "-import-samples"]
        app.launch()
        XCTAssertTrue(book(epubTitle, in: app).waitForExistence(timeout: 15))

        // Select both books and put them on a new shelf.
        app.buttons["Select"].tap()
        XCTAssertFalse(app.buttons["tab-library"].exists)
        book(epubTitle, in: app).tap()
        book(pdfTitle, in: app).tap()
        XCTAssertTrue(book(epubTitle, in: app).isSelected)
        XCTAssertTrue(app.navigationBars["2 Selected"].exists)
        app.buttons["Add to Shelf"].tap()
        XCTAssertTrue(menuItem("New Shelf…", in: app).waitForExistence(timeout: 5))
        menuItem("New Shelf…", in: app).tap()
        enterName("Favorites", in: app)
        let favorites = app.buttons["shelf-Favorites"]
        XCTAssertTrue(favorites.waitForExistence(timeout: 5))
        let twoBooks = NSPredicate(format: "label == %@", "Favorites, 2 books")
        wait(for: [expectation(for: twoBooks, evaluatedWith: favorites)], timeout: 5)
        XCTAssertTrue(app.buttons["tab-library"].exists)

        // Remove them all from the shelf; they stay in the library.
        favorites.tap()
        app.buttons["Select"].tap()
        app.buttons["Select All"].tap()
        XCTAssertTrue(app.navigationBars["2 Selected"].exists)
        app.buttons["Remove from Shelf"].tap()
        let noBooks = NSPredicate(format: "label == %@", "Favorites, 0 books")
        wait(for: [expectation(for: noBooks, evaluatedWith: favorites)], timeout: 5)
        app.buttons["shelf-all"].tap()
        XCTAssertTrue(book(epubTitle, in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(book(pdfTitle, in: app).exists)

        // Delete acts only on selected books still in view.
        app.buttons["Select"].tap()
        app.buttons["Select All"].tap()
        let search = app.textFields["library-search"]
        search.tap()
        search.typeText("Field\n")
        XCTAssertTrue(app.navigationBars["1 Selected"].waitForExistence(timeout: 5))
        app.buttons["Delete"].tap()
        let confirm = menuItem("Delete 1 Book", in: app)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.buttons["tab-library"].waitForExistence(timeout: 5))
        app.buttons["Clear Search"].tap()
        XCTAssertTrue(book(epubTitle, in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(book(pdfTitle, in: app).exists)
    }
}
