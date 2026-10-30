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
    private let classifier: BookGenreClassifier?
    private var enrichments: [String: Task<Void, Never>] = [:]

    static let coverSize = CGSize(width: 600, height: 900)

    init(database: AppDatabase, storage: BookStorage, readium: ReadiumServices = .shared,
         openLibrary: (any OpenLibraryEnriching)? = OpenLibraryClient.shared,
         classifier: BookGenreClassifier? = .shared) {
        self.database = database
        self.storage = storage
        self.readium = readium
        self.openLibrary = openLibrary
        self.classifier = classifier
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
                size: Self.fileSize(of: destination),
                addedAt: Date(),
                lastOpenedAt: nil,
                locator: nil,
                progression: 0
            )
            try await database.insert(book)
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
                    book.series.isEmpty || book.subjects.isEmpty || book.languages.isEmpty {
                do {
                    if let metadata = try await openLibrary.metadata(for: book) {
                        try Task.checkCancellation()
                        _ = try await database.enrichBook(id: book.id, metadata: metadata,
                            fields: Set(OpenLibraryField.allCases), classify: false)
                    }
                } catch { /* Keep the local import even if lookup fails. */ }
            }
            guard !Task.isCancelled else { return }
            // Always run after enrichment (or its failure), including fully embedded imports.
            await classifier?.classifyBook(id: book.id, database: database)
        }
    }

    func waitForMetadata(bookID: String) async { await enrichments[bookID]?.value }

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
