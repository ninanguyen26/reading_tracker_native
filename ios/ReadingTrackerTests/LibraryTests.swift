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
        importer = BookImporter(database: database, storage: storage)
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

    func testImportsEpubWithMetadataAndCover() async throws {
        let book = try await importer.importBook(from: fixture("sample", "epub"))
        XCTAssertEqual(book.title, "The Lighthouse Keeper")
        XCTAssertEqual(book.author, "Avery Quinn")
        XCTAssertEqual(book.format, .epub)
        XCTAssertGreaterThan(book.size, 0)
        XCTAssertEqual(book.progression, 0)
        XCTAssertNotNil(book.coverFileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.url(for: book.fileName).path))
        XCTAssertNotNil(UIImage(contentsOfFile: storage.url(for: book.coverFileName!).path))
        let saved = try await database.allBooks()
        XCTAssertEqual(saved.map(\.id), [book.id])
        // SQLite keeps dates to the millisecond.
        XCTAssertEqual(saved[0].addedAt.timeIntervalSince1970, book.addedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testImportsPdfWithFirstPageAsCover() async throws {
        let book = try await importer.importBook(from: fixture("sample", "pdf"))
        XCTAssertEqual(book.title, "Field Notes")
        XCTAssertEqual(book.author, "Jordan Lee")
        XCTAssertEqual(book.format, .pdf)
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
