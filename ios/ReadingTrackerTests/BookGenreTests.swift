import XCTest
import GRDB
@testable import ReadingTracker

@MainActor
final class BookGenreTests: XCTestCase {
    private func book(subjects: [String] = [], description: String? = nil) -> Book {
        Book(id: UUID().uuidString, title: "A Book", author: "An Author", format: .epub,
             fileName: "book.epub", subjects: subjects, size: 1, addedAt: Date(), progression: 0)
    }
    private func input() -> GenreInput {
        var local = book()
        local.description = "In an invented kingdom, a young wizard discovers a magical doorway and must master ancient spells to protect her village from a dragon. The adventure takes her through enchanted forests to find the sorcerer who created the doorway."
        return GenreInput(book: local)
    }

    func testExactlySixteenCanonicalGenresMapLocally() {
        XCTAssertEqual(BookGenre.allCases.count, 16)
        for genre in BookGenre.allCases {
            XCTAssertEqual(SubjectGenreMapping.classify([genre.rawValue])?.primary, genre, genre.rawValue)
        }
        XCTAssertEqual(SubjectGenreMapping.classify(["FICTION / Science Fiction / Space Opera"])?.primary, .scienceFiction)
        XCTAssertEqual(SubjectGenreMapping.classify(["FICTION / Historical / General"])?.primary, .historicalFiction)
        XCTAssertEqual(SubjectGenreMapping.classify(["Biography & Autobiography / Memoirs"])?.primary, .memoir)
        XCTAssertEqual(SubjectGenreMapping.classify(["Romantasy"])?.secondary, [.romance])
    }

    func testBroadConflictingAndUnsupportedSubjectsDoNotForceGenres() {
        for subjects in [["Fiction"], ["Crime"], ["Cooking", "Travel"], ["Romance", "True Crime"], ["History", "Science Fiction"]] {
            XCTAssertNil(SubjectGenreMapping.classify(subjects), subjects.joined(separator: ", "))
        }
    }

    func testModelAnswersRequireCertaintyAllowedLabelsAndVerbatimEvidence() {
        let evidence = "a young wizard discovers a magical doorway"
        let valid = GenreModelAnswer(certain: true, choices: [.init(label: BookGenre.fantasy.rawValue, quote: evidence)])
        XCTAssertEqual(BookGenreClassifier.validated(valid, input: input())?.primary, .fantasy)
        XCTAssertNil(BookGenreClassifier.validated(.init(certain: false, choices: valid.choices), input: input()))
        XCTAssertNil(BookGenreClassifier.validated(.init(certain: true, choices: [.init(label: "Cooking", quote: evidence)]), input: input()))
        XCTAssertNil(BookGenreClassifier.validated(.init(certain: true, choices: [.init(label: BookGenre.fantasy.rawValue, quote: "invented evidence that does not exist")]), input: input()))
        XCTAssertNil(BookGenreClassifier.validated(.init(certain: true, choices: valid.choices + valid.choices), input: input()))
    }

    func testUnavailableModelAndInsufficientEvidenceStayUnclassified() async {
        let classifier = BookGenreClassifier(model: StubGenreModel(answer: nil))
        let unavailable = await classifier.classify(input())
        XCTAssertNil(unavailable)
        let sparse = await classifier.classify(GenreInput(book: book(subjects: ["Fiction"])))
        XCTAssertNil(sparse)
        let local = await classifier.classify(GenreInput(book: book(subjects: ["Space opera"])))
        XCTAssertEqual(local?.primary, .scienceFiction)
    }

    func testModelCanClassifyAmbiguousSynopsisWithoutNetwork() async {
        let classifier = BookGenreClassifier(model: StubGenreModel(answer: .init(certain: true, choices: [
            .init(label: BookGenre.fantasy.rawValue, quote: "a young wizard discovers a magical doorway")
        ])))
        let result = await classifier.classify(input())
        XCTAssertEqual(result?.primary, .fantasy)
        XCTAssertEqual(result?.source, "onDevice")
    }

