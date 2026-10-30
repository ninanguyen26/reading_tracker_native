import Foundation
import XCTest
@testable import ReadingTracker

@MainActor
final class OpenLibraryTests: XCTestCase {
    private func record(_ json: String) throws -> OpenLibraryRecord {
        try JSONDecoder().decode(OpenLibraryRecord.self, from: Data(json.utf8))
    }

    private func book() -> Book {
        Book(id: "local", title: "Local Title", author: "Local Author", format: .pdf,
             fileName: "local.pdf", coverFileName: "cover.jpg", size: 123, addedAt: Date(), progression: 0)
    }

    func testISBNNormalizationAndChecksum() {
        XCTAssertEqual(OpenLibraryISBN.normalize("urn:isbn:978-0-14-032872-1"), "9780140328721")
        XCTAssertEqual(OpenLibraryISBN.normalize("0-8044-2957-X"), "080442957X")
        XCTAssertNil(OpenLibraryISBN.normalize("9780140328722"))
        XCTAssertNil(OpenLibraryISBN.normalize("https://example.org/9780140328721"))
        XCTAssertNil(OpenLibraryISBN.normalize("1234567890"))
    }

    func testDescriptionRejectsSingleWordsAndFormatPlaceholders() {
        for value in ["Hardcover", "<p>Hardcover.</p>", "Paperback", "Hard cover", "Mass-market paperback",
                      "Kindle Edition", "No description available", "Fiction", "&nbsp;"] {
            XCTAssertNil(BookDetailsText.description(value), value)
        }
        XCTAssertEqual(BookDetailsText.description("A journey."), "A journey.")
        XCTAssertEqual(BookDetailsText.description("<p>A keeper watches over an isolated island.</p>"),
                       "A keeper watches over an isolated island.")
        XCTAssertNotNil(BookDetailsText.description("这是一本关于友谊与冒险的小说。"))
    }

