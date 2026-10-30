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
        app.staticTexts["reader-progress"]
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

    func testLibraryShowsImportedBooks() {
        let app = launch(fresh: true)
        XCTAssertTrue(book(epubTitle, in: app).waitForExistence(timeout: 15))
        XCTAssertTrue(book(pdfTitle, in: app).exists)
        XCTAssertTrue(book(epubTitle, in: app).label.contains("by Avery Quinn"))
        XCTAssertTrue(book(epubTitle, in: app).label.contains("New"))
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

        homeTab.tap()
        XCTAssertLessThanOrEqual(app.staticTexts["home-title"].frame.height, 32)
        let home = app.scrollViews["home-scroll"]
        XCTAssertLessThanOrEqual(home.frame.maxY, homeTab.frame.minY)
        home.swipeUp()
        let lastHomeBook = app.buttons.matching(identifier: "book-\(epubTitle)").element(boundBy: 1)
        XCTAssertTrue(lastHomeBook.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(lastHomeBook.frame.maxY, homeTab.frame.minY)
        XCTAssertLessThanOrEqual(app.frame.maxY - homeTab.frame.maxY, 45)
        captureDetails("Home Bottom Clearance", in: app)
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
            app.buttons["Done"].tap()
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
        XCTAssertTrue(app.staticTexts["Series"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Island Stories · Book 2.5")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Coastal Tales")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Fiction"].exists)
        XCTAssertTrue(app.staticTexts["Sea stories"].exists)
        XCTAssertTrue(app.staticTexts["Languages"].exists)
        captureDetails("EPUB Metadata", in: app)
        app.scrollViews.firstMatch.swipeDown()
        app.buttons["Read Book"].tap()
        waitForProgress(in: app, matching: "Location 1 of .*")
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
            app.buttons["Done"].tap()
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
        for heading in ["Description", "Series", "Subjects", "Language", "Languages"] {
            XCTAssertFalse(app.staticTexts[heading].exists)
        }
        captureDetails("PDF Book Details", in: app)
        app.buttons["Read Book"].tap()
        waitForProgress(in: app, matching: "Page 1 of 6 · 0%")
        showToolbar(in: app)
        app.buttons["Book Details"].tap()
        XCTAssertTrue(app.navigationBars["Book Details"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(progress(in: app).exists)
    }

    private func captureDetails(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
        XCTAssertFalse(book(epubTitle, in: app).label.contains("New"), "The library shows progress after reading")

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
        turnPage(in: app)
        waitForProgress(in: app, matching: "Page 2 of 6 · \\d+%")
        // Turning the page hides the toolbar; a tap in the middle brings it back.
        XCTAssertTrue(app.navigationBars[pdfTitle].waitForNonExistence(timeout: 5))
        app.otherElements["reader-content"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars[pdfTitle].waitForExistence(timeout: 5))
        app.otherElements["reader-content"].coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap()
        waitForProgress(in: app, matching: "Page 1 of 6 · 0%")
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
        let bar = app.navigationBars[epubTitle]
        XCTAssertFalse(bar.exists)
        app.otherElements["reader-content"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        app.otherElements["reader-content"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(bar.waitForNonExistence(timeout: 5))
    }
}