    func testManualChoiceIncludingUnclassifiedSurvivesAutomaticResult() async throws {
        let db = try AppDatabase.inMemory()
        let local = book(subjects: ["Fantasy"])
        try await db.insert(local)
        _ = try await db.saveManualGenre(id: local.id, primary: .romance, secondary: [.fantasy])
        let decision = GenreDecision(primary: .fantasy, source: "subjects")
        try await db.saveAutomaticGenre(id: local.id, decision: decision, inputSignature: GenreInput(book: local).signature)
        var saved = try await db.book(id: local.id)
        XCTAssertEqual(saved?.genre, .romance)
        XCTAssertEqual(saved?.secondaryGenres, [.fantasy])
        _ = try await db.saveManualGenre(id: local.id, primary: nil, secondary: [.romance])
        try await db.saveAutomaticGenre(id: local.id, decision: decision, inputSignature: GenreInput(book: local).signature)
        saved = try await db.book(id: local.id)
        XCTAssertNil(saved?.genre)
        XCTAssertEqual(saved?.genreSource, "manual")
        XCTAssertEqual(saved?.secondaryGenres, [])
        try await db.resetManualGenre(id: local.id)
        await BookGenreClassifier(model: StubGenreModel(answer: nil)).classifyBook(id: local.id, database: db)
        saved = try await db.book(id: local.id)
        XCTAssertEqual(saved?.genre, .fantasy)
    }

    func testStalePredictionDoesNotOverwriteNewerMetadataOrProgress() async throws {
        let db = try AppDatabase.inMemory()
        var local = book(subjects: ["Fantasy"])
        try await db.insert(local)
        let oldSignature = GenreInput(book: local).signature
        XCTAssertEqual(oldSignature, GenreInput(book: local).signature)
        local.subjects = ["True Crime"]
        try await db.writer.write { try local.update($0) }
        try await db.saveProgress(id: local.id, locator: "latest", progression: 0.8)
        try await db.saveAutomaticGenre(id: local.id, decision: .init(primary: .fantasy, source: "subjects"), inputSignature: oldSignature)
        let saved = try await db.book(id: local.id)
        XCTAssertNil(saved?.genre)
        XCTAssertEqual(saved?.progression, 0.8)
        XCTAssertEqual(saved?.locator, "latest")
    }

    func testImportClassifiesAfterEnrichmentAndPersistsAcrossReopening() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let db = try AppDatabase.onDisk(directory: directory)
        let classifier = BookGenreClassifier(model: StubGenreModel(answer: nil))
        let importer = BookImporter(database: db, storage: BookStorage(directory: directory), openLibrary: GenreLookupStub(), classifier: classifier)
        let url = try XCTUnwrap(Bundle(for: LibraryTests.self).url(forResource: "sample", withExtension: "pdf"))
        let imported = try await importer.importBook(from: url)
        await importer.waitForMetadata(bookID: imported.id)
        let reopened = try AppDatabase.onDisk(directory: directory)
        let saved = try await reopened.book(id: imported.id)
        XCTAssertEqual(saved?.genre, .mystery)
        XCTAssertEqual(saved?.genreSource, "subjects")
        XCTAssertEqual(saved?.coverFileName, imported.coverFileName)
    }
}

private struct StubGenreModel: GenreModelPredicting {
    let answer: GenreModelAnswer?
    func predict(_ input: GenreInput) async -> GenreModelAnswer? { answer }
}
private struct GenreLookupStub: OpenLibraryEnriching {
    func metadata(for book: Book) async throws -> OpenLibraryMetadata? {
        let record = try JSONDecoder().decode(OpenLibraryRecord.self, from: Data(#"{"key":"/works/OL1W","description":"A detective searches for clues to a mysterious disappearance.","subjects":["Detective fiction"]}"#.utf8))
        return OpenLibraryMetadata(work: record, edition: nil)
    }
}
