import XCTest
@testable import ReadingTracker

@MainActor
final class HighlightTests: XCTestCase {
    private var database: AppDatabase!
    private var importer: BookImporter!
    private var storage: BookStorage!

    override func setUp() async throws {
        database = try AppDatabase.inMemory()
        storage = BookStorage(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        importer = BookImporter(database: database, storage: storage)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: storage.directory)
    }

    private func highlight(_ id: String, bookId: String, progression: Double, text: String = "text",
                           chapter: String? = nil, note: String = "", rects: [Highlight.PageRect] = []) -> Highlight {
        Highlight(id: id, bookId: bookId, locator: "{}", text: text, color: .yellow, note: note,
                  progression: progression, chapter: chapter, pdfRects: Highlight.encode(rects),
                  createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0))
    }

    private func importSample() async throws -> Book {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "sample", withExtension: "epub"))
        return try await importer.importBook(from: url)
    }

    func testStoresUpdatesAndOrdersHighlights() async throws {
        let book = try await importSample()
        try await database.addHighlight(highlight("late", bookId: book.id, progression: 0.9))
        try await database.addHighlight(highlight("early", bookId: book.id, progression: 0.1))
        try await database.updateHighlight(id: "early", color: .pink, note: "remember")

        var iterator = database.observeHighlights(bookId: book.id).makeAsyncIterator()
        let first = try await iterator.next()
        let saved = try XCTUnwrap(first)
        XCTAssertEqual(saved.map(\.id), ["early", "late"])
        XCTAssertEqual(saved[0].color, .pink)
        XCTAssertEqual(saved[0].note, "remember")
        XCTAssertGreaterThan(saved[0].updatedAt, saved[0].createdAt)

        try await database.deleteHighlight(id: "late")
        let remaining = try await database.writer.read { try Highlight.fetchCount($0) }
        XCTAssertEqual(remaining, 1)
    }

    func testHighlightsAreDeletedWithTheirBook() async throws {
        let book = try await importSample()
        try await database.addHighlight(highlight("h", bookId: book.id, progression: 0.5))
        try await importer.delete(book)
        let count = try await database.writer.read { try Highlight.fetchCount($0) }
        XCTAssertEqual(count, 0)
    }

    func testPDFRectsRoundTrip() {
        let rects = [Highlight.PageRect(page: 2, x: 10, y: 20, width: 100, height: 12)]
        let h = highlight("p", bookId: "b", progression: 0, rects: rects)
        XCTAssertEqual(h.pageRects, rects)
        XCTAssertNil(Highlight.encode([]))
        XCTAssertEqual(highlight("e", bookId: "b", progression: 0).pageRects, [])
    }

    func testExportsMarkdownGroupedByChapter() {
        let markdown = NotesExport.markdown(
            for: .init(title: "The Book", author: "Ann"),
            highlights: [
                highlight("3", bookId: "b", progression: 0.8, text: "Third", chapter: "Two"),
                highlight("1", bookId: "b", progression: 0.1, text: "First", chapter: "One", note: "Nice line"),
                highlight("2", bookId: "b", progression: 0.2, text: "Second\nline two", chapter: "One"),
            ]
        )
        XCTAssertEqual(markdown, [
            "# The Book", "", "*Ann*", "",
            "## One", "",
            "> First", "", "**Note:** Nice line", "",
            "> Second", "> line two", "",
            "## Two", "",
            "> Third", "",
        ].joined(separator: "\n"))
        XCTAssertTrue(NotesExport.markdown(for: .init(title: "T", author: "A"), highlights: []).contains("No highlights yet."))
        XCTAssertEqual(NotesExport.fileName(for: #"What? A/B: "Story""#), "What AB Story - notes.md")
    }
}
