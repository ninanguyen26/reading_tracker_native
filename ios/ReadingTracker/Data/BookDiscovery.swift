import Foundation

struct DiscoveryBook: Codable, Identifiable, Sendable {
    let id: Int
    let title: String
    let author: String
    let description: String?
    let coverURL: URL?
    let alternateCoverURLs: [URL]?
    let isbns: [String]
    let language: String?

    var coverSources: [URL] {
        let hardcover = ([coverURL].compactMap { $0 } + (alternateCoverURLs ?? [])).filter { url in
            url.scheme == "https" && url.host?.hasSuffix(".hardcover.app") == true &&
                url.user == nil && url.password == nil && url.port == nil
        }
        let openLibrary = isbns.compactMap { rawISBN -> URL? in
            guard let isbn = OpenLibraryISBN.normalize(rawISBN) else { return nil }
            return URL(string: "https://covers.openlibrary.org/b/isbn/\(isbn)-M.jpg?default=false")
        }
        var seen = Set<URL>()
        return (hardcover + openLibrary).filter { seen.insert($0).inserted }
    }

    var sourceURL: URL { URL(string: "https://hardcover.app/books/\(id)")! }

    func libraryMatch(in books: [Book]) -> Book? {
        if let matched = books.first(where: { $0.hardcoverBookID == id }) { return matched }
        return books.first { book in
            guard book.hardcoverBookID == nil, let isbn = OpenLibraryISBN.normalize(book.isbn) else { return false }
            return isbns.contains(isbn)
        }
    }
}

struct DiscoverySeriesEntry: Decodable, Identifiable, Sendable {
    let book: DiscoveryBook
    let position: Double?
    var id: Int { book.id }
}

struct DiscoverySeries: Decodable, Identifiable, Sendable {
    let id: Int
    let name: String
    let currentPosition: Double?
    let entries: [DiscoverySeriesEntry]
    let nextOffset: Int?
}

struct DiscoverySeriesPage: Decodable, Sendable {
    let entries: [DiscoverySeriesEntry]
    let nextOffset: Int?
}

struct BookDiscovery: Decodable, Sendable {
    let bookID: Int
    let series: [DiscoverySeries]
    let authorBooks: [DiscoveryBook]
}

struct DiscoveryPreviewMetadata: Decodable, Sendable {
    let genres: [String]
    let moods: [String]
    let releaseYear: Int?
    let rating: Double?
    let ratingsCount: Int?
    let language: String?
}

enum BookDiscoveryClient {
    private struct BookID: Encodable { let bookID: Int; var language: String? = nil }
    private struct Lookup: Encodable { let isbn: String?; let title: String; let author: String; var language: String? = nil }
    private struct Page: Encodable { let seriesID: Int; let offset: Int; var bookID: Int? = nil; var language: String? = nil }
    private struct Response: Decodable { let discovery: BookDiscovery? }
    private struct PreviewResponse: Decodable { let preview: DiscoveryPreviewMetadata? }

    static func language(for book: Book) -> String? {
        book.languages.lazy.compactMap(BookDetailsText.languageCode).first
    }

    static func discover(for book: Book) async throws -> BookDiscovery? {
        let language = language(for: book)
        if let bookID = book.hardcoverBookID, bookID > 0 {
            let result: Response = try await request(
                "discovery", body: BookID(bookID: bookID, language: language),
                legacyBody: language == nil ? nil : BookID(bookID: bookID)
            )
            if let discovery = result.discovery { return discovery }
        }
        let isbn = OpenLibraryISBN.normalize(book.isbn)
        guard isbn != nil || (!book.title.isEmpty && !book.author.isEmpty && book.author != "Unknown author") else { return nil }
        let lookup = Lookup(isbn: isbn, title: String(book.title.prefix(500)), author: String(book.author.prefix(300)))
        var localizedLookup = lookup
        localizedLookup.language = language
        let result: Response = try await request(
            "discovery", body: localizedLookup, legacyBody: language == nil ? nil : lookup
        )
        return result.discovery
    }

    static func seriesPage(id: Int, offset: Int, currentBookID: Int?, language: String?) async throws -> DiscoverySeriesPage {
        try await request(
            "series", body: Page(seriesID: id, offset: offset, bookID: currentBookID, language: language),
            legacyBody: Page(seriesID: id, offset: offset)
        )
    }

    static func preview(for bookID: Int) async throws -> DiscoveryPreviewMetadata? {
        let response: PreviewResponse = try await request("preview", body: BookID(bookID: bookID), legacyBody: nil)
        return response.preview
    }

    private static func request<Body: Encodable, Result: Decodable>(
        _ path: String, body: Body, legacyBody: Body?
    ) async throws -> Result {
        guard let base = HardcoverClient.configuredEndpoint?.deletingLastPathComponent() else {
            throw HardcoverError.notConfigured
        }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode
        if status == 400, let legacyBody {
            return try await self.request(path, body: legacyBody, legacyBody: nil)
        }
        guard status == 200 else { throw HardcoverError.unavailable }
        return try JSONDecoder().decode(Result.self, from: data)
    }
}
