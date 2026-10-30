import XCTest
@testable import ReadingTracker

@MainActor
final class BookPageCountTests: XCTestCase {
    func testPageMapsRejectSparseListsAndCountRomanFrontMatter() {
        XCTAssertEqual(BookPageCounter.paginationCount(["i", "ii", "1", "2", "3"]), 5)
        XCTAssertEqual(BookPageCounter.paginationCount(["Page 1", "Page 2"]), 2)
        XCTAssertNil(BookPageCounter.paginationCount(["1", "200"]))
        XCTAssertNil(BookPageCounter.paginationCount(["1", "2", "1"]))
        XCTAssertNil(BookPageCounter.paginationCount([]))
    }
    func testWordEstimatesRoundUpAndNeverInventPagesForEmptyText() {
        XCTAssertEqual(BookPageCounter.estimatedPages(words: 250), 1)
        XCTAssertEqual(BookPageCounter.estimatedPages(words: 251), 2)
        XCTAssertNil(BookPageCounter.estimatedPages(words: 0))
        XCTAssertEqual(BookPageCounter.wordCount("One two three."), 3)
    }
    func testRealPDFFilesAndEPUBPaginationOrFallback() async throws {
        let db = try AppDatabase.inMemory()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let importer = BookImporter(database: db, storage: BookStorage(directory: directory), openLibrary: nil, classifier: nil)
        for (file, ext, expectedSource, expectedCount) in [
            ("sample", "pdf", BookPageSource.pdf, 6),
            ("embedded-pages", "epub", .embedded, 3),
            ("page-markers", "epub", .embedded, 3),
            ("minimal", "epub", .estimated, 0)
        ] {
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: file, withExtension: ext))
            let book = try await importer.importBook(from: url)
            await importer.updatePageCount(for: book)
            let loaded = try await db.book(id: book.id)
            let saved = try XCTUnwrap(loaded)
            XCTAssertEqual(saved.pageCountSource, expectedSource, file)
            XCTAssertGreaterThan(saved.pageCount ?? 0, 0, file)
            if expectedCount > 0 { XCTAssertEqual(saved.pageCount, expectedCount, file) }
        }
    }
    func testCatalogPagesRequireExactEditionAndNeverOverrideEmbeddedOrPDF() throws {
        let work = try JSONDecoder().decode(OpenLibraryRecord.self, from: Data(#"{"key":"/works/OL1W","number_of_pages":999}"#.utf8))
        let edition = try JSONDecoder().decode(OpenLibraryRecord.self, from: Data(#"{"key":"/books/OL1M","number_of_pages":320}"#.utf8))
        var book = Book(id: "book", title: "Book", author: "Author", format: .epub, fileName: "book.epub", size: 1, addedAt: Date(), progression: 0)
        book.pageCount = 200
        book.pageCountSource = .estimated
        let uncertain = OpenLibraryMetadata(work: work, edition: edition)
        XCTAssertEqual(uncertain.filling(book, fields: []).pageCount, 200)
        let exact = OpenLibraryMetadata(work: work, edition: edition, exactEdition: true)
        let updated = exact.filling(book, fields: [])
        XCTAssertEqual(updated.pageCount, 320)
        XCTAssertEqual(updated.pageCountEditionKey, "/books/OL1M")
        book.pageCountSource = .embedded
        XCTAssertEqual(exact.filling(book, fields: []).pageCount, 200)
        book.format = .pdf
        book.pageCountSource = .pdf
        XCTAssertEqual(exact.filling(book, fields: []).pageCount, 200)
    }
    func testLateEstimateCannotOverwriteCatalogPagesOrProgress() async throws {
        let db = try AppDatabase.inMemory()
        let book = Book(id: "book", title: "Book", author: "Author", format: .epub, fileName: "book.epub", size: 1, addedAt: Date(), progression: 0)
        try await db.insert(book)
        try await db.savePageCount(id: book.id, measurement: .init(count: 320, source: .openLibrary, editionKey: "/books/OL1M"))
        try await db.saveProgress(id: book.id, locator: "latest", progression: 0.5)
        try await db.savePageCount(id: book.id, measurement: .init(count: 240, source: .estimated))
        let saved = try await db.book(id: book.id)
        XCTAssertEqual(saved?.pageCount, 320)
        XCTAssertEqual(saved?.pageCountSource, .openLibrary)
        XCTAssertEqual(saved?.progression, 0.5)
        XCTAssertEqual(saved?.locator, "latest")
    }
    func testTitleMatchCannotSupplyEditionPageCount() async throws {
        let client = OpenLibraryClient()
        let book = Book(id: "book", title: "Book", author: "Author", format: .epub, fileName: "book.epub", openLibraryWorkKey: "/works/OL1W", size: 1, addedAt: Date(), progression: 0)
        let count = try await client.exactEditionPages(for: book)
        XCTAssertNil(count)
    }

    func testExactISBNEndpointSuppliesCatalogPages() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PageEditionProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let client = OpenLibraryClient(session: session)
        let book = Book(id: "book", title: "Book", author: "Author", format: .epub, fileName: "book.epub",
                        isbn: "9780140328721", size: 1, addedAt: Date(), progression: 0)
        let count = try await client.exactEditionPages(for: book)
        XCTAssertEqual(count, BookPageCount(count: 320, source: .openLibrary, editionKey: "/books/OL1M"))
    }
}

private final class PageEditionProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let exact = request.url!.path == "/isbn/9780140328721.json"
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: exact ? 200 : 404,
            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"key":"/books/OL1M","number_of_pages":320}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
