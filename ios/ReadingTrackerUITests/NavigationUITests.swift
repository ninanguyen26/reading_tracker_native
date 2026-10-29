import XCTest

final class NavigationUITests: XCTestCase {
    private let epubTitle = "The Lighthouse Keeper"
    private let pdfTitle = "Field Notes"

    override func setUp() { continueAfterFailure = false }

    private func open(_ title: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-library", "-import-samples"]
        app.launch()
        let book = app.descendants(matching: .any)["book-\(title)"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 15))
        book.tap()
        XCTAssertTrue(app.staticTexts["reader-progress"].waitForExistence(timeout: 15))
        return app
    }

    private func showToolbar(_ app: XCUIApplication) {
        guard !app.buttons["Contents and Bookmarks"].isHittable else { return }
        app.otherElements["reader-content"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Contents and Bookmarks"].waitForExistence(timeout: 5))
    }

    private func waitFor(_ element: XCUIElement, label pattern: String, timeout: TimeInterval = 10) {
        let predicate = NSPredicate(format: "label MATCHES %@", pattern)
        wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: timeout)
    }

    private func openContents(_ app: XCUIApplication, tab: String) {
        showToolbar(app)
        app.buttons["Contents and Bookmarks"].tap()
        app.segmentedControls.buttons[tab].tap()
    }

    /// The chapter title shown in the footer.
    private func chapter(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.staticTexts[title].firstMatch
    }

    func testJumpsToAChapterFromTheContents() {
        let app = open(epubTitle)
        openContents(app, tab: "Contents")
        XCTAssertTrue(app.buttons["Chapter 1: The Tower"].isSelected, "The current chapter is marked")
        app.buttons["Chapter 3: The Letter"].tap()
        XCTAssertTrue(chapter(app, "Chapter 3: The Letter").waitForExistence(timeout: 10))
    }

    func testAddsUsesAndRemovesBookmarks() {
        let app = open(epubTitle)
        openContents(app, tab: "Contents")
        app.buttons["Chapter 2: The Fog"].tap()
        XCTAssertTrue(chapter(app, "Chapter 2: The Fog").waitForExistence(timeout: 10))

        showToolbar(app)
        app.buttons["Add Bookmark"].tap()
        XCTAssertTrue(app.buttons["Remove Bookmark"].waitForExistence(timeout: 5))

        // Go somewhere else, then back via the bookmark.
        app.buttons["Contents and Bookmarks"].tap()
        app.segmentedControls.buttons["Contents"].tap()
        app.buttons["Chapter 3: The Letter"].tap()
        XCTAssertTrue(chapter(app, "Chapter 3: The Letter").waitForExistence(timeout: 10))
        showToolbar(app)
        XCTAssertTrue(app.buttons["Add Bookmark"].exists, "No bookmark on this page")

        openContents(app, tab: "Bookmarks")
        let saved = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Chapter 2: The Fog'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()
        XCTAssertTrue(chapter(app, "Chapter 2: The Fog").waitForExistence(timeout: 10))
        showToolbar(app)
        XCTAssertTrue(app.buttons["Remove Bookmark"].waitForExistence(timeout: 5))

        // Remove it by swiping in the list.
        openContents(app, tab: "Bookmarks")
        saved.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'No bookmarks yet'")).firstMatch.waitForExistence(timeout: 5))
    }

    func testPdfOutlineAndSlider() {
        let app = open(pdfTitle)
        let progress = app.staticTexts["reader-progress"]
        waitFor(progress, label: "Page 1 of 6 · 0%")

        openContents(app, tab: "Contents")
        app.buttons["Notes"].tap()
        waitFor(progress, label: "Page 5 of 6 · \\d+%")

        showToolbar(app)
        app.sliders["position-slider"].adjust(toNormalizedSliderPosition: 0)
        waitFor(app.staticTexts["reader-progress"], label: "Page 1 of 6 · 0%")
    }
}
