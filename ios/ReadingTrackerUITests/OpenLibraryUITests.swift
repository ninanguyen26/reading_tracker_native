import XCTest

final class OpenLibraryUITests: XCTestCase {
    func testPDFPagesHiddenSubjectsAndInlineReadMore() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-library", "-import-samples", "-open-library-fixtures", "-long-description-fixture"]
        app.launch()
        let book = app.descendants(matching: .any)["book-Field Notes"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 15))
        book.press(forDuration: 1)
        app.buttons["Book Details"].tap()
        let more = app.links["Read More"]
        XCTAssertTrue(more.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Read More"].exists)
        XCTAssertFalse(app.staticTexts["Subjects"].exists)
        let collapsed = XCTAttachment(screenshot: app.screenshot())
        collapsed.name = "Inline Read More and Pages"
        collapsed.lifetime = .keepAlways
        add(collapsed)
        more.tap()
        XCTAssertTrue(app.staticTexts["details-description"].label.contains("The final chapter follows the returning birds."))
        app.swipeUp()
        app.links["Show Less"].tap()
        app.swipeUp()
        let pages = app.descendants(matching: .any)["details-pages"].firstMatch
        XCTAssertTrue(pages.exists)
        XCTAssertTrue(pages.label.contains("6"))
        XCTAssertFalse(pages.label.contains("estimated"))
        let details = XCTAttachment(screenshot: app.screenshot())
        details.name = "PDF Actual Pages"
        details.lifetime = .keepAlways
        add(details)
    }

    func testAutomaticGenreManualCorrectionAndUnclassifiedPersist() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-library", "-import-samples", "-open-library-fixtures"]
        app.launch()
        openPDFDetails(app)
        XCTAssertTrue(app.staticTexts["Science & Technology"].waitForExistence(timeout: 10))
        app.buttons["Edit Genres"].tap()
        app.buttons["primary-genre-picker"].tap()
        app.descendants(matching: .any)["Romance"].firstMatch.tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Romance"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.terminate()
        app.launchArguments = []
        app.launch()
        openPDFDetails(app)
        XCTAssertTrue(app.staticTexts["Romance"].waitForExistence(timeout: 5))
        app.buttons["Edit Genres"].tap()
        app.buttons["primary-genre-picker"].tap()
        app.descendants(matching: .any)["Unclassified"].firstMatch.tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Unclassified"].waitForExistence(timeout: 5))
        app.buttons["Edit Genres"].tap()
        app.buttons["automatic-genre"].tap()
        XCTAssertTrue(app.staticTexts["Science & Technology"].waitForExistence(timeout: 10))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Book Genres"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openPDFDetails(_ app: XCUIApplication) {
        let book = app.descendants(matching: .any)["book-Field Notes"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 15))
        book.press(forDuration: 1)
        app.buttons["Book Details"].tap()
        app.swipeUp()
        XCTAssertTrue(app.buttons["Edit Genres"].waitForExistence(timeout: 5))
    }

    func testImportAutomaticallyAddsAndPersistsMissingDetails() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-library", "-import-samples", "-open-library-fixtures"]
        app.launch()
        let book = app.descendants(matching: .any)["book-Field Notes"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 15))
        book.press(forDuration: 1)
        app.buttons["Book Details"].tap()
        app.swipeUp()
        // No search, match selection, or save action: import triggers enrichment.
        XCTAssertTrue(app.staticTexts["Observations from the natural world."].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Nature Journals"].exists)
        let details = XCTAttachment(screenshot: app.screenshot())
        details.name = "Automatically Enriched Import"
        details.lifetime = .keepAlways
        add(details)
        app.buttons["Done"].tap()
        app.terminate()
        app.launchArguments = []
        app.launch()
        let saved = app.descendants(matching: .any)["book-Field Notes"].firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        saved.press(forDuration: 1)
        app.buttons["Book Details"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Observations from the natural world."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Nature Journals"].exists)
    }
}
