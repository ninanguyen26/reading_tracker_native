import Foundation
import GRDB

protocol HardcoverEnriching: Sendable {
    func metadata(for book: Book) async throws -> HardcoverMetadata?
    func metadata(matchingISBN isbn: String) async throws -> HardcoverMetadata?
}

extension HardcoverEnriching {
    func metadata(matchingISBN isbn: String) async throws -> HardcoverMetadata? { nil }
}

struct HardcoverPublicationYears: Codable, Hashable, Sendable {
    struct Entry: Codable, Hashable, Sendable {
        var year: Int
        var sourceURL: String
    }

    var release: Entry? = nil
    var edition: Entry? = nil
}

struct HardcoverMetadata: Sendable {
    var bookID: Int
    var description: String?
    var series: [BookSeries]
    var genres: [String]
    var moods: [String]? = nil
    var contentWarnings: [String]? = nil
    var rating: Double? = nil
    var ratingsCount: Int? = nil
    /// Only populated by a unique, exact ISBN edition match. Never book-level pages.
    var pages: BookPageCount?
    /// Nil when the catalog server predates publication year support.
    var publicationYears: HardcoverPublicationYears? = nil
    var sourceURL: String { "https://hardcover.app/books/\(bookID)" }

    func filling(_ original: Book) -> Book {
        var book = original
        book.hardcoverBookID = bookID
        if BookDetailsText.description(book.description) == nil,
           let text = BookDetailsText.description(description) {
            book.description = text
            book.hardcoverFields["description"] = sourceURL
        }
        if book.series.isEmpty {
            book.series = series.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if !book.series.isEmpty { book.hardcoverFields["series"] = sourceURL }
        }
        applyGenreTags(to: &book)
        applyReadingMetadata(to: &book)
        if book.format == .epub, let pages, pages.count > 0, pages.source == .hardcover,
           book.pageCountSource == nil || book.pageCountSource!.priority >= pages.source.priority {
            book.pageCount = pages.count
            book.pageCountSource = .hardcover
            book.pageCountEditionKey = pages.editionKey
        }
        return book
    }

    func applyGenreTags(to book: inout Book) {
        book.hardcoverGenres = BookDetailsText.nonempty(genres)
        if !book.hardcoverGenres.isEmpty { book.hardcoverFields["genres"] = sourceURL }
    }

    func applyReadingMetadata(to book: inout Book) {
        if let publicationYears { book.hardcoverPublicationYears = publicationYears }
        if book.hardcoverMoods == nil, let moods {
            let tags = BookDetailsText.nonempty(moods)
            book.hardcoverMoods = tags
            if !tags.isEmpty { book.hardcoverFields["moods"] = sourceURL }
        }
        if book.hardcoverContentWarnings == nil, let contentWarnings {
            let tags = BookDetailsText.nonempty(contentWarnings)
            book.hardcoverContentWarnings = tags
            if !tags.isEmpty { book.hardcoverFields["contentWarnings"] = sourceURL }
        }
        if book.hardcoverRatingsCount == nil, let ratingsCount, ratingsCount >= 0 {
            book.hardcoverRatingsCount = ratingsCount
            if ratingsCount > 0, let rating, rating.isFinite, (0...5).contains(rating) {
                book.hardcoverRating = rating
                book.hardcoverFields["rating"] = sourceURL
            }
        }
    }
}

extension AppDatabase {
    func enrichHardcover(id: String, metadata: HardcoverMetadata) async throws {
        try await writer.write { db in
            guard let latest = try Book.fetchOne(db, key: id),
                  latest.hardcoverBookID == nil || latest.hardcoverBookID == metadata.bookID else { return }
            try metadata.filling(latest).update(db)
        }
    }

    func booksMissingHardcoverReadingMetadata() async throws -> [Book] {
        try await writer.read { db in
            try Book.filter(sql: """
                hardcoverMoods IS NULL OR hardcoverContentWarnings IS NULL OR hardcoverRatingsCount IS NULL
                """).fetchAll(db)
        }
    }