    func testPlaceholderEditionFallsBackToSynopsisAndKeepsSingleWordSubjects() throws {
        let work = try record(#"{"key":"/works/OL1W","description":"A keeper watches over an isolated island.","subjects":["Fiction"]}"#)
        let edition = try record(#"{"key":"/books/OL1M","description":"Hardcover"}"#)
        let metadata = OpenLibraryMetadata(work: work, edition: edition)
        var local = book()
        local.description = "Hardcover"
        let updated = metadata.filling(local, fields: [.description, .subjects])
        XCTAssertEqual(updated.description, work.description)
        XCTAssertEqual(updated.openLibraryFields["description"], work.key)
        XCTAssertEqual(updated.subjects, ["Fiction"])
    }

    func testPreviouslyStoredPlaceholderCanBeReplacedWithoutChangingProgress() async throws {
        let database = try AppDatabase.inMemory()
        var local = book()
        local.description = "Hardcover"
        local.progression = 0.7
        try await database.insert(local)
        let metadata = OpenLibraryMetadata(work: try record(#"{"key":"/works/OL1W","description":"A family discovers a long forgotten secret."}"#), edition: nil)
        _ = try await database.enrichBook(id: local.id, metadata: metadata, fields: [.description])
        let saved = try await database.book(id: local.id)
        XCTAssertEqual(saved?.description, metadata.description)
        XCTAssertEqual(saved?.progression, 0.7)
        XCTAssertEqual(saved?.coverFileName, local.coverFileName)
    }

    func testSearchEncodingAndISBNPriority() {
        let titleURL = OpenLibraryClient.searchURL(title: "A & B?", author: "C/D", isbn: "")
        let items = URLComponents(url: titleURL, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "title" }?.value, "A & B?")
        XCTAssertEqual(items.first { $0.name == "author" }?.value, "C/D")
        let isbnURL = OpenLibraryClient.searchURL(title: "Ignored", author: "Ignored", isbn: "9780140328721")
        XCTAssertTrue(isbnURL.absoluteString.contains("isbn=9780140328721"))
        XCTAssertFalse(isbnURL.absoluteString.contains("Ignored"))
        XCTAssertFalse(OpenLibraryClient.validKey("//evil.org/works/OL1W", kind: "works", suffix: "W"))
    }

    func testVariableCatalogShapesAndEditionLanguages() throws {
        let work = try record(#"{"key":"/works/OL1W","description":{"value":"<p>Work &amp; story.</p>"},"subjects":["Fiction"],"series":"A Series","languages":[{"key":"/languages/fre"}]}"#)
        let edition = try record(#"{"key":"/books/OL1M","description":"Edition text","languages":[{"key":"/languages/eng"}],"series":["Edition Series"]}"#)
        let general = OpenLibraryMetadata(work: work, edition: nil)
        XCTAssertEqual(general.description, "Work & story.")
        XCTAssertEqual(general.languages, [])
        let specific = OpenLibraryMetadata(work: work, edition: edition)
        XCTAssertEqual(specific.description, "Edition text")
        XCTAssertEqual(specific.languages, ["eng"])
        XCTAssertEqual(specific.subjects, ["Fiction"])
        XCTAssertEqual(specific.series.first?.name, "Edition Series")
    }

    func testSelectedFieldsFillOnlyEmptyValuesAndPreserveLocalData() throws {
        let work = try record(#"{"key":"/works/OL1W","description":"Remote","subjects":["Fiction"],"series":["Remote Series"]}"#)
        let metadata = OpenLibraryMetadata(work: work, edition: nil)
        var original = book()
        original.description = "Embedded description"
        original.progression = 0.75
        let updated = metadata.filling(original, fields: [.description, .subjects])
        XCTAssertEqual(updated.description, "Embedded description")
        XCTAssertEqual(updated.subjects, ["Fiction"])
        XCTAssertEqual(updated.series, [])
        XCTAssertEqual(updated.title, original.title)
        XCTAssertEqual(updated.author, original.author)
        XCTAssertEqual(updated.coverFileName, original.coverFileName)
        XCTAssertEqual(updated.progression, original.progression)
        XCTAssertEqual(updated.openLibraryFields, ["subjects": "/works/OL1W"])
    }

    func testPersistenceRereadsLatestProgressAndDoesNotOverwriteEnrichedFields() async throws {
        let database = try AppDatabase.inMemory()
        let original = book()
        try await database.insert(original)
        try await database.saveProgress(id: original.id, locator: "latest", progression: 0.6)
        let first = OpenLibraryMetadata(work: try record(#"{"key":"/works/OL1W","description":"First description","subjects":["First subject"]}"#), edition: nil)
        let saved = try await database.enrichBook(id: original.id, metadata: first, fields: [.description])
        XCTAssertEqual(saved.progression, 0.6)
        XCTAssertEqual(saved.locator, "latest")
        let second = OpenLibraryMetadata(work: try record(#"{"key":"/works/OL2W","description":"Replacement","subjects":["Second subject"]}"#), edition: nil)
        _ = try await database.enrichBook(id: original.id, metadata: second, fields: [.description, .subjects])
        let persisted = try await database.book(id: original.id)
        XCTAssertEqual(persisted?.description, "First description")
        XCTAssertEqual(persisted?.subjects, ["Second subject"])
        XCTAssertEqual(persisted?.openLibraryFields, ["description": "/works/OL1W", "subjects": "/works/OL2W"])
    }

    func testHTTPResponseCachingAndRateLimitError() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OpenLibraryTestProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let client = OpenLibraryClient(session: session)
        let results = try await client.search(title: "Cache", author: "", isbn: "")
        XCTAssertEqual(results.map(\.title), ["Test Book"])
        let cached = try await client.search(title: "Cache", author: "", isbn: "")
        XCTAssertEqual(cached.count, 1)
        do {
            _ = try await client.work("/works/OL429W")
            XCTFail("Expected rate limit error")
        } catch OpenLibraryError.rateLimited {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testFullClientLookupSequence() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OpenLibraryFixtureProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let client = OpenLibraryClient(session: session)
        let matches = try await client.search(title: "Field Notes", author: "", isbn: "")
        let work = try await client.work(try XCTUnwrap(matches.first?.key))
        let editions = try await client.editions(work.key, offset: 0)
        let metadata = OpenLibraryMetadata(work: work, edition: editions.first)
        XCTAssertEqual(metadata.description, "Observations from the natural world.")
        XCTAssertEqual(metadata.languages, ["eng"])
        let updated = metadata.filling(book(), fields: Set(OpenLibraryField.allCases))
        XCTAssertEqual(updated.openLibraryFields["description"], "/works/OL1W")
        XCTAssertEqual(updated.openLibraryFields["languages"], "/books/OL1M")
    }

    func testAutomaticImportAddsMetadataWithoutManualSave() async throws {
        let database = try AppDatabase.inMemory()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let metadata = OpenLibraryMetadata(work: try record(#"{"key":"/works/OL1W","description":"Automatic description","subjects":["Nature"],"series":["Field Journals"]}"#),
                                           edition: try record(#"{"key":"/books/OL1M","languages":[{"key":"/languages/eng"}]}"#))
        let lookup = ImportLookupStub(result: metadata)
        let importer = BookImporter(database: database, storage: BookStorage(directory: directory), openLibrary: lookup)
        let source = try XCTUnwrap(Bundle(for: LibraryTests.self).url(forResource: "sample", withExtension: "pdf"))
        let imported = try await importer.importBook(from: source)
        await importer.waitForMetadata(bookID: imported.id)
        let loaded = try await database.book(id: imported.id)
        let saved = try XCTUnwrap(loaded)
        XCTAssertEqual(saved.description, "Automatic description")
        XCTAssertEqual(saved.subjects, ["Nature"])
        XCTAssertEqual(saved.languages, ["eng"])
        XCTAssertEqual(saved.title, imported.title)
        XCTAssertEqual(saved.coverFileName, imported.coverFileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(saved.fileName).path))
        let calls = await lookup.calls
        XCTAssertEqual(calls, 1)
    }

    func testOfflineLookupDoesNotFailOrRemoveImportedBook() async throws {
        let database = try AppDatabase.inMemory()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let importer = BookImporter(database: database, storage: BookStorage(directory: directory),
                                    openLibrary: ImportLookupStub(result: nil, offline: true))
        let source = try XCTUnwrap(Bundle(for: LibraryTests.self).url(forResource: "sample", withExtension: "pdf"))
        let imported = try await importer.importBook(from: source)
        await importer.waitForMetadata(bookID: imported.id)
        let saved = try await database.book(id: imported.id)
        XCTAssertEqual(saved?.id, imported.id)
        XCTAssertEqual(saved?.fileName, imported.fileName)
        XCTAssertEqual(saved?.title, imported.title)
        XCTAssertEqual(saved?.coverFileName, imported.coverFileName)
        XCTAssertNil(saved?.description)
        XCTAssertEqual(saved?.openLibraryFields, [:])
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(imported.fileName).path))
    }

    func testAutomaticMatchingUsesISBNAndRejectsAmbiguousOrDifferentBooks() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AutomaticLookupTestProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let client = OpenLibraryClient(session: session)
        var local = book()
        local.isbn = "9780140328721"
        let exactEdition = try await client.metadata(for: local)
        XCTAssertEqual(exactEdition?.languages, ["eng"])
        local.isbn = nil
        local.title = "Field Notes"
        local.author = "Jordan Lee"
        let exactWork = try await client.metadata(for: local)
        XCTAssertNotNil(exactWork)
        XCTAssertEqual(exactWork?.languages, [])
        local.title = "Field Notes 2"
        let mismatch = try await client.metadata(for: local)
        XCTAssertNil(mismatch)
        local.title = "Shared"
        let ambiguous = try await client.metadata(for: local)
        XCTAssertNil(ambiguous)
    }
}

private actor ImportLookupStub: OpenLibraryEnriching {
    let result: OpenLibraryMetadata?
    var offline = false
    private(set) var calls = 0
    init(result: OpenLibraryMetadata?, offline: Bool = false) { self.result = result; self.offline = offline }
    func metadata(for book: Book) async throws -> OpenLibraryMetadata? {
        calls += 1
        if offline { throw URLError(.notConnectedToInternet) }
        return result
    }
}

private final class AutomaticLookupTestProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let json: String
        if request.url!.path.hasPrefix("/isbn/") {
            json = #"{"key":"/books/OL1M","works":[{"key":"/works/OL1W"}],"languages":[{"key":"/languages/eng"}]}"#
        } else if request.url!.path == "/search.json" {
            let title = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "title" }?.value
            json = title == "Shared"
                ? #"{"docs":[{"key":"/works/OL1W","title":"Shared","author_name":["Jordan Lee"]},{"key":"/works/OL2W","title":"Shared","author_name":["Jordan Lee"]}]}"#
                : #"{"docs":[{"key":"/works/OL1W","title":"Field Notes","author_name":["Jordan Lee"]}]}"#
        } else { json = #"{"key":"/works/OL1W","description":"Automatic description","subjects":["Nature"]}"# }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class OpenLibraryTestProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let limited = request.url!.path.contains("OL429W")
        let response = HTTPURLResponse(url: request.url!, statusCode: limited ? 429 : 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"docs":[{"key":"/works/OL1W","title":"Test Book"}]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
