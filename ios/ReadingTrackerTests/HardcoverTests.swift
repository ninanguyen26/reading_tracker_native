import Foundation
import XCTest
@testable import ReadingTracker

@MainActor
final class HardcoverTests: XCTestCase {
    private func book() -> Book {
        Book(id: UUID().uuidString, title: "Test Book", author: "Test Author", format: .epub,
             fileName: "test.epub", coverFileName: "cover.jpg", size: 20, addedAt: Date(), progression: 0.6)
    }
    private func client() -> HardcoverClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HardcoverProtocol.self]
        return HardcoverClient(session: URLSession(configuration: config), endpoint: URL(string: "https://metadata.test/v1/metadata")!)
    }
    private var fallback: HardcoverMetadata {
        HardcoverMetadata(bookID: 42, description: "A wizard journeys into an enchanted forest.",
            series: [BookSeries(name: "Wizard Series", position: 2.5)], genres: ["Fantasy"],
            pages: BookPageCount(count: 320, source: .hardcover,
                                 editionKey: "https://hardcover.app/books/42/editions/11"))
    }
    func testFillMissingFieldsAndPreserveLocalValuesAndProgress() {
        var original = book()
        original.description = "Hardcover"
        original.pageCount = 12
        original.pageCountSource = .estimated
        let filled = fallback.filling(original)
        XCTAssertEqual(filled.description, fallback.description)
        XCTAssertEqual(filled.series.first?.position, 2.5)
        XCTAssertEqual(filled.hardcoverGenres, ["Fantasy"])
        XCTAssertEqual(filled.pageCount, 320)
        XCTAssertEqual(filled.pageCountSource, .hardcover)
        XCTAssertEqual(filled.progression, 0.6)
        XCTAssertEqual(filled.coverFileName, original.coverFileName)
        original.description = "An embedded synopsis already exists."
        original.series = [BookSeries(name: "Local series", position: 1)]
        let preserved = fallback.filling(original)
        XCTAssertEqual(preserved.description, original.description)
        XCTAssertEqual(preserved.series, original.series)
        XCTAssertNil(preserved.hardcoverFields["description"])
        XCTAssertNil(preserved.hardcoverFields["series"])
    }
    func testPagePriorityAndPDFProtection() {
        for source in [BookPageSource.pdf, .embedded, .openLibrary] {
            var local = book()
            local.pageCount = 99
            local.pageCountSource = source
            XCTAssertEqual(fallback.filling(local).pageCount, 99)
        }
        var pdf = book()
        pdf.format = .pdf
        XCTAssertNil(fallback.filling(pdf).pageCount)
        var placeholder = fallback
        placeholder.description = "Hardcover"
        XCTAssertNil(placeholder.filling(book()).description)
    }
    func testExactISBNReturnsEditionPagesAndSeparateTagCategories() async throws {
        var local = book()
        local.isbn = "9780140328721"
        let metadata = try await client().metadata(for: local)
        XCTAssertEqual(metadata?.pages?.count, 320)
        XCTAssertEqual(metadata?.pages?.source, .hardcover)
        XCTAssertTrue(metadata?.pages?.editionKey?.hasSuffix("/editions/11") == true)
        XCTAssertEqual(metadata?.genres, ["Fantasy"])
        XCTAssertEqual(metadata?.moods, ["Dark", "Tense"])
        XCTAssertEqual(metadata?.contentWarnings, ["Blood"])
        XCTAssertEqual(metadata?.rating, 4.24)
        XCTAssertEqual(metadata?.ratingsCount, 1283)
        XCTAssertEqual(metadata?.series.first?.position, 2.5)
        XCTAssertEqual(metadata?.publicationYears?.release?.year, 1980)
        XCTAssertEqual(metadata?.publicationYears?.edition?.year, 2018)
    }
    func testTitleMatchNeverProvidesPageCountAndRejectsWrongAuthor() async throws {
        let service = client()
        let metadata = try await service.metadata(for: book())
        XCTAssertNotNil(metadata?.description)
        XCTAssertNil(metadata?.pages)
        XCTAssertEqual(metadata?.publicationYears?.release?.year, 1980)
        XCTAssertNil(metadata?.publicationYears?.edition)
        var mismatch = book()
        mismatch.author = "Another Author"
        let absent = try await service.metadata(for: mismatch)
        XCTAssertNil(absent)
    }
    func testHardcoverMoodLabelsNormalizeSavedArrayFragmentsAndRemoveDuplicates() {
        let rawMoods = ["Dark", "mysterious", #""Mysterious"]"#, #"["reflective""#, " "]
        let expected = ["Dark", "mysterious", "reflective"]
        XCTAssertEqual(BookDetailsText.hardcoverMoods(rawMoods), expected)

        var metadata = fallback
        metadata.moods = rawMoods
        XCTAssertEqual(metadata.filling(book()).hardcoverMoods, expected)
    }
    func testDuplicateEditionAndTitleMatchesStayUnclassified() async throws {
        var local = book()
        local.title = "Ambiguous"
        let result = try await client().metadata(for: local)
        XCTAssertNil(result)
        local.isbn = "080442957X"
        let editionResult = try await client().metadata(for: local)
        XCTAssertNil(editionResult)
    }
    func testGraphQLErrorsAndRateLimitAreFailures() async throws {
        for title in ["Error", "Rate Limited"] {
            var local = book()
            local.title = title
            do { _ = try await client().metadata(for: local); XCTFail("Must reject failed responses") }
            catch { XCTAssertTrue(error is HardcoverError) }
        }
    }
    func testMissingServiceConfigurationIsExplicit() async throws {
        let service = HardcoverClient(endpoint: nil)
        do { _ = try await service.metadata(for: book()); XCTFail("Must report missing service") }
        catch { guard case HardcoverError.notConfigured = error else { return XCTFail("Unexpected error") } }
    }
    func testWrongEditionISBNCannotSupplyPages() async throws {
        var local = book()
        local.title = "Wrong ISBN"
        local.isbn = "9780140328721"
        let metadata = try await client().metadata(for: local)
        XCTAssertNotNil(metadata)
        XCTAssertNil(metadata?.pages)
        XCTAssertNil(metadata?.publicationYears?.edition)
    }

    func testPublicationYearRefreshPrefersOriginalYearAndKeepsEmbeddedFallback() async throws {
        let database = try AppDatabase.inMemory()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let importer = BookImporter(database: database, storage: BookStorage(directory: directory),
                                    openLibrary: nil, hardcover: client())
        var local = book()
        local.embeddedEditionYear = 2020
        local.didReadEmbeddedEditionYear = true
        local.isbn = "9780140328721"
        XCTAssertNil(book().publicationYear)
        XCTAssertEqual(local.publicationYear?.label, "Edition Year")
        try await database.insert(local)
        await importer.updatePublicationYears(id: local.id)
        let loaded = try await database.book(id: local.id)
        var saved = try XCTUnwrap(loaded)
        XCTAssertEqual(saved.publicationYear?.label, "Release Year")
        XCTAssertEqual(saved.publicationYear?.year, 1980)
        saved.hardcoverPublicationYears?.release = nil
        XCTAssertEqual(saved.publicationYear?.year, 2020)
        saved.embeddedEditionYear = nil
        XCTAssertEqual(saved.publicationYear?.label, "Edition Year")
        XCTAssertEqual(saved.publicationYear?.year, 2018)
    }
    func testGenreEvidencePersistsAndManualCorrectionSurvives() async throws {
        let database = try AppDatabase.inMemory()
        let local = book()
        try await database.insert(local)
        let oldSignature = GenreInput(book: local).signature
        try await database.enrichHardcover(id: local.id, metadata: fallback)
        let loaded = try await database.book(id: local.id)
        let saved = try XCTUnwrap(loaded)
        XCTAssertEqual(saved.hardcoverGenres, ["Fantasy"])
        XCTAssertNotEqual(GenreInput(book: saved).signature, oldSignature)
        XCTAssertEqual(SubjectGenreMapping.classify(GenreInput(book: saved).subjects)?.genres, [.fantasy])
        _ = try await database.saveManualGenres(id: local.id, genres: [.romance])
        try await database.enrichHardcover(id: local.id, metadata: fallback)
        await BookGenreClassifier.shared.classifyBook(id: local.id, database: database)
        let corrected = try await database.book(id: local.id)
        XCTAssertEqual(corrected?.genres, [.romance])
        XCTAssertEqual(corrected?.genreSource, "manual")
        XCTAssertEqual(corrected?.progression, 0.6)
    }

    func testRetriesOnlyAutomaticallyUnclassifiedBooksAndKeepsAllRecognizedTags() async throws {
        let database = try AppDatabase.inMemory()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var metadata = fallback
        metadata.genres = ["Fiction", "Cyberterrorism", "Science Fiction", "Dystopian",
                           "Fantasy", "Suspense", "Technothrillers", "Adventure", "Sci-Fi", "Horror"]
        let hardcover = HardcoverImportStub(result: metadata)
        let importer = BookImporter(database: database, storage: BookStorage(directory: directory),
                                    openLibrary: nil, hardcover: hardcover)
        let missingTags = book()
        var savedTags = book()
        savedTags.hardcoverGenres = metadata.genres
        // Hardcover tags must remain available even when many embedded subjects precede them.
        savedTags.subjects = (0..<50).map { "Subject \($0)" }
        let manual = book()
        let manualUnclassified = book()
        var alreadyClassified = book()
        alreadyClassified.genres = [.mystery]
        alreadyClassified.genreSource = "subjects"
        for book in [missingTags, savedTags, manual, manualUnclassified, alreadyClassified] {
            try await database.insert(book)
        }
        _ = try await database.saveManualGenres(id: manual.id, genres: [.romance])
        _ = try await database.saveManualGenres(id: manualUnclassified.id, genres: [])

        let completed = try await importer.retryUnclassifiedGenres()
        XCTAssertTrue(completed)
        let requested = await hardcover.receivedIDs
        XCTAssertEqual(requested, [missingTags.id])
        let allBooks = try await database.allBooks()
        let byID = Dictionary(uniqueKeysWithValues: allBooks.map { ($0.id, $0) })
        for id in [missingTags.id, savedTags.id] {
            let updated = try XCTUnwrap(byID[id])
            XCTAssertEqual(updated.genres, [.fantasy, .scienceFiction, .thriller, .horror])
            XCTAssertEqual(updated.genreSource, "hardcover")
            XCTAssertEqual(updated.hardcoverGenres, metadata.genres)
            XCTAssertNil(updated.description)
            XCTAssertTrue(updated.series.isEmpty)
            XCTAssertNil(updated.pageCount)
            XCTAssertEqual(updated.progression, 0.6)
        }
        XCTAssertEqual(byID[manual.id]?.genres, [.romance])
        XCTAssertEqual(byID[manual.id]?.genreSource, "manual")
        XCTAssertEqual(byID[manualUnclassified.id]?.genres, [])
        XCTAssertEqual(byID[manualUnclassified.id]?.genreSource, "manual")
        XCTAssertEqual(byID[alreadyClassified.id]?.genres, [.mystery])
        XCTAssertEqual(byID[alreadyClassified.id]?.genreSource, "subjects")
    }

    func testImportRunsHardcoverAfterOpenLibraryAndStoresBothSources() async throws {
        let database = try AppDatabase.inMemory()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = BookStorage(directory: directory)
        var catalog = fallback
        catalog.genres = ["Fantasy", "Science Fiction"]
        catalog.moods = ["Dark"]
        catalog.contentWarnings = ["Blood"]
        catalog.rating = 4.24
        catalog.ratingsCount = 1283
        let hardcover = HardcoverImportStub(result: catalog)
        let importer = BookImporter(database: database, storage: storage,
                                    openLibrary: FirstCatalog(), hardcover: hardcover)
        let fixture = try XCTUnwrap(Bundle(for: LibraryTests.self).url(forResource: "sample", withExtension: "pdf"))
        let imported = try await importer.importBook(from: fixture)
        await importer.waitForMetadata(bookID: imported.id)
        let saved = try await database.book(id: imported.id)
        let input = await hardcover.received
        XCTAssertEqual(input?.description, "An Open Library description already exists.")
        XCTAssertEqual(saved?.description, input?.description)
        XCTAssertEqual(saved?.series.first?.name, "Wizard Series")
        XCTAssertEqual(saved?.hardcoverGenres, ["Fantasy", "Science Fiction"])
        XCTAssertEqual(saved?.genres, [.fantasy, .scienceFiction])
        XCTAssertEqual(saved?.genreSource, "hardcover")
        XCTAssertEqual(saved?.hardcoverMoods, ["Dark"])
        XCTAssertEqual(saved?.hardcoverContentWarnings, ["Blood"])
        XCTAssertEqual(saved?.hardcoverRating, 4.24)
        XCTAssertEqual(saved?.hardcoverRatingsCount, 1283)
        XCTAssertEqual(saved?.pageCountSource, .pdf)
    }

    func testReadingMetadataBackfillAddsRatingToBooksWithTagsWithoutChangingGenres() async throws {
        let database = try AppDatabase.inMemory()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let importer = BookImporter(database: database, storage: BookStorage(directory: directory),
                                    openLibrary: nil, hardcover: client())
        var matched = book()
        matched.hardcoverMoods = ["Reflective"]
        matched.hardcoverContentWarnings = ["Blood"]
        matched.genres = [.romance]
        matched.genreSource = "manual"
        var unmatched = book()
        unmatched.title = "Ambiguous"
        try await database.insert(matched)
        try await database.insert(unmatched)

        await importer.backfillHardcoverReadingMetadata()

        let updated = try await database.book(id: matched.id)
        XCTAssertEqual(updated?.hardcoverMoods, ["Reflective"])
        XCTAssertEqual(updated?.hardcoverContentWarnings, ["Blood"])
        XCTAssertEqual(updated?.hardcoverFields["rating"], "https://hardcover.app/books/42")
        XCTAssertEqual(updated?.hardcoverRating, 4.24)
        XCTAssertEqual(updated?.hardcoverRatingsCount, 1283)
        XCTAssertEqual(updated?.genres, [.romance])
        XCTAssertEqual(updated?.genreSource, "manual")
        XCTAssertEqual(updated?.description, matched.description)
        let missed = try await database.book(id: unmatched.id)
        XCTAssertEqual(missed?.hardcoverMoods, [])
        XCTAssertEqual(missed?.hardcoverContentWarnings, [])
        XCTAssertNil(missed?.hardcoverRating)
        XCTAssertEqual(missed?.hardcoverRatingsCount, 0)
        let pending = try await database.booksMissingHardcoverReadingMetadata()
        XCTAssertTrue(pending.isEmpty)
    }
}