    func saveHardcoverReadingMetadata(id: String, metadata: HardcoverMetadata?, recordNoMatch: Bool = false) async throws {
        try await writer.write { db in
            guard var book = try Book.fetchOne(db, key: id), book.needsHardcoverReadingMetadata ||
                    (recordNoMatch && book.hardcoverPublicationYears == nil) else { return }
            if let metadata {
                guard book.hardcoverBookID == nil || book.hardcoverBookID == metadata.bookID else { return }
                metadata.applyReadingMetadata(to: &book)
            } else {
                if book.hardcoverMoods == nil { book.hardcoverMoods = [] }
                if book.hardcoverContentWarnings == nil { book.hardcoverContentWarnings = [] }
                if book.hardcoverRatingsCount == nil { book.hardcoverRatingsCount = 0 }
                if recordNoMatch && book.hardcoverPublicationYears == nil {
                    book.hardcoverPublicationYears = HardcoverPublicationYears()
                }
            }
            try book.update(db)
        }
    }

    func saveHardcoverPublicationYears(id: String, isbn: String?, bookID: Int?, years: HardcoverPublicationYears) async throws {
        try await writer.write { db in
            guard var book = try Book.fetchOne(db, key: id), book.isbn == isbn,
                  bookID == nil || book.hardcoverBookID == nil || book.hardcoverBookID == bookID,
                  book.hardcoverPublicationYears == nil else { return }
            book.hardcoverPublicationYears = years
            try book.update(db)
        }
    }

    func saveMissingHardcoverGenreTags(id: String, metadata: HardcoverMetadata) async throws {
        try await writer.write { db in
            guard var book = try Book.fetchOne(db, key: id), book.isAutomaticallyUnclassified,
                  book.hardcoverBookID == nil || book.hardcoverBookID == metadata.bookID,
                  book.hardcoverGenres.isEmpty else { return }
            metadata.applyGenreTags(to: &book)
            if !book.hardcoverGenres.isEmpty {
                book.hardcoverBookID = metadata.bookID
                try book.update(db)
            }
        }
    }
}

enum HardcoverError: LocalizedError {
    case request, rateLimited, unavailable, notConfigured
    var errorDescription: String? {
        switch self {
        case .request: "Book metadata could not be loaded."
        case .rateLimited: "Book metadata lookup is busy. Try again later."
        case .unavailable: "Book metadata is temporarily unavailable."
        case .notConfigured: "The book metadata service has not been configured."
        }
    }
}

