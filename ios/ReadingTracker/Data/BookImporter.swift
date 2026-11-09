import Foundation
import PDFKit
import ReadiumShared
import UIKit

enum ImportError: LocalizedError, Equatable {
    case unsupportedFile(String)
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFile(let name): "“\(name)” isn’t an EPUB or PDF file."
        case .copyFailed(let name): "“\(name)” couldn’t be copied into your library."
        }
    }
}

/// Adds book files to the library: copies the file in, reads its title,
/// author and cover, preserves optional embedded metadata, and saves it to the database.
@MainActor
final class BookImporter {
    private let database: AppDatabase
    private let storage: BookStorage
    private let readium: ReadiumServices
    private let openLibrary: (any OpenLibraryEnriching)?
    private let hardcover: (any HardcoverEnriching)?
    private let classifier: BookGenreClassifier?
    private var enrichments: [String: Task<Void, Never>] = [:]
    private var pageTasks: [String: Task<Void, Never>] = [:]
    private var backfillingHardcoverReadingMetadata = false

    static let coverSize = CGSize(width: 600, height: 900)

    init(database: AppDatabase, storage: BookStorage, readium: ReadiumServices = .shared,
         openLibrary: (any OpenLibraryEnriching)? = OpenLibraryClient.shared,
         classifier: BookGenreClassifier? = .shared,
         hardcover: (any HardcoverEnriching)? = HardcoverClient.shared) {
        self.database = database
        self.storage = storage
        self.readium = readium
        self.openLibrary = openLibrary
        self.classifier = classifier
        self.hardcover = hardcover
    }

    /// Imports a file from anywhere: the Files picker, "Open in…", or the app bundle.
    @discardableResult
    func importBook(from source: URL) async throws -> Book {
        // Files from the picker or other apps are only readable inside this scope.
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let name = source.lastPathComponent
        guard let format = Self.detectFormat(of: source) else { throw ImportError.unsupportedFile(name) }

        let id = UUID().uuidString
        let fileName = "\(id).\(format.fileExtension)"
        let destination = storage.url(for: fileName)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            throw ImportError.copyFailed(name)
        }