private actor FirstCatalog: OpenLibraryEnriching {
    func metadata(for book: Book) async throws -> OpenLibraryMetadata? {
        let record = try JSONDecoder().decode(OpenLibraryRecord.self, from: Data(#"{"key":"/works/OL1W","description":"An Open Library description already exists."}"#.utf8))
        return OpenLibraryMetadata(work: record, edition: nil)
    }
}
private actor HardcoverImportStub: HardcoverEnriching {
    let result: HardcoverMetadata
    var received: Book?
    var receivedIDs: [String] = []
    init(result: HardcoverMetadata) { self.result = result }
    func metadata(for book: Book) async throws -> HardcoverMetadata? {
        received = book
        receivedIDs.append(book.id)
        return result
    }
}
private final class HardcoverProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        XCTAssertEqual(request.url?.host, "metadata.test")
        XCTAssertEqual(request.url?.path, "/v1/metadata")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"), "No account credential belongs in the app")
        let parameters = (try? JSONSerialization.jsonObject(with: body)) as? [String: String] ?? [:]
        XCTAssertNil(parameters["query"])
        let title = parameters["title"]
        let identifier = parameters["isbn"]
        var record: [String: Any] = ["bookID": 42, "description": "A wizard journeys into an enchanted forest.",
            "series": [["name": "Wizard Series", "position": 2.5]], "genres": ["Fantasy"],
            "moods": ["Dark", "Tense"], "contentWarnings": ["Blood"],
            "rating": 4.24, "ratingsCount": 1283]
        var publicationYears: [String: Any] = ["releaseYear": 1980]
        if let identifier {
            let editionISBN = title == "Wrong ISBN" ? "080442957X" : identifier
            record["exactEdition"] = ["id": 11, "pages": 320,
                "isbn": editionISBN]
            publicationYears["exactEdition"] = ["id": 11, "isbn": editionISBN, "year": 2018]
        }
        record["publicationYears"] = publicationYears
        let absent = title == "Ambiguous" || identifier == "080442957X" || parameters["author"] == "Another Author"
        let json: [String: Any] = ["metadata": absent ? NSNull() : record]
        let status = title == "Rate Limited" ? 429 : title == "Error" ? 503 : 200
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: (try? JSONSerialization.data(withJSONObject: json)) ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
