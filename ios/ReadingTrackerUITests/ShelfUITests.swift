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

    func testGenreMenuFiltersLibraryAndClearsWithoutResettingSearch() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-library", "-import-samples", "-open-library-fixtures"]
        app.launch()
        XCTAssertTrue(book(pdfTitle, in: app).waitForExistence(timeout: 15))
        XCTAssertTrue(book(epubTitle, in: app).waitForExistence(timeout: 5))

        let genres = app.buttons["library-genres"]
        let science = menuItem("Science & Tech (1)", in: app)
        let deadline = Date().addingTimeInterval(15)
        repeat {
            genres.tap()
            if science.waitForExistence(timeout: 1) { break }
            menuItem("All Genres (2)", in: app).tap()
        } while Date() < deadline
        XCTAssertTrue(science.exists)
        science.tap()
        XCTAssertEqual(genres.value as? String, "Science & Tech")
        XCTAssertTrue(book(pdfTitle, in: app).exists)
        XCTAssertFalse(book(epubTitle, in: app).exists)

        let search = app.textFields["library-search"]
        search.tap()
        search.typeText("Lighthouse\n")
        XCTAssertTrue(app.staticTexts["No books match this genre filter."].waitForExistence(timeout: 5))
        genres.tap()
        let allGenres = menuItem("All Genres (1)", in: app)
        XCTAssertTrue(allGenres.waitForExistence(timeout: 5))
        allGenres.tap()
        XCTAssertEqual(genres.value as? String, "All Genres")
        XCTAssertEqual(search.value as? String, "Lighthouse")
        XCTAssertTrue(book(epubTitle, in: app).exists)
        XCTAssertFalse(book(pdfTitle, in: app).exists)
    }

    func testBookDetailsGenreUsesLibraryControlsWithIndependentSearch() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-library", "-import-samples", "-open-library-fixtures"]
        app.launch()
        let pdf = book(pdfTitle, in: app)
        XCTAssertTrue(pdf.waitForExistence(timeout: 15))

        let search = app.textFields["library-search"]
        search.tap()
        search.typeText("Field\n")
        app.buttons["Sort"].tap()
        menuItem("Card", in: app).tap()
        let moreActions = app.buttons["More actions for \(pdfTitle)"]
        let read = app.buttons["Read Book"]
        let openDetails = app.buttons["Book Details"]
        XCTAssertTrue(read.waitForExistence(timeout: 5))
        XCTAssertTrue(openDetails.exists)
        XCTAssertLessThan(read.frame.maxX, openDetails.frame.minX)
        XCTAssertEqual(read.frame.midY, openDetails.frame.midY, accuracy: 1)
        read.tap()
        XCTAssertTrue(app.descendants(matching: .any)["reader-progress"].firstMatch.waitForExistence(timeout: 15))
        let back = app.navigationBars.buttons.firstMatch
        if !back.exists {
            app.otherElements["reader-content"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(moreActions.waitForExistence(timeout: 5))
        moreActions.tap()
        let changeStatus = menuItem("Change Status", in: app)
        XCTAssertTrue(changeStatus.waitForExistence(timeout: 5))
        XCTAssertFalse(app.menuItems["Book Details"].exists)
        XCTAssertFalse(openDetails.isHittable)
        changeStatus.tap()
        menuItem("Reading", in: app).tap()
        XCTAssertTrue(app.buttons["Continue Reading"].waitForExistence(timeout: 5))
        openDetails.tap()
        let details = app.navigationBars["Book Details"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        let genreChip = app.buttons["Science & Tech"]
        for _ in 0..<4 where !genreChip.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(genreChip.isHittable)
        genreChip.tap()

        let genre = app.navigationBars["Science & Tech"]
        XCTAssertTrue(genre.waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "Title or author")
        XCTAssertTrue(pdf.exists)
        XCTAssertFalse(book(epubTitle, in: app).exists)

        app.buttons["Sort"].tap()
        let rating = menuItem("Rating", in: app)
        XCTAssertTrue(rating.waitForExistence(timeout: 5))
        rating.tap()
        app.buttons["Sort"].tap()
        menuItem("Grid", in: app).tap()
        XCTAssertTrue(pdf.exists)
        XCTAssertFalse(moreActions.exists)

        search.tap()
        search.typeText("Lighthouse\n")
        XCTAssertTrue(app.staticTexts["No books match “Lighthouse”."].waitForExistence(timeout: 5))
        XCTAssertFalse(pdf.exists)
        app.buttons["Clear Search"].tap()
        XCTAssertTrue(pdf.exists)

        genre.buttons.firstMatch.tap()
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        details.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "Field")
        XCTAssertTrue(pdf.exists)
        XCTAssertFalse(moreActions.exists)
    }

    func testBookDetailsBackPreservesShelfSearchAndScroll() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-library", "-import-samples", "-layout-samples", "-open-library-fixtures"]
        app.launch()
        let allBooks = app.buttons["shelf-all"]
        wait(for: [expectation(for: NSPredicate(format: "label == %@", "All Books, 6 books"), evaluatedWith: allBooks)], timeout: 15)

        app.buttons["Select"].tap()
        app.buttons["Select All"].tap()
        app.buttons["Add to Shelf"].tap()
        menuItem("New Shelf…", in: app).tap()
        enterName("Favorites", in: app)
        let shelf = app.buttons["shelf-Favorites"]
        XCTAssertTrue(shelf.waitForExistence(timeout: 5))
        shelf.tap()

        let search = app.textFields["library-search"]
        search.tap()
        search.typeText("a\n")
        let library = app.scrollViews["library-scroll"]
        let firstBook = app.buttons.matching(identifier: "book-\(epubTitle)").firstMatch
        let initialY = firstBook.frame.minY
        library.swipeUp()
        library.swipeUp()
        let lastBook = app.buttons.matching(identifier: "book-\(epubTitle)").element(boundBy: 2)
        XCTAssertTrue(lastBook.isHittable)
        XCTAssertLessThan(firstBook.frame.minY, initialY - 50)
        let scrolledY = lastBook.frame.minY
        lastBook.press(forDuration: 1)
        menuItem("Book Details", in: app).tap()
        let details = app.navigationBars["Book Details"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tab-library"].exists)
        details.buttons.firstMatch.tap()

        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        XCTAssertTrue(shelf.isSelected)
        XCTAssertEqual(search.value as? String, "a")
        XCTAssertTrue(lastBook.isHittable)
        XCTAssertEqual(lastBook.frame.minY, scrolledY, accuracy: 3)
    }

    func testReadingStatusControlsFilterBooksAndUpdateStats() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-library", "-import-samples", "-open-library-fixtures",
                               "-hardcover-reading-tags-fixture"]
        app.launch()
        let epub = book(epubTitle, in: app)
        let pdf = book(pdfTitle, in: app)
        XCTAssertTrue(epub.waitForExistence(timeout: 15))
        XCTAssertTrue(pdf.waitForExistence(timeout: 15))

        let filter = app.buttons["Filter books"]
        XCTAssertEqual(filter.value as? String, "All Books")
        XCTAssertLessThan(filter.frame.maxX, app.buttons["Sort"].frame.minX)
        XCTAssertFalse(app.navigationBars["Library"].buttons["Wishlist"].exists)

        func chooseFilter(_ title: String) {
            filter.tap()
            menuItem(title, in: app).tap()
            XCTAssertEqual(filter.value as? String, title)
        }

        chooseFilter("Wishlist")
        XCTAssertTrue(app.staticTexts["Your wishlist is empty"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Library"].exists)
        XCTAssertFalse(epub.exists)
        XCTAssertFalse(pdf.exists)

        chooseFilter("TBR")
        XCTAssertTrue(epub.exists)
        XCTAssertTrue(pdf.exists)

        pdf.press(forDuration: 1)
        menuItem("Change Status", in: app).tap()
        menuItem("Reading", in: app).tap()
        chooseFilter("Reading")
        XCTAssertTrue(pdf.waitForExistence(timeout: 5))
        XCTAssertFalse(epub.exists)

        pdf.press(forDuration: 1)
        menuItem("Book Details", in: app).tap()
        let status = app.buttons["book-reading-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.value as? String, "Reading")
        status.tap()
        menuItem("DNF", in: app).tap()
        let didNotFinish = NSPredicate(format: "value == %@", "DNF")
        wait(for: [expectation(for: didNotFinish, evaluatedWith: status)], timeout: 5)
        app.navigationBars["Book Details"].buttons.firstMatch.tap()
        chooseFilter("DNF")
        XCTAssertTrue(pdf.waitForExistence(timeout: 5))
        XCTAssertFalse(epub.exists)

        chooseFilter("All Books")
        app.buttons["Select"].tap()
        app.buttons["Select All"].tap()
        app.buttons["Change Status"].tap()
        menuItem("Finished", in: app).tap()
        chooseFilter("Finished")
        XCTAssertTrue(epub.waitForExistence(timeout: 5))
        XCTAssertTrue(pdf.exists)

        let library = XCTAttachment(screenshot: app.screenshot())
        library.name = "Library Filtered by Reading Status"
        library.lifetime = .keepAlways
        add(library)

        app.buttons["tab-stats"].tap()
        let finishedCount = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Finished, 2")).firstMatch
        XCTAssertTrue(finishedCount.waitForExistence(timeout: 5))
        let stats = XCTAttachment(screenshot: app.screenshot())
        stats.name = "Reading Status Stats"
        stats.lifetime = .keepAlways
        add(stats)
    }
}
