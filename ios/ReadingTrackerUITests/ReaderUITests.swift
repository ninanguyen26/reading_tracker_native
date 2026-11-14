import XCTest

final class ReaderUITests: XCTestCase {
    private let epubTitle = "The Lighthouse Keeper"
    private let pdfTitle = "Field Notes"

    override func setUp() {
        continueAfterFailure = false
    }

    /// Launches the app; `fresh` starts from an empty library with the two sample books added.
    private func launch(fresh: Bool, appearance: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = fresh ? ["-reset-library", "-import-samples"] : []
        if let appearance { app.launchEnvironment["UITEST_APPEARANCE"] = appearance }
        app.launch()
        return app
    }

    private func book(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["book-\(title)"].firstMatch
    }

    private func progress(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["reader-progress"].firstMatch
    }

    /// Waits until the reader's progress line matches the given pattern, returning its text.
    @discardableResult
    private func waitForProgress(in app: XCUIApplication, matching pattern: String, timeout: TimeInterval = 15) -> String {
        let label = progress(in: app)
        let matches = NSPredicate(format: "label MATCHES %@", pattern)
        let found = expectation(for: matches, evaluatedWith: label)
        wait(for: [found], timeout: timeout)
        return label.label
    }

    private func turnPage(in app: XCUIApplication) {
        app.otherElements["reader-content"].coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    }

    private func goBack(in app: XCUIApplication) {
        // Page turns hide the toolbar; a tap in the middle shows it again.
        if !app.navigationBars.buttons.element(boundBy: 0).exists {
            app.otherElements["reader-content"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertTrue(app.navigationBars.buttons.element(boundBy: 0).waitForExistence(timeout: 5))
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
    }

    private func filterLibrary(_ title: String, in app: XCUIApplication) {
        app.buttons["Filter books"].tap()
        let option = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ AND (elementType == %d OR elementType == %d)",
                        title, XCUIElement.ElementType.menuItem.rawValue, XCUIElement.ElementType.button.rawValue)
        ).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
    }

    func testLibraryShowsImportedBooks() {
        let app = launch(fresh: true)
        XCTAssertTrue(book(epubTitle, in: app).waitForExistence(timeout: 15))
        XCTAssertTrue(book(pdfTitle, in: app).exists)
        XCTAssertTrue(book(epubTitle, in: app).label.contains("by Avery Quinn"))
        XCTAssertTrue(book(epubTitle, in: app).label.contains("Unrated, 0% read"))
    }