/// The app talks only to our catalog service. Hardcover credentials never enter the app.
actor HardcoverClient: HardcoverEnriching {
    static let shared = HardcoverClient()
    private let session: URLSession
    private let endpoint: URL?
    private var backoff = Date.distantPast

    init(session: URLSession = .shared, endpoint: URL? = HardcoverClient.configuredEndpoint) {
        self.session = session
        self.endpoint = endpoint
    }
    static var configuredEndpoint: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "MetadataServiceURL") as? String,
              let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
    func metadata(for book: Book) async throws -> HardcoverMetadata? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-hardcover-reading-tags-fixture") {
            guard book.title == "Field Notes" else { return nil }
            return HardcoverMetadata(bookID: 42, description: nil, series: [], genres: [],
                                     moods: ["Reflective", "Tense"], contentWarnings: ["Blood"],
                                     rating: 4.24, ratingsCount: 1283, pages: nil)
        }
        #endif
        let isbn = OpenLibraryISBN.normalize(book.isbn)
        guard isbn != nil || (!book.title.isEmpty && !book.author.isEmpty && book.author != "Unknown author") else { return nil }
        return try await lookup(Lookup(isbn: isbn, title: String(book.title.prefix(500)), author: String(book.author.prefix(300))))
    }

    func metadata(matchingISBN isbn: String) async throws -> HardcoverMetadata? {
        guard let isbn = OpenLibraryISBN.normalize(isbn) else { return nil }
        return try await lookup(Lookup(isbn: isbn, title: "", author: ""))
    }

    private func lookup(_ input: Lookup) async throws -> HardcoverMetadata? {
        guard let endpoint else { throw HardcoverError.notConfigured }
        guard Date() >= backoff else { throw HardcoverError.rateLimited }
        let isbn = input.isbn
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90 // Accommodate Render Free cold starts in a background task.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(input)
        for attempt in 0..<2 {
            try Task.checkCancellation()
            do {
                let (data, raw) = try await session.data(for: request)
                try Task.checkCancellation()
                guard let response = raw as? HTTPURLResponse else { throw HardcoverError.unavailable }
                if response.statusCode == 429 {
                    let delay = Double(response.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60
                    backoff = Date().addingTimeInterval(max(60, delay))
                    throw HardcoverError.rateLimited
                }
                guard response.statusCode == 200 else { throw HardcoverError.unavailable }
                let result = try JSONDecoder().decode(Response.self, from: data)
                guard let record = result.metadata else { return nil }
                guard record.bookID > 0 else { throw HardcoverError.request }
                var pages: BookPageCount?
                if let edition = record.exactEdition, edition.id > 0, edition.pages > 0,
                   let isbn, OpenLibraryISBN.normalize(edition.isbn) == isbn {
                    pages = BookPageCount(count: edition.pages, source: .hardcover,
                        editionKey: "https://hardcover.app/books/\(record.bookID)/editions/\(edition.id)")
                }
                let bookURL = "https://hardcover.app/books/\(record.bookID)"
                let publicationYears = record.publicationYears.map { years in
                    var result = HardcoverPublicationYears()
                    if let year = years.releaseYear, (1...9999).contains(year) {
                        result.release = .init(year: year, sourceURL: bookURL)
                    }
                    if let edition = years.exactEdition, edition.id > 0, (1...9999).contains(edition.year),
                       let isbn, OpenLibraryISBN.normalize(edition.isbn) == isbn {
                        result.edition = .init(year: edition.year, sourceURL: "\(bookURL)/editions/\(edition.id)")
                    }
                    return result
                }
                return HardcoverMetadata(bookID: record.bookID, description: record.description,
                    series: record.series, genres: record.genres, moods: record.moods,
                    contentWarnings: record.contentWarnings, rating: record.rating,
                    ratingsCount: record.ratingsCount, pages: pages, publicationYears: publicationYears)
            } catch {
                if Task.isCancelled { throw CancellationError() }
                if case HardcoverError.rateLimited = error { throw error }
                if attempt == 1 { throw error }
                // A first request may wake Render without getting a usable response.
                try await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
        return nil
    }
    private struct Lookup: Encodable { var isbn: String?; var title: String; var author: String }
    private struct Response: Decodable { var metadata: Record? }
    private struct Record: Decodable {
        var bookID: Int
        var description: String?
        var series: [BookSeries]
        var genres: [String]
        var moods: [String]?
        var contentWarnings: [String]?
        var rating: Double?
        var ratingsCount: Int?
        var exactEdition: Edition?
        var publicationYears: PublicationYears?
    }
    private struct Edition: Decodable { var id: Int; var isbn: String; var pages: Int }
    private struct PublicationYears: Decodable {
        struct Edition: Decodable { var id: Int; var isbn: String; var year: Int }
        var releaseYear: Int?
        var exactEdition: Edition?
    }
}

#if DEBUG
/// Explicit diagnostic using a public catalog ISBN; does not touch the user's library.
enum HardcoverSmokeTest {
    static func run() async {
        var book = Book(id: "catalog-smoke", title: "Fantastic Mr. Fox", author: "Roald Dahl", format: .epub,
                        fileName: "", size: 0, addedAt: Date(), progression: 0)
        book.isbn = "9780140328721"
        do {
            let result = try await HardcoverClient.shared.metadata(for: book)
            NSLog("HARDCOVER_SMOKE matched=%@ description=%@ series=%@ genres=%@ exactPages=%@", String(result != nil),
                  String(BookDetailsText.description(result?.description) != nil), String(!(result?.series.isEmpty ?? true)),
                  String(!(result?.genres.isEmpty ?? true)), String(result?.pages?.source == .hardcover))
        } catch { NSLog("HARDCOVER_SMOKE failed=%@", error.localizedDescription) }
    }
}
#endif