        var coverFileName: String?
        do {
            let publication = try await readium.openPublication(at: destination)
            let metadata = publication.metadata
            let pdfMetadata = format == .pdf ? PDFBookMetadata(url: destination) : nil
            let cover = format == .pdf
                ? Self.renderPDFCover(at: destination)
                : try? await publication.coverFitting(maxSize: Self.coverSize).get()
            if let data = cover?.jpegData(compressionQuality: 0.85) {
                coverFileName = "\(id)-cover.jpg"
                try data.write(to: storage.url(for: coverFileName!))
            }
            let initialPages = format == .pdf
                ? PDFDocument(url: destination).map { BookPageCount(count: $0.pageCount, source: .pdf) }
                : BookPageCounter.embedded(publication)
            let book = Book(
                id: id,
                title: Self.clean(metadata.title) ?? Self.title(fromFileName: name),
                author: Self.clean(metadata.authors.map(\.name).joined(separator: ", ")) ?? "Unknown author",
                format: format,
                fileName: fileName,
                coverFileName: coverFileName,
                description: BookDetailsText.description(pdfMetadata?.description ?? Self.clean(metadata.description)),
                series: format == .epub ? (metadata.belongsTo["series"] ?? []).compactMap {
                    guard let name = Self.clean($0.name) else { return nil }
                    return BookSeries(name: name, position: $0.position)
                } : pdfMetadata?.series ?? [],
                subjects: pdfMetadata?.subjects ?? metadata.subjects.compactMap { Self.clean($0.name) },
                languages: pdfMetadata?.languages ?? metadata.languages.compactMap { Self.clean($0) },
                isbn: OpenLibraryISBN.normalize(metadata.identifier),
                pageCount: initialPages?.count,
                pageCountSource: initialPages?.source,
                size: Self.fileSize(of: destination),
                addedAt: Date(),
                lastOpenedAt: nil,
                locator: nil,
                progression: 0
            )
            try await database.insert(book)
            Task { await updatePageCount(for: book, publication: publication) }
            enrichAfterImport(book)
            return book
        } catch {
            // Don't leave half-imported files behind.
            try? FileManager.default.removeItem(at: destination)
            if let coverFileName { try? FileManager.default.removeItem(at: storage.url(for: coverFileName)) }
            throw error
        }
    }

    func delete(_ book: Book) async throws {
        enrichments.removeValue(forKey: book.id)?.cancel()
        pageTasks.removeValue(forKey: book.id)?.cancel()
        try await database.deleteBook(id: book.id)
        storage.removeFiles(of: book)
    }

    /// Save the imported file immediately; network failures never fail an import.
    private func enrichAfterImport(_ book: Book) {
        let classifier = classifier
        let openLibrary = openLibrary
        enrichments[book.id] = Task { [weak self] in
            defer { self?.enrichments[book.id] = nil }
            guard let database = self?.database else { return }
            // Clear embedded subjects can be classified immediately, without AI or network.
            if let decision = SubjectGenreMapping.classify(book.subjects), classifier != nil {
                try? await database.saveAutomaticGenre(id: book.id, decision: decision,
                                                       inputSignature: GenreInput(book: book).signature)
            }
            if let openLibrary, BookDetailsText.description(book.description) == nil ||
                    book.series.isEmpty || book.subjects.isEmpty || book.languages.isEmpty ||
                    (book.format == .epub && book.pageCountSource == nil) {
                do {
                    if let metadata = try await openLibrary.metadata(for: book) {
                        try Task.checkCancellation()
                        _ = try await database.enrichBook(id: book.id, metadata: metadata,
                            fields: Set(OpenLibraryField.allCases), classify: false)
                    }
                } catch { /* Keep the local import even if lookup fails. */ }
            }
            guard !Task.isCancelled else { return }
            await updateCatalogPages(id: book.id)
            await self?.updateHardcover(id: book.id)
            // Always run after enrichment (or its failure), including fully embedded imports.
            await classifier?.classifyBook(id: book.id, database: database)
        }
    }

    func waitForMetadata(bookID: String) async { await enrichments[bookID]?.value }

    func backfillHardcoverReadingMetadata() async {
        guard let hardcover, !backfillingHardcoverReadingMetadata else { return }
        backfillingHardcoverReadingMetadata = true
        defer { backfillingHardcoverReadingMetadata = false }
        do {
            let books = try await database.booksMissingHardcoverReadingMetadata()
            for book in books where enrichments[book.id] == nil {
                try Task.checkCancellation()
                let metadata = try await hardcover.metadata(for: book)
                try Task.checkCancellation()
                try await database.saveHardcoverReadingMetadata(id: book.id, metadata: metadata)
            }
        } catch { /* Resume remaining lookups next launch after an interruption. */ }
    }

    /// Revisit old unclassified books using their saved evidence and fill missing Hardcover tags.
    func retryUnclassifiedGenres() async throws -> Bool {
        guard let classifier else { return true }
        var lookupAvailable = true
        let candidates = try await database.allBooks().filter(\.isAutomaticallyUnclassified)
        let withTags = candidates.filter { !$0.hardcoverGenres.isEmpty }
        let withoutTags = candidates.filter { $0.hardcoverGenres.isEmpty }
        for candidate in withTags + withoutTags {
            try Task.checkCancellation()
            guard var book = try await database.book(id: candidate.id), book.isAutomaticallyUnclassified else { continue }
            if book.hardcoverGenres.isEmpty, let hardcover, lookupAvailable {
                let metadata: HardcoverMetadata?
                do {
                    metadata = try await hardcover.metadata(for: book)
                } catch {
                    try Task.checkCancellation()
                    lookupAvailable = false
                    metadata = nil
                }
                if let metadata {
                    try Task.checkCancellation()
                    try await database.saveMissingHardcoverGenreTags(id: book.id, metadata: metadata)
                    guard let updated = try await database.book(id: book.id), updated.isAutomaticallyUnclassified else { continue }
                    book = updated
                }
            }
            let input = GenreInput(book: book)
            if let decision = await classifier.classify(input) {
                try Task.checkCancellation()
                try await database.saveAutomaticGenre(id: book.id, decision: decision, inputSignature: input.signature,
                                                      onlyIfUnclassified: true)
            }
        }
        return lookupAvailable
    }

    func updatePageCount(for book: Book, publication: Publication? = nil) async {
        if let task = pageTasks[book.id] { await task.value; return }
        if book.pageCountSource == .pdf || book.pageCountSource == .embedded { return }
        let task = Task { [weak self] in
            guard let self else { return }
            defer { pageTasks[book.id] = nil }
            if book.pageCountSource == nil {
                do {
                    let url = storage.url(for: book.fileName)
                    let pub: Publication
                    if let publication { pub = publication } else { pub = try await readium.openPublication(at: url) }
                    if book.isbn == nil, let isbn = OpenLibraryISBN.normalize(pub.metadata.identifier) {
                        try await database.saveEmbeddedISBN(id: book.id, isbn: isbn)
                    }
                    if let count = try await BookPageCounter.measure(publication: pub, format: book.format, url: url) {
                        try Task.checkCancellation()
                        try await database.savePageCount(id: book.id, measurement: count)
                    }
                } catch { /* Keep a known count; never invent one from an unreadable file. */ }
            }
            if enrichments[book.id] == nil { await updateCatalogPages(id: book.id) }
        }
        pageTasks[book.id] = task
        await task.value
    }

    private func updateCatalogPages(id: String) async {
        guard let openLibrary, !Task.isCancelled,
              let book = try? await database.book(id: id), book.format == .epub,
              book.pageCountSource == nil || book.pageCountSource == .estimated || book.pageCountSource == .hardcover,
              let count = try? await openLibrary.exactEditionPages(for: book), !Task.isCancelled else { return }
        try? await database.savePageCount(id: id, measurement: count)
    }

    /// Optional account-backed fallback. Never blocks saving or reading an import.
    private func updateHardcover(id: String) async {
        guard let hardcover, !Task.isCancelled,
              let book = try? await database.book(id: id),
              book.needsHardcoverReadingMetadata || BookDetailsText.description(book.description) == nil || book.series.isEmpty ||
                book.hardcoverGenres.isEmpty || book.pageCountSource == nil || book.pageCountSource == .estimated else { return }
        do {
            let metadata = try await hardcover.metadata(for: book)
            try Task.checkCancellation()
            if let metadata {
                try await database.enrichHardcover(id: id, metadata: metadata)
            } else {
                try await database.saveHardcoverReadingMetadata(id: id, metadata: nil)
            }
        } catch { /* Authentication, offline and catalog failures leave the local book usable. */ }
    }

    // MARK: Helpers

    /// Works out the format from the file's first bytes, falling back to its extension.
    nonisolated static func detectFormat(of url: URL) -> BookFormat? {
        if let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            let head = (try? handle.read(upToCount: 4)) ?? Data()
            if head.starts(with: [0x25, 0x50, 0x44, 0x46]) { return .pdf }  // %PDF
            if head.starts(with: [0x50, 0x4B, 0x03, 0x04]) { return .epub } // PK.. (zip)
        }
        return BookFormat(rawValue: url.pathExtension.lowercased())
    }

    /// "my_great-book.epub" -> "my great book"
    nonisolated static func title(fromFileName name: String) -> String {
        let base = name
            .replacingOccurrences(of: "\\.[^.]*$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[_-]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return base.isEmpty ? "Untitled" : base
    }

    private nonisolated static func clean(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private nonisolated static func fileSize(of url: URL) -> Int64 {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber
        return size?.int64Value ?? 0
    }

    /// The first page of a PDF, as a cover image.
    private static func renderPDFCover(at url: URL) -> UIImage? {
        guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let scale = coverSize.width / max(bounds.width, 1)
        return page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
    }
}