    func testMainNavigationSearchAndAddBooks() {
        let app = launch(fresh: true)
        XCTAssertTrue(book(epubTitle, in: app).waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["tab-library"].isSelected)
        let search = app.textFields["library-search"]
        XCTAssertTrue(search.exists)
        XCTAssertLessThan(search.frame.maxY, book(epubTitle, in: app).frame.minY)
        XCTAssertLessThan(search.frame.minX, app.buttons["Sort"].frame.minX)
        captureDetails("Library Navigation", in: app)
        search.tap()
        search.typeText("Lighthouse\n")
        XCTAssertTrue(book(epubTitle, in: app).exists)
        XCTAssertFalse(book(pdfTitle, in: app).exists)
        app.buttons["Clear Search"].tap()

        app.buttons["tab-home"].tap()
        XCTAssertTrue(app.staticTexts["home-title"].exists)
        XCTAssertFalse(book(epubTitle, in: app).exists)
        app.buttons["Browse Library"].tap()
        XCTAssertTrue(book(epubTitle, in: app).exists)
        app.buttons["tab-stats"].tap()
        XCTAssertTrue(app.navigationBars["Stats"].exists)
        XCTAssertTrue(app.staticTexts["Your Library"].exists)
        app.buttons["tab-settings"].tap()
        XCTAssertTrue(app.buttons["Reading Preferences"].exists)
        app.buttons["Reading Preferences"].tap()
        XCTAssertTrue(app.navigationBars["Reading Settings"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["Add Books"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 15))
        app.buttons["Cancel"].tap()

        app.buttons["tab-library"].tap()
        XCTAssertTrue(book(epubTitle, in: app).waitForExistence(timeout: 5))
        book(epubTitle, in: app).tap()
        waitForProgress(in: app, matching: "Location 1 of .*")
        XCTAssertFalse(app.buttons["tab-home"].exists)
        goBack(in: app)
        XCTAssertTrue(app.buttons["tab-home"].exists)
    }

    func testHomeAndLibraryContentClearsCompactNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-library", "-import-samples", "-layout-samples", "-open-library-fixtures"]
        app.launch()
        XCTAssertTrue(book(epubTitle, in: app).waitForExistence(timeout: 15))
        let homeTab = app.buttons["tab-home"]
        XCTAssertLessThan(app.navigationBars["Library"].frame.height, 60)
        let library = app.scrollViews["library-scroll"]
        XCTAssertLessThanOrEqual(library.frame.maxY, homeTab.frame.minY)
        library.swipeUp()
        library.swipeUp()
        let lastLibraryBook = app.buttons.matching(identifier: "book-\(epubTitle)").element(boundBy: 2)
        XCTAssertTrue(lastLibraryBook.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(lastLibraryBook.frame.maxY, homeTab.frame.minY)
        captureDetails("Library Bottom Clearance", in: app)

        app.scrollViews["library-scroll"].swipeDown()
        book(pdfTitle, in: app).tap()
        waitForProgress(in: app, matching: "Page 1 of .*")
        turnPage(in: app)
        waitForProgress(in: app, matching: "Page 2 of .*")
        goBack(in: app)
        homeTab.tap()
        XCTAssertLessThanOrEqual(app.staticTexts["home-title"].frame.height, 32)
        let home = app.scrollViews["home-scroll"]
        XCTAssertLessThanOrEqual(home.frame.maxY, homeTab.frame.minY)
        let resume = book(pdfTitle, in: app)
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        XCTAssertFalse(book(epubTitle, in: app).exists)
        XCTAssertLessThanOrEqual(resume.frame.maxY, homeTab.frame.minY)
        XCTAssertLessThanOrEqual(app.frame.maxY - homeTab.frame.maxY, 45)
        captureDetails("Home Bottom Clearance", in: app)
        resume.tap()
        waitForProgress(in: app, matching: "Page 2 of .*")
    }

    func testDiscoverFeedbackAndWishlist() {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-library", "-open-library-fixtures", "-discover-page-fixtures"]
        app.launch()
        app.buttons["tab-home"].tap()
        let covers = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "discover-cover-"))
        let first = covers.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        XCTAssertEqual(covers.count, 5)
        let firstID = first.identifier
        let firstTitle = first.label
        first.tap()
        XCTAssertTrue(app.navigationBars["Book Preview"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Why this pick?"].exists)
        let like = app.buttons["discover-feedback-moreLikeThis"]
        let dislike = app.buttons["discover-feedback-notForMe"]
        let read = app.buttons["discover-feedback-alreadyRead"]
        XCTAssertTrue(like.isHittable)
        XCTAssertTrue(dislike.isHittable)
        XCTAssertTrue(read.isHittable)
        captureDetails("Discover preview", in: app)
        like.tap()
        XCTAssertTrue(like.isSelected)
        read.tap()
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons[firstID].exists)
        XCTAssertEqual(covers.count, 5)
        app.buttons["Undo"].tap()
        XCTAssertTrue(app.buttons[firstID].exists)
        app.buttons[firstID].tap()
        XCTAssertTrue(like.waitForExistence(timeout: 5))
        XCTAssertTrue(like.isSelected)
        app.buttons["Save to Wishlist"].tap()
        XCTAssertTrue(app.buttons["Saved"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertFalse(app.buttons[firstID].exists)
        XCTAssertEqual(covers.count, 5)

        let second = covers.firstMatch
        let secondID = second.identifier
        second.tap()
        XCTAssertTrue(dislike.waitForExistence(timeout: 5))
        dislike.tap()
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons[secondID].exists)

        app.buttons["tab-library"].tap()
        filterLibrary("Wishlist", in: app)
        let saved = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", firstTitle + ", by ")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()
        XCTAssertTrue(app.buttons["Saved"].waitForExistence(timeout: 5))
        XCTAssertFalse(read.exists)

        app.terminate()
        app.launchArguments = ["-open-library-fixtures", "-discover-page-fixtures"]
        app.launch()
        app.buttons["tab-home"].tap()
        XCTAssertTrue(covers.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons[firstID].exists)
        XCTAssertFalse(app.buttons[secondID].exists)
        let current = Set(covers.allElementsBoundByIndex.map(\.identifier))
        app.buttons["More picks"].tap()
        XCTAssertTrue(app.buttons["discover-cover-900036"].waitForExistence(timeout: 5))
        XCTAssertEqual(covers.count, 5)
        XCTAssertTrue(current.isDisjoint(with: covers.allElementsBoundByIndex.map(\.identifier)))
    }

    func testPaletteInLightAndDarkAppearance() {
        for appearance in ["light", "dark"] {
            let app = launch(fresh: true, appearance: appearance)
            XCTAssertTrue(book(epubTitle, in: app).waitForExistence(timeout: 15))
            captureDetails("\(appearance) Library", in: app)
            book(epubTitle, in: app).press(forDuration: 1)
            app.buttons["Book Details"].tap()
            XCTAssertTrue(app.navigationBars["Book Details"].waitForExistence(timeout: 5))
            captureDetails("\(appearance) Details", in: app)
            app.navigationBars["Book Details"].buttons.firstMatch.tap()
            app.buttons["tab-stats"].tap()
            XCTAssertTrue(app.navigationBars["Stats"].exists)
            captureDetails("\(appearance) Stats", in: app)
            app.buttons["tab-settings"].tap()
            XCTAssertTrue(app.buttons["Reading Preferences"].exists)
            captureDetails("\(appearance) Settings", in: app)
            app.terminate()
        }
    }

    func testAddButtonDarkLaunchPresentation() {
        let app = launch(fresh: true, appearance: "dark")
        XCTAssertTrue(book(epubTitle, in: app).waitForExistence(timeout: 15))
        captureDetails("dark Add initial", in: app)
        XCTAssertGreaterThan(app.buttons["Add Books"].frame.width, 44)
        captureDetails("dark Add settled", in: app)
        app.buttons["Add Books"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        captureDetails("dark Add after picker", in: app)
    }

    func testBookDetailsShowsAvailableEpubMetadataAndOpensReader() {
        let app = launch(fresh: true)
        XCTAssertTrue(book(epubTitle, in: app).waitForExistence(timeout: 15))
        book(epubTitle, in: app).press(forDuration: 1)
        app.buttons["Book Details"].tap()
        XCTAssertTrue(app.navigationBars["Book Details"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["details-description"].label, "A keeper watches over an isolated island.")
        captureDetails("EPUB Book Details", in: app)
        app.scrollViews.firstMatch.swipeUp()
        XCTAssertTrue(app.staticTexts["In This Series"].exists)
        XCTAssertTrue(app.staticTexts["#2.5 of Island Stories"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Coastal Tales")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Subjects"].exists)
        XCTAssertFalse(app.staticTexts["Sea stories"].exists)
        XCTAssertTrue(app.staticTexts["Languages"].exists)
        captureDetails("EPUB Metadata", in: app)
        app.scrollViews.firstMatch.swipeDown()
        app.buttons["Read Book"].tap()
        waitForProgress(in: app, matching: "Location 1 of .*")
        goBack(in: app)
    }

    func testBookDetailsButtonsAndLayoutInBothAppearances() {
        for appearance in ["light", "dark"] {
            let app = launch(fresh: true, appearance: appearance)
            XCTAssertTrue(book(epubTitle, in: app).waitForExistence(timeout: 15))
            book(epubTitle, in: app).press(forDuration: 1)
            app.buttons["Book Details"].tap()
            let edit = app.buttons["Edit Genres"]
            XCTAssertTrue(edit.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(edit.frame.height, 43.5)
            XCTAssertGreaterThanOrEqual(app.buttons["Read Book"].frame.height, 43.5)
            captureDetails("\(appearance) Redesigned Book Details", in: app)
            app.scrollViews.firstMatch.swipeUp()
            let lookup = app.buttons["find-missing-details"]
            XCTAssertTrue(lookup.exists)
            XCTAssertGreaterThanOrEqual(lookup.frame.height, 43.5)
            captureDetails("\(appearance) Redesigned Metadata", in: app)
            app.navigationBars["Book Details"].buttons.firstMatch.tap()
            app.terminate()
        }
    }

    func testPDFDetailsHidesMissingFieldsAndCanBeOpenedFromReader() {
        let app = launch(fresh: true)
        XCTAssertTrue(book(pdfTitle, in: app).waitForExistence(timeout: 15))
        book(pdfTitle, in: app).press(forDuration: 1)
        app.buttons["Book Details"].tap()
        XCTAssertTrue(app.navigationBars["Book Details"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[pdfTitle].exists)
        XCTAssertTrue(app.staticTexts["PDF"].exists)
        for heading in ["Description", "In This Series", "Subjects", "Language", "Languages"] {
            XCTAssertFalse(app.staticTexts[heading].exists)
        }
        captureDetails("PDF Book Details", in: app)
        app.buttons["Read Book"].tap()
        waitForProgress(in: app, matching: "Page 1 of 6 · 0%")
        turnPage(in: app)
        let page = waitForProgress(in: app, matching: "Page 2 of 6 · \\d+%")
        showToolbar(in: app)
        app.buttons["Book Details"].tap()
        let details = app.navigationBars["Book Details"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        let continueReading = app.buttons["Continue Reading"]
        XCTAssertTrue(continueReading.isHittable)
        let lookup = app.buttons["find-missing-details"]
        for _ in 0..<4 where !lookup.isHittable { app.scrollViews.firstMatch.swipeUp() }
        lookup.tap()
        let lookupBar = app.navigationBars["Find Missing Details"]
        XCTAssertTrue(lookupBar.waitForExistence(timeout: 5))
        lookupBar.buttons["Cancel"].tap()
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertTrue(continueReading.isHittable)
        continueReading.tap()
        XCTAssertTrue(app.staticTexts["reader-title"].waitForExistence(timeout: 5))
        waitForProgress(in: app, matching: NSRegularExpression.escapedPattern(for: page))
    }

    private func captureDetails(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testEpubFooterAndSettingsShareDisplayPreference() {
        let app = launch(fresh: true)
        let sample = book(epubTitle, in: app)
        XCTAssertTrue(sample.waitForExistence(timeout: 15))
        sample.tap()

        let location = waitForProgress(in: app, matching: "Location 1 of .*", timeout: 30)
        let footer = app.buttons["reader-progress"]
        footer.tap()
        let initialChapter = waitForProgress(in: app, matching: "About .* left in chapter")
        footer.tap()
        let initialBook = waitForProgress(in: app, matching: "About .* left in book")

        if !app.buttons["Contents and Bookmarks"].exists {
            app.otherElements["reader-content"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        let options = app.buttons["Reader Options"]
        if options.exists { options.tap() }
        app.buttons["Reading Settings"].tap()
        XCTAssertTrue(app.navigationBars["Reading Settings"].waitForExistence(timeout: 5))
        let picker = app.buttons["footer-display"]
        revealInSheet(picker, in: app)
        XCTAssertGreaterThan(picker.frame.midY, app.buttons["Scroll"].frame.midY)
        XCTAssertEqual(picker.value as? String, "Time left in book")
        picker.tap()
        app.buttons["Time left in chapter"].tap()

        let speedPicker = app.buttons["reading-speed"]
        revealInSheet(speedPicker, in: app)
        XCTAssertEqual(speedPicker.value as? String, "200 WPM")
        speedPicker.tap()
        app.buttons["250 WPM"].tap()
        app.buttons["Save speed"].tap()
        XCTAssertEqual(speedPicker.value as? String, "250 WPM")
        app.buttons["Done"].tap()
        let fasterChapter = waitForProgress(in: app, matching: "About .* left in chapter")
        XCTAssertNotEqual(fasterChapter, initialChapter)

        footer.tap()
        let fasterBook = waitForProgress(in: app, matching: "About .* left in book")
        XCTAssertNotEqual(fasterBook, initialBook)
        footer.tap()
        XCTAssertEqual(footer.label, location)
    }

    func testReadingSpeedPresetsAndStopwatchCalculatorUpdateBothEstimates() throws {
        let app = launch(fresh: true)
        app.buttons["tab-settings"].tap()
        app.buttons["Reading Preferences"].tap()

        let speedPicker = app.buttons["reading-speed"]
        revealInSheet(speedPicker, in: app)
        XCTAssertEqual(speedPicker.value as? String, "200 WPM")
        speedPicker.tap()
        app.buttons["250 WPM"].tap()
        app.buttons["Save speed"].tap()
        XCTAssertEqual(speedPicker.value as? String, "250 WPM")

        speedPicker.tap()
        let entry = app.textFields["reading-speed-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        entry.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "235")
        app.buttons["Save speed"].tap()
        XCTAssertEqual(speedPicker.value as? String, "235 WPM")

        let calculator = app.buttons["Stopwatch calculator"]
        revealInSheet(calculator, in: app)
        calculator.tap()
        let start = app.buttons["Start stopwatch"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        app.buttons["Stop stopwatch"].tap()
        let result = app.staticTexts["calculated-reading-speed"]
        let visible = NSPredicate(format: "hittable == true")
        wait(for: [expectation(for: visible, evaluatedWith: result)], timeout: 5)
        revealInSheet(entry, in: app)
        let measuredSeconds = try XCTUnwrap(entry.value as? String)
        XCTAssertGreaterThan(Int(measuredSeconds) ?? 0, 0)
        entry.tap()
        entry.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: measuredSeconds.count) + "75")
        wait(for: [expectation(for: visible, evaluatedWith: result)], timeout: 5)
        XCTAssertEqual(result.label, "160 WPM")
        let explanation = app.staticTexts["reading-speed-explanation"]
        XCTAssertTrue(explanation.label.contains("words per minute"))
        XCTAssertTrue(explanation.label.contains("chapter and book"))
        let save = app.buttons["Save speed"]
        XCTAssertGreaterThan(save.frame.minY, result.frame.maxY)
        captureDetails("Stopwatch reading speed result", in: app)
        save.tap()
        XCTAssertEqual(speedPicker.value as? String, "160 WPM")

        app.buttons["Done"].tap()
        app.buttons["tab-library"].tap()
        let sample = book(epubTitle, in: app)
        XCTAssertTrue(sample.waitForExistence(timeout: 15))
        sample.tap()

        waitForProgress(in: app, matching: "Location 1 of .*", timeout: 30)
        let footer = app.buttons["reader-progress"]
        footer.tap()
        waitForProgress(in: app, matching: "About 12 min left in chapter")
        footer.tap()
        waitForProgress(in: app, matching: "About 37 min left in book")
    }

    func testReadsAnEpubAndRemembersThePosition() {
        var app = launch(fresh: true)
        XCTAssertTrue(book(epubTitle, in: app).waitForExistence(timeout: 15))
        book(epubTitle, in: app).tap()

        let start = waitForProgress(in: app, matching: "Location 1 of \\d+ · \\d+%")
        turnPage(in: app)
        turnPage(in: app)
        // The sample book is tiny, so the location number may not change; the percentage does.
        let afterTurning = waitForProgress(in: app, matching: "Location \\d+ of \\d+ · \\d+%")
        let percent = { (label: String) in Int(label.split(separator: "·").last!.dropLast().trimmingCharacters(in: .whitespaces)) ?? 0 }
        XCTAssertGreaterThan(percent(afterTurning), percent(start))

        goBack(in: app)
        XCTAssertTrue(book(epubTitle, in: app).label.hasSuffix("\(percent(afterTurning))% read"))
        filterLibrary("Reading", in: app)
        XCTAssertTrue(book(epubTitle, in: app).exists)

        // Reopen after quitting the app.
        app.terminate()
        app = launch(fresh: false)
        XCTAssertTrue(book(epubTitle, in: app).waitForExistence(timeout: 15))
        book(epubTitle, in: app).tap()
        waitForProgress(in: app, matching: NSRegularExpression.escapedPattern(for: afterTurning))
    }

    func testReadsAPdfPageByPage() {
        let app = launch(fresh: true)
        XCTAssertTrue(book(pdfTitle, in: app).waitForExistence(timeout: 15))
        book(pdfTitle, in: app).tap()
        waitForProgress(in: app, matching: "Page 1 of 6 · 0%")
        goBack(in: app)
        filterLibrary("TBR", in: app)
        XCTAssertTrue(book(pdfTitle, in: app).exists)
        book(pdfTitle, in: app).tap()
        waitForProgress(in: app, matching: "Page 1 of 6 · 0%")
        turnPage(in: app)
        waitForProgress(in: app, matching: "Page 2 of 6 · \\d+%")
        // Turning the page hides the toolbar; a tap in the middle brings it back.
        XCTAssertTrue(app.staticTexts["reader-title"].waitForNonExistence(timeout: 5))
        app.otherElements["reader-content"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["reader-title"].waitForExistence(timeout: 5))
        app.otherElements["reader-content"].coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap()
        waitForProgress(in: app, matching: "Page 1 of 6 · 0%")
        goBack(in: app)
        filterLibrary("Reading", in: app)
        XCTAssertTrue(book(pdfTitle, in: app).exists)
    }

    func testReadingSettingsApplyAndPersist() {
        var app = launch(fresh: true)
        XCTAssertTrue(book(epubTitle, in: app).waitForExistence(timeout: 15))
        book(epubTitle, in: app).tap()
        waitForProgress(in: app, matching: "Location 1 of .*")
        showToolbar(in: app)
        app.buttons["Reading Settings"].tap()

        app.buttons["Sepia theme"].tap()
        XCTAssertTrue(app.buttons["Sepia theme"].isSelected)
        app.buttons["Larger Text"].tap()
        XCTAssertEqual(app.staticTexts["font-size"].label, "110%")
        revealInSheet(app.buttons["Scroll"], in: app)
        app.buttons["Scroll"].tap()
        app.buttons["Done"].tap()

        // In scroll mode, swiping up moves through the book.
        let before = progress(in: app).label
        app.otherElements["reader-content"].swipeUp()
        app.otherElements["reader-content"].swipeUp()
        let moved = NSPredicate(format: "label != %@", before)
        wait(for: [expectation(for: moved, evaluatedWith: progress(in: app))], timeout: 10)
        goBack(in: app)
        filterLibrary("Reading", in: app)
        XCTAssertTrue(book(epubTitle, in: app).exists)

        // Settings are kept after quitting.
        app.terminate()
        app = launch(fresh: false)
        XCTAssertTrue(book(epubTitle, in: app).waitForExistence(timeout: 15))
        book(epubTitle, in: app).tap()
        waitForProgress(in: app, matching: "Location .*")
        showToolbar(in: app)
        app.buttons["Reading Settings"].tap()
        XCTAssertTrue(app.buttons["Sepia theme"].isSelected)
        XCTAssertEqual(app.staticTexts["font-size"].label, "110%")
        revealInSheet(app.buttons["Scroll"], in: app)
        XCTAssertTrue(app.buttons["Scroll"].isSelected)
    }

    func testReaderClockAndTextAlignmentPersist() {
        var app = launch(fresh: true)
        app.buttons["tab-settings"].tap()
        app.buttons["Reading Preferences"].tap()

        let alignment = app.buttons["reader-text-alignment"]
        revealInSheet(alignment, in: app)
        XCTAssertEqual(alignment.value as? String, "Original")
        alignment.tap()
        XCTAssertTrue(app.buttons["Original"].exists)
        XCTAssertTrue(app.buttons["Align to start"].exists)
        app.buttons["Justified"].tap()
        XCTAssertEqual(alignment.value as? String, "Justified")

        let clockToggle = app.switches["reader-show-clock"]
        revealInSheet(clockToggle, in: app)
        XCTAssertEqual(clockToggle.value as? String, "0")
        clockToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        wait(for: [expectation(for: NSPredicate(format: "value == %@", "1"), evaluatedWith: clockToggle)], timeout: 5)
        app.buttons["Done"].tap()

        app.terminate()
        app = launch(fresh: false)
        app.buttons["tab-settings"].tap()
        app.buttons["Reading Preferences"].tap()
        let savedAlignment = app.buttons["reader-text-alignment"]
        revealInSheet(savedAlignment, in: app)
        XCTAssertEqual(savedAlignment.value as? String, "Justified")
        app.buttons["Done"].tap()

        app.buttons["tab-library"].tap()
        let sample = book(epubTitle, in: app)
        XCTAssertTrue(sample.waitForExistence(timeout: 15))
        sample.tap()
        waitForProgress(in: app, matching: "Location 1 of .*")
        let clock = app.staticTexts["reader-clock"]
        XCTAssertTrue(clock.waitForExistence(timeout: 5))
        XCTAssertFalse((clock.value as? String ?? "").isEmpty)
        captureDetails("Reader clock and justified text", in: app)
    }

    func testFontSamplesScrollAndPersist() {
        var app = launch(fresh: true)
        app.buttons["tab-settings"].tap()
        app.buttons["Reading Preferences"].tap()

        let fontOptions = app.scrollViews["reader-font-options"]
        revealInSheet(fontOptions.buttons["Original"], in: app)
        XCTAssertTrue(fontOptions.buttons["Original"].isSelected)
        captureDetails("Font samples", in: app)
        let baskerville = fontOptions.buttons["Baskerville"]
        for _ in 0..<5 where !baskerville.isHittable { fontOptions.swipeLeft() }
        XCTAssertTrue(baskerville.isHittable)
        baskerville.tap()
        XCTAssertTrue(baskerville.isSelected)
        captureDetails("Selected font sample", in: app)

        app.buttons["Done"].tap()
        app.terminate()
        app = launch(fresh: false)
        app.buttons["tab-settings"].tap()
        app.buttons["Reading Preferences"].tap()

        let savedFont = app.scrollViews["reader-font-options"].buttons["Baskerville"]
        revealInSheet(savedFont, in: app)
        XCTAssertTrue(savedFont.isSelected)
    }

    /// The settings sheet opens at half height; scroll it until the control is reachable.
    private func revealInSheet(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 where !element.isHittable {
            app.collectionViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    private func showToolbar(in app: XCUIApplication) {
        guard !app.buttons["Reading Settings"].exists else { return }
        app.otherElements["reader-content"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Reading Settings"].waitForExistence(timeout: 5))
    }

    func testTappingTheMiddleTogglesTheToolbar() {
        let app = launch(fresh: true)
        XCTAssertTrue(book(epubTitle, in: app).waitForExistence(timeout: 15))
        book(epubTitle, in: app).tap()
        waitForProgress(in: app, matching: "Location 1 of .*")
        // Books open full-screen; a tap in the middle shows the toolbar, another hides it.
        let title = app.staticTexts["reader-title"]
        XCTAssertFalse(title.exists)
        app.otherElements["reader-content"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, epubTitle)
        app.otherElements["reader-content"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
    }
}
