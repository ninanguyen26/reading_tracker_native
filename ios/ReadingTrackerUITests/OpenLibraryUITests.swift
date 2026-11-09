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
        XCTAssertTrue(app.staticTexts["Science & Tech"].waitForExistence(timeout: 10))
        app.buttons["Edit Genres"].tap()
        let romance = app.buttons["genre-option-Romance"]
        let fantasy = app.buttons["genre-option-Fantasy"]
        let science = app.buttons["genre-option-Science & Technology"]
        romance.tap()
        fantasy.tap()
        let editor = XCTAttachment(screenshot: app.screenshot())
        editor.name = "Genre Multi-Select"
        editor.lifetime = .keepAlways
        add(editor)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Romance"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Fantasy"].exists)
        XCTAssertTrue(app.staticTexts["Science & Tech"].exists)
        app.navigationBars["Book Details"].buttons.firstMatch.tap()
        app.terminate()
        app.launchArguments = []
        app.launch()
        openPDFDetails(app)
        XCTAssertTrue(app.staticTexts["Romance"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Fantasy"].exists)
        app.buttons["Edit Genres"].tap()
        romance.tap()
        fantasy.tap()
        for _ in 0..<5 where !science.isHittable { app.swipeUp() }
        XCTAssertEqual(science.label, "Science & Tech")
        science.tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Unclassified"].waitForExistence(timeout: 5))
        app.buttons["Edit Genres"].tap()
        app.buttons["automatic-genre"].tap()
        XCTAssertTrue(app.staticTexts["Science & Tech"].waitForExistence(timeout: 10))
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

    func testHardcoverMoodsAreVisibleAndContentWarningsRequireReveal() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-library", "-import-samples", "-open-library-fixtures",
                               "-hardcover-reading-tags-fixture"]
        app.launch()
        openPDFDetails(app)
        let rating = app.descendants(matching: .any)["hardcover-rating"].firstMatch
        for _ in 0..<4 where !rating.isHittable { app.swipeUp() }
        XCTAssertTrue(rating.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Metadata"].exists)
        XCTAssertTrue(rating.label.contains("4.2 out of 5"))
        let metadata = XCTAttachment(screenshot: app.screenshot())
        metadata.name = "Hardcover Rating in Metadata"
        metadata.lifetime = .keepAlways
        add(metadata)
        let reveal = app.buttons["Show content warnings"]
        for _ in 0..<4 where !reveal.isHittable { app.swipeDown() }
        XCTAssertTrue(reveal.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["reflective"].exists)
        XCTAssertTrue(app.staticTexts["tense"].exists)
        XCTAssertFalse(app.staticTexts["Blood"].exists)
        reveal.tap()
        XCTAssertTrue(app.staticTexts["Blood"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Moods and Revealed Content Warnings"
        attachment.lifetime = .keepAlways
        add(attachment)
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
        app.navigationBars["Book Details"].buttons.firstMatch.tap()
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
