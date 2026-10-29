import XCTest

final class ReaderUITests: XCTestCase {
    private let epubTitle = "The Lighthouse Keeper"
    private let pdfTitle = "Field Notes"

    override func setUp() {
        continueAfterFailure = false
    }

    /// Launches the app; `fresh` starts from an empty library with the two sample books added.
    private func launch(fresh: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = fresh ? ["-reset-library", "-import-samples"] : []
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
