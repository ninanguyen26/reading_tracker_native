import ReadiumShared
import GRDB
import XCTest
@testable import ReadingTracker

@MainActor
final class LibraryTests: XCTestCase {
    private var database: AppDatabase!
    private var storage: BookStorage!
    private var importer: BookImporter!

    override func setUp() async throws {
        database = try AppDatabase.inMemory()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        storage = BookStorage(directory: folder)
        importer = BookImporter(database: database, storage: storage, openLibrary: nil, classifier: nil)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: storage.directory)
    }

    private func fixture(_ name: String, _ ext: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: ext), "Missing fixture \(name).\(ext)")
    }

    private func filesInStorage() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: storage.directory.path).sorted()
    }

    // MARK: Import

    func testBookDetailsDescriptionDisplaysTextWithoutMarkup() {
        let text = BookDetailsText.description("<p>A journey &amp; a discovery.</p><p>Second paragraph.</p><img src='https://example.org/cover.jpg'><script>hidden()</script>")
        XCTAssertTrue(text?.contains("A journey & a discovery.") == true)
        XCTAssertTrue(text?.contains("Second paragraph.") == true)
        XCTAssertFalse(text?.contains("<") == true)
        XCTAssertFalse(text?.contains("hidden()") == true)
        XCTAssertNil(BookDetailsText.description("<p>  </p>"))
        XCTAssertNil(BookDetailsText.description(nil))
    }

    func testImportsEpubWithMetadataAndCover() async throws {
        let book = try await importer.importBook(from: fixture("sample", "epub"))
        XCTAssertEqual(book.title, "The Lighthouse Keeper")
        XCTAssertEqual(book.author, "Avery Quinn")
        XCTAssertEqual(book.format, .epub)
        XCTAssertEqual(book.description, "A keeper watches over an isolated island.")
        XCTAssertEqual(book.series, [
            BookSeries(name: "Island Stories", position: 2.5),
            BookSeries(name: "Coastal Tales", position: nil)
        ])
        XCTAssertEqual(book.subjects, ["Fiction", "Sea stories"])
        XCTAssertEqual(book.languages, ["en", "vi"])
        XCTAssertGreaterThan(book.size, 0)
        XCTAssertEqual(book.progression, 0)
        XCTAssertNotNil(book.coverFileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.url(for: book.fileName).path))
        XCTAssertNotNil(UIImage(contentsOfFile: storage.url(for: book.coverFileName!).path))
        let saved = try await database.allBooks()
        XCTAssertEqual(saved.map(\.id), [book.id])
        XCTAssertEqual(saved[0].description, book.description)
        XCTAssertEqual(saved[0].series, book.series)
        XCTAssertEqual(saved[0].subjects, book.subjects)
        XCTAssertEqual(saved[0].languages, book.languages)
        // SQLite keeps dates to the millisecond.
        XCTAssertEqual(saved[0].addedAt.timeIntervalSince1970, book.addedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testImportsPdfWithFirstPageAsCover() async throws {
        let book = try await importer.importBook(from: fixture("sample", "pdf"))
        XCTAssertEqual(book.title, "Field Notes")
        XCTAssertEqual(book.author, "Jordan Lee")
        XCTAssertEqual(book.format, .pdf)
        XCTAssertNil(book.description)
        XCTAssertTrue(book.series.isEmpty)
        XCTAssertTrue(book.subjects.isEmpty)
        XCTAssertTrue(book.languages.isEmpty)
        let cover = try XCTUnwrap(UIImage(contentsOfFile: storage.url(for: XCTUnwrap(book.coverFileName)).path))
        // US Letter proportions, from rendering page 1.
        XCTAssertEqual(cover.size.height / cover.size.width, 792.0 / 612.0, accuracy: 0.02)
    }

    func testRejectsFilesThatAreNotBooks() async throws {
        let text = FileManager.default.temporaryDirectory.appendingPathComponent("notes.txt")
        try "hello".write(to: text, atomically: true, encoding: .utf8)
        do {
            try await importer.importBook(from: text)
            XCTFail("Expected an error")
        } catch let error as ImportError {
            XCTAssertEqual(error, .unsupportedFile("notes.txt"))
        }
        XCTAssertEqual(try filesInStorage(), [])
        let saved = try await database.allBooks()
        XCTAssertTrue(saved.isEmpty)
    }

    func testImportsPDFXMPMetadataAndStoresIt() async throws {
        let source = try metadataPDF(xmp: """
            <x:xmpmeta xmlns:x="adobe:ns:meta/">
            <r:RDF xmlns:r="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <r:Description xmlns:d="http://purl.org/dc/elements/1.1/"
                xmlns:c="http://calibre-ebook.com/xmp-namespace"
                xmlns:s="http://calibre-ebook.com/xmp-namespace-series-index">
                <d:description><r:Alt>
                    <r:li xml:lang="vi">Other translation</r:li>
                    <r:li xml:lang="x-default">  A journey &amp; a discovery.  </r:li>
                </r:Alt></d:description>
                <d:subject><r:Bag><r:li>Travel</r:li><r:li>  Islands </r:li><r:li>travel</r:li><r:li> </r:li></r:Bag></d:subject>
                <d:language><r:Bag><r:li>en-GB</r:li><r:li>vi</r:li></r:Bag></d:language>
                <c:series><r:Description><r:value>Island Stories</r:value><s:series_index>2.5</s:series_index></r:Description></c:series>
                <c:series><r:Description><r:value>Coastal Tales</r:value><s:series_index>NaN</s:series_index></r:Description></c:series>
            </r:Description></r:RDF></x:xmpmeta>
            """, info: "/Subject (Older description) /Keywords (Old topic)", language: "fr")
        defer { try? FileManager.default.removeItem(at: source) }
        let book = try await importer.importBook(from: source)
        XCTAssertEqual(book.description, "A journey & a discovery.")
        XCTAssertEqual(book.series, [BookSeries(name: "Island Stories", position: 2.5), BookSeries(name: "Coastal Tales", position: nil)])
        XCTAssertEqual(book.subjects, ["Travel", "Islands"])
        XCTAssertEqual(book.languages, ["en-GB", "vi"])
        XCTAssertNotNil(book.coverFileName)
        let fetched = try await database.book(id: book.id)
        let saved = try XCTUnwrap(fetched)
        XCTAssertEqual(saved.description, book.description)
        XCTAssertEqual(saved.series, book.series)
        XCTAssertEqual(saved.subjects, book.subjects)
        XCTAssertEqual(saved.languages, book.languages)
    }

    func testImportsPDFDocumentPropertiesWithoutXMP() async throws {
        let source = try metadataPDF(info: "/Subject (  Notes about coastal life.  ) /Keywords (Travel; Islands, travel)", language: "vi")
        defer { try? FileManager.default.removeItem(at: source) }
        let book = try await importer.importBook(from: source)
        XCTAssertEqual(book.description, "Notes about coastal life.")
        XCTAssertEqual(book.subjects, ["Travel", "Islands"])
        XCTAssertEqual(book.languages, ["vi"])
        XCTAssertTrue(book.series.isEmpty)
    }

    func testMalformedPDFXMPFallsBackToDocumentProperties() async throws {
        let source = try metadataPDF(xmp: "<broken><description>Partial value", info: "/Subject (Fallback description) /Keywords (History)", language: "en")
        defer { try? FileManager.default.removeItem(at: source) }
        let book = try await importer.importBook(from: source)
        XCTAssertEqual(book.description, "Fallback description")
        XCTAssertEqual(book.subjects, ["History"])
        XCTAssertEqual(book.languages, ["en"])
    }

    func testPDFCompactXMPAndUnknownNamespaces() async throws {
        let source = try metadataPDF(xmp: """
            <r:RDF xmlns:r="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <r:Description xmlns:d="http://purl.org/dc/elements/1.1/"
                xmlns:p="http://ns.adobe.com/pdf/1.3/"
                xmlns:other="https://example.org/unrelated/"
                d:description="Short description" d:language="en" p:Keywords="Fiction; Sea stories">
                <other:series>Not a recognized series field</other:series>
                <other:subject>Not a subject</other:subject>
            </r:Description></r:RDF>
            """)
        defer { try? FileManager.default.removeItem(at: source) }
        let book = try await importer.importBook(from: source)
        XCTAssertEqual(book.description, "Short description")
        XCTAssertEqual(book.subjects, ["Fiction", "Sea stories"])
        XCTAssertEqual(book.languages, ["en"])
        XCTAssertTrue(book.series.isEmpty)
    }

    /// A real, minimal PDF with optional Info, catalog language, and XMP stream.
    private func metadataPDF(xmp: String? = nil, info: String = "", language: String? = nil) throws -> URL {
        let languageEntry = language.map { "/Lang (\($0))" } ?? ""
        var objects = [
            "<< /Type /Catalog /Pages 2 0 R \(languageEntry) \(xmp == nil ? "" : "/Metadata 5 0 R") >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>",
            "<< /Title (Metadata Test) /Author (Test Author) \(info) >>"
        ]
        if let xmp {
            objects.append("<< /Type /Metadata /Subtype /XML /Length \(xmp.utf8.count) >>\nstream\n\(xmp)\nendstream")
        }
        var data = Data("%PDF-1.7\n".utf8)
        var offsets = [Int]()
        for (index, object) in objects.enumerated() {
            offsets.append(data.count)
            data.append(Data("\(index + 1) 0 obj\n\(object)\nendobj\n".utf8))
        }
        let xref = data.count
        data.append(Data("xref\n0 \(objects.count + 1)\n0000000000 65535 f \n".utf8))
        for offset in offsets { data.append(Data(String(format: "%010d 00000 n \n", offset).utf8)) }
        data.append(Data("trailer\n<< /Size \(objects.count + 1) /Root 1 0 R /Info 4 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        try data.write(to: url)
        return url
    }

    func testCleansUpWhenABookCannotBeOpened() async throws {
        // Looks like an EPUB (zip signature) but isn't one.
        let broken = FileManager.default.temporaryDirectory.appendingPathComponent("broken.epub")
        try Data([0x50, 0x4B, 0x03, 0x04, 0x00, 0x01]).write(to: broken)
        do {
            try await importer.importBook(from: broken)
            XCTFail("Expected an error")
        } catch {}
        XCTAssertEqual(try filesInStorage(), [])
    }

    func testDeleteRemovesTheBookAndItsFiles() async throws {
        let book = try await importer.importBook(from: fixture("sample", "epub"))
        try await importer.delete(book)
        let saved = try await database.allBooks()
        XCTAssertTrue(saved.isEmpty)
        XCTAssertEqual(try filesInStorage(), [])
    }

    // MARK: Progress

    func testImportsEpubWithoutOptionalMetadata() async throws {
        // This fixture has only title, author and language.
        let source = try fixture("minimal", "epub")
        let book = try await importer.importBook(from: source)
        XCTAssertNil(book.description)
        XCTAssertTrue(book.series.isEmpty)
        XCTAssertTrue(book.subjects.isEmpty)
        XCTAssertEqual(book.languages, ["en"])
        let fetched = try await database.book(id: book.id)
        let saved = try XCTUnwrap(fetched)
        XCTAssertEqual(saved.series, [])
        XCTAssertEqual(saved.subjects, [])
    }

    func testMetadataMigrationPreservesExistingBooksAndProgress() async throws {
        let queue = try DatabaseQueue()
        try await queue.write { db in
            // Simulate an existing v1 library before the new columns existed.
            try db.execute(sql: """
                CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY);
                INSERT INTO grdb_migrations VALUES ('v1');
                CREATE TABLE book (
                    id TEXT PRIMARY KEY, title TEXT NOT NULL, author TEXT NOT NULL,
                    format TEXT NOT NULL, fileName TEXT NOT NULL, coverFileName TEXT,
                    size INTEGER NOT NULL, addedAt DATETIME NOT NULL,
                    lastOpenedAt DATETIME, locator TEXT, progression DOUBLE NOT NULL DEFAULT 0
                );
                INSERT INTO book VALUES (
                    'legacy', 'Existing Book', 'Author', 'epub', 'legacy.epub', NULL,
                    100, '2026-01-01 00:00:00', NULL, '{"href":"chapter.xhtml"}', 0.42
                );
                """)
        }
        let migrated = try AppDatabase(queue)
        let fetched = try await migrated.book(id: "legacy")
        let book = try XCTUnwrap(fetched)
        XCTAssertEqual(book.title, "Existing Book")
        XCTAssertEqual(book.progression, 0.42)
        XCTAssertEqual(book.locator, #"{"href":"chapter.xhtml"}"#)
        XCTAssertNil(book.description)
        XCTAssertEqual(book.series, [])
        XCTAssertEqual(book.subjects, [])
        XCTAssertEqual(book.languages, [])
    }

    func testSavesProgressAndLastOpened() async throws {
        let book = try await importer.importBook(from: fixture("sample", "pdf"))
        try await database.saveProgress(id: book.id, locator: #"{"href":"x"}"#, progression: 1.4)
        try await database.markOpened(id: book.id, at: Date(timeIntervalSince1970: 100))
        let fetched = try await database.book(id: book.id)
        let saved = try XCTUnwrap(fetched)
        XCTAssertEqual(saved.locator, #"{"href":"x"}"#)
        XCTAssertEqual(saved.progression, 1) // clamped
        XCTAssertEqual(saved.lastOpenedAt, Date(timeIntervalSince1970: 100))
    }

    // MARK: Helpers

    func testDetectsFormatsFromContentBeforeExtension() throws {
        let dir = FileManager.default.temporaryDirectory
        let pdfNamedEpub = dir.appendingPathComponent("mislabeled.epub")
        try Data("%PDF-1.7".utf8).write(to: pdfNamedEpub)
        XCTAssertEqual(BookImporter.detectFormat(of: pdfNamedEpub), .pdf)
        let unknown = dir.appendingPathComponent("Book.EPUB")
        try Data("??".utf8).write(to: unknown)
        XCTAssertEqual(BookImporter.detectFormat(of: unknown), .epub)
        XCTAssertEqual(BookImporter.title(fromFileName: "my_great-book.epub"), "my great book")
        XCTAssertEqual(BookImporter.title(fromFileName: ".pdf"), "Untitled")
    }

    func testBookmarksAreOrderedAndDeletedWithTheirBook() async throws {
        let book = try await importer.importBook(from: fixture("sample", "epub"))
        for (id, progression) in [("late", 0.8), ("early", 0.2)] {
            try await database.addBookmark(Bookmark(id: id, bookId: book.id, locator: "{}", progression: progression, title: nil, createdAt: Date()))
        }
        var iterator = database.observeBookmarks(bookId: book.id).makeAsyncIterator()
        let ordered = try await iterator.next()
        XCTAssertEqual(ordered?.map(\.id), ["early", "late"])

        try await importer.delete(book)
        let count = try await database.writer.read { try Bookmark.fetchCount($0) }
        XCTAssertEqual(count, 0)
    }

    func testBookmarkMatchesThePageItWasMadeOn() throws {
        func locator(_ href: String, progression: Double?, position: Int? = nil) throws -> Locator {
            try XCTUnwrap(Locator(jsonString: #"{"href":"\#(href)","type":"text/html","locations":{\#(progression.map { "\"progression\":\($0)," } ?? "")"position":\#(position ?? 1)}}"#))
        }
        XCTAssertTrue(ReaderModel.isSamePlace(try locator("ch1.xhtml", progression: 0.25), try locator("ch1.xhtml", progression: 0.2504)))
        XCTAssertFalse(ReaderModel.isSamePlace(try locator("ch1.xhtml", progression: 0.25), try locator("ch1.xhtml", progression: 0.3)))
        XCTAssertFalse(ReaderModel.isSamePlace(try locator("ch1.xhtml", progression: 0.25), try locator("ch2.xhtml", progression: 0.25)))
        XCTAssertTrue(ReaderModel.isSamePlace(try locator("doc.pdf", progression: nil, position: 3), try locator("doc.pdf", progression: nil, position: 3)))
    }

    func testTapZones() {
        XCTAssertEqual(ReaderHostViewController.zone(for: 10, width: 400), .left)
        XCTAssertEqual(ReaderHostViewController.zone(for: 200, width: 400), .middle)
        XCTAssertEqual(ReaderHostViewController.zone(for: 390, width: 400), .right)
        // On narrow screens the edges stay at least 80pt wide.
        XCTAssertEqual(ReaderHostViewController.zone(for: 75, width: 200), .left)
    }

    func testSortsAndSearches() {
        func book(_ title: String, _ author: String, added: TimeInterval, opened: TimeInterval?) -> Book {
            Book(id: title, title: title, author: author, format: .epub, fileName: "", coverFileName: nil, size: 0,
                 addedAt: Date(timeIntervalSince1970: added), lastOpenedAt: opened.map(Date.init(timeIntervalSince1970:)),
                 locator: nil, progression: 0)
        }
        let books = [
            book("beta", "Zed", added: 1, opened: 50),
            book("Alpha", "Amy", added: 3, opened: nil),
            book("gamma", "Amy", added: 2, opened: 10),
        ]
        XCTAssertEqual(books.sorted(by: .title).map(\.title), ["Alpha", "beta", "gamma"])
        XCTAssertEqual(books.sorted(by: .author).map(\.title), ["Alpha", "gamma", "beta"])
        XCTAssertEqual(books.sorted(by: .recent).map(\.title), ["beta", "gamma", "Alpha"])
        XCTAssertEqual(books.sorted(by: .added).map(\.title), ["Alpha", "gamma", "beta"])
        XCTAssertEqual(books.matching("amy").map(\.title), ["Alpha", "gamma"])
        XCTAssertEqual(books.matching("  BET ").map(\.title), ["beta"])
    }
}
