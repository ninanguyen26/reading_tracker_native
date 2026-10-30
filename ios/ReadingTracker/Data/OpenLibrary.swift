import Foundation
import GRDB

enum OpenLibraryISBN {
    static func normalize(_ value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() else { return nil }
        for prefix in ["URN:ISBN:", "ISBN:", "ISBN "] where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
        }
        let digits = value.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
        let chars = Array(digits)
        if chars.count == 13, chars.allSatisfy({ $0.isNumber && $0.isASCII }) {
            let sum = chars.enumerated().reduce(0) { $0 + $1.element.wholeNumberValue! * ($1.offset.isMultiple(of: 2) ? 1 : 3) }
            return sum.isMultiple(of: 10) ? digits : nil
        }
        if chars.count == 10 {
            var sum = 0
            for (index, char) in chars.enumerated() {
                guard let digit = char.wholeNumberValue, char.isASCII else {
                    if index == 9 && char == "X" { sum += 10; continue }
                    return nil
                }
                sum += digit * (10 - index)
            }
            return sum.isMultiple(of: 11) ? digits : nil
        }
        return nil
    }
}

struct OpenLibrarySearch: Decodable {
    var docs: [OpenLibraryMatch]
}

struct OpenLibraryMatch: Decodable, Identifiable {
    var key: String
    var title: String
    var author_name: [String]?
    var first_publish_year: Int?
    var id: String { key }
}

struct OpenLibraryEditions: Decodable {
    var entries: [OpenLibraryRecord]
}

/// Both descriptions and series vary in shape across community catalog records.
struct OpenLibraryRecord: Decodable, Identifiable {
    var key: String
    var title: String?
    var description: String?
    var subjects: [String]
    var series: [String]
    var languages: [String]
    var publishers: [String]
    var publishDate: String?
    var workKeys: [String]
    var numberOfPages: Int?
    var id: String { key }

    private enum CodingKeys: String, CodingKey {
        case key, title, description, subjects, series, languages, publishers, publish_date, works, number_of_pages
    }
    private struct TextValue: Decodable { var value: String }
    private struct Reference: Decodable { var key: String }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        title = try? c.decode(String.self, forKey: .title)
        description = (try? c.decode(String.self, forKey: .description))
            ?? (try? c.decode(TextValue.self, forKey: .description).value)
        subjects = (try? c.decode([String].self, forKey: .subjects)) ?? []
        series = (try? c.decode([String].self, forKey: .series))
            ?? (try? c.decode(String.self, forKey: .series)).map { [$0] } ?? []
        languages = ((try? c.decode([Reference].self, forKey: .languages)) ?? [])
            .map { String($0.key.split(separator: "/").last ?? "") }.filter { !$0.isEmpty }
        publishers = (try? c.decode([String].self, forKey: .publishers)) ?? []
        publishDate = try? c.decode(String.self, forKey: .publish_date)
        workKeys = ((try? c.decode([Reference].self, forKey: .works)) ?? []).map(\.key)
        numberOfPages = try? c.decode(Int.self, forKey: .number_of_pages)
    }
}

enum OpenLibraryField: String, CaseIterable, Identifiable {
    case description, series, subjects, languages
    var id: String { rawValue }
    var label: String { self == .languages ? "Language" : rawValue.capitalized }
}

struct OpenLibraryMetadata {
    var workKey: String
    var editionKey: String?
    var description: String?
    var series: [BookSeries]
    var subjects: [String]
    var languages: [String]
    private var sources: [OpenLibraryField: String] = [:]
    var exactEditionPages: BookPageCount? = nil

    init(work: OpenLibraryRecord, edition: OpenLibraryRecord?, exactEdition: Bool = false) {
        workKey = work.key
        editionKey = edition?.key
        description = BookDetailsText.description(edition?.description) ?? BookDetailsText.description(work.description)
        series = BookDetailsText.nonempty(edition?.series.isEmpty == false ? edition!.series : work.series)
            .map { BookSeries(name: $0, position: nil) }
        subjects = BookDetailsText.nonempty(edition?.subjects.isEmpty == false ? edition!.subjects : work.subjects)
        // Work-level languages can describe many translations; only use a selected edition.
        languages = edition?.languages ?? []
        sources[.description] = BookDetailsText.description(edition?.description) != nil ? edition?.key : work.key
        sources[.series] = edition?.series.isEmpty == false ? edition?.key : work.key
        sources[.subjects] = edition?.subjects.isEmpty == false ? edition?.key : work.key
        sources[.languages] = edition?.key
        if exactEdition, let edition, let count = edition.numberOfPages, count > 0 {
            exactEditionPages = BookPageCount(count: count, source: .openLibrary, editionKey: edition.key)
        }
    }

    func availableFields(for book: Book) -> [OpenLibraryField] {
        OpenLibraryField.allCases.filter {
            switch $0 {
            case .description: BookDetailsText.description(book.description) == nil && description != nil
            case .series: BookDetailsText.nonempty(book.series.map(\.name)).isEmpty && !series.isEmpty
            case .subjects: BookDetailsText.nonempty(book.subjects).isEmpty && !subjects.isEmpty
            case .languages: BookDetailsText.nonempty(book.languages).isEmpty && !languages.isEmpty
            }
        }
    }

    func value(for field: OpenLibraryField) -> String {
        switch field {
        case .description: description ?? ""
        case .series: series.map(\.name).joined(separator: " · ")
        case .subjects: subjects.joined(separator: " · ")
        case .languages: languages.map { Locale.current.localizedString(forLanguageCode: $0) ?? $0 }.joined(separator: ", ")
        }
    }

    func filling(_ original: Book, fields: Set<OpenLibraryField>) -> Book {
        var book = original
        if book.format == .epub, let pages = exactEditionPages,
           book.pageCountSource == nil || book.pageCountSource == .estimated || book.pageCountSource == .openLibrary {
            book.pageCount = pages.count
            book.pageCountSource = pages.source
            book.pageCountEditionKey = pages.editionKey
        }
        let additions = Set(availableFields(for: original)).intersection(fields)
        guard !additions.isEmpty else { return book }
        if additions.contains(.description) { book.description = description }
        if additions.contains(.series) { book.series = series }
        if additions.contains(.subjects) { book.subjects = subjects }
        if additions.contains(.languages) { book.languages = languages }
        book.openLibraryWorkKey = workKey
        book.openLibraryEditionKey = editionKey
        for field in additions { book.openLibraryFields[field.rawValue] = sources[field] ?? workKey }
        return book
    }
}

extension AppDatabase {
    /// Re-read inside the transaction so reading progress and concurrent edits survive.
    func enrichBook(id: String, metadata: OpenLibraryMetadata, fields: Set<OpenLibraryField>, classify: Bool = true) async throws -> Book {
        let updated = try await writer.write { db in
            guard let existing = try Book.fetchOne(db, key: id) else { throw OpenLibraryError.missingBook }
            let updated = metadata.filling(existing, fields: fields)
            try updated.update(db)
            return updated
        }
        if classify { await BookGenreClassifier.shared.classifyBook(id: id, database: self) }
        return try await book(id: id) ?? updated
    }
}

enum OpenLibraryError: LocalizedError {
    case invalidRecord, rateLimited, unavailable, missingBook, notFound
    var errorDescription: String? {
        switch self {
        case .invalidRecord: "This catalog record could not be read. Try another match."
        case .rateLimited: "Open Library is receiving too many requests. Please try again later."
        case .unavailable: "Open Library is unavailable right now. Please try again later."
        case .missingBook: "This book is no longer in your library."
        case .notFound: "This book wasn't found in Open Library."
        }
    }
}

protocol OpenLibraryEnriching: Sendable {
    func metadata(for book: Book) async throws -> OpenLibraryMetadata?
    func exactEditionPages(for book: Book) async throws -> BookPageCount?
}
extension OpenLibraryEnriching {
    func exactEditionPages(for book: Book) async throws -> BookPageCount? { nil }
}

/// Requests follow imports or manual lookups. One per second, bounded caching,
/// plus URLSession's persistent HTTP cache; never sends files or requests covers.
actor OpenLibraryClient: OpenLibraryEnriching {
    static let shared: OpenLibraryClient = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-open-library-fixtures") {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [OpenLibraryFixtureProtocol.self]
            return OpenLibraryClient(session: URLSession(configuration: configuration))
        }
        #endif
        return OpenLibraryClient()
    }()
    private let session: URLSession
    private var lastRequest = Date.distantPast
    private var cache: [URL: (Date, Data)] = [:]

    init(session: URLSession = .shared) { self.session = session }

    static func searchURL(title: String, author: String, isbn: String) -> URL {
        var components = URLComponents(string: "https://openlibrary.org/search.json")!
        var query = [URLQueryItem(name: "limit", value: "20"),
                     URLQueryItem(name: "fields", value: "key,title,author_name,first_publish_year")]
        if let isbn = OpenLibraryISBN.normalize(isbn) {
            query.append(URLQueryItem(name: "isbn", value: isbn))
        } else {
            query.append(URLQueryItem(name: "title", value: title.trimmingCharacters(in: .whitespacesAndNewlines)))
            if !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                query.append(URLQueryItem(name: "author", value: author.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
        components.queryItems = query
        return components.url!
    }

    func search(title: String, author: String, isbn: String) async throws -> [OpenLibraryMatch] {
        let result: OpenLibrarySearch = try await fetch(Self.searchURL(title: title, author: author, isbn: isbn))
        return result.docs.filter { Self.validKey($0.key, kind: "works", suffix: "W") }
    }

    /// Match an ISBN edition, otherwise require one exact title-and-author match.
    func metadata(for book: Book) async throws -> OpenLibraryMetadata? {
        if let isbn = OpenLibraryISBN.normalize(book.isbn) {
            do {
                let edition: OpenLibraryRecord = try await fetch(URL(string: "https://openlibrary.org/isbn/\(isbn).json")!)
                guard Self.validKey(edition.key, kind: "books", suffix: "M"),
                      let workKey = edition.workKeys.first,
                      Self.validKey(workKey, kind: "works", suffix: "W") else { return nil }
                return OpenLibraryMetadata(work: try await work(workKey), edition: edition, exactEdition: true)
            } catch OpenLibraryError.notFound {
                // Unknown ISBNs can still have a reliable title-and-author match.
            }
        }
        let title = Self.matchText(book.title)
        let author = Self.matchText(book.author)
        guard !title.isEmpty, !author.isEmpty, book.author != "Unknown author" else { return nil }
        let results = try await search(title: book.title, author: book.author, isbn: "")
        let matches = results.filter {
            Self.matchText($0.title) == title &&
            (Self.matchText(($0.author_name ?? []).joined(separator: ", ")) == author ||
             ($0.author_name ?? []).contains { Self.matchText($0) == author })
        }
        guard Set(matches.map(\.key)).count == 1, let match = matches.first else { return nil }
        return OpenLibraryMetadata(work: try await work(match.key), edition: nil)
    }

    private static func matchText(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    func exactEditionPages(for book: Book) async throws -> BookPageCount? {
        let url: URL
        if let isbn = OpenLibraryISBN.normalize(book.isbn) {
            url = URL(string: "https://openlibrary.org/isbn/\(isbn).json")!
        } else if let key = book.openLibraryEditionKey, Self.validKey(key, kind: "books", suffix: "M") {
            url = URL(string: "https://openlibrary.org\(key).json")!
        } else { return nil }
        let edition: OpenLibraryRecord = try await fetch(url)
        guard Self.validKey(edition.key, kind: "books", suffix: "M"), let count = edition.numberOfPages, count > 0 else { return nil }
        return BookPageCount(count: count, source: .openLibrary, editionKey: edition.key)
    }

    func work(_ key: String) async throws -> OpenLibraryRecord {
        guard Self.validKey(key, kind: "works", suffix: "W") else { throw OpenLibraryError.invalidRecord }
        let record: OpenLibraryRecord = try await fetch(URL(string: "https://openlibrary.org\(key).json")!)
        guard record.key == key else { throw OpenLibraryError.invalidRecord }
        return record
    }

    func editions(_ key: String, offset: Int) async throws -> [OpenLibraryRecord] {
        guard Self.validKey(key, kind: "works", suffix: "W") else { throw OpenLibraryError.invalidRecord }
        let response: OpenLibraryEditions = try await fetch(URL(string: "https://openlibrary.org\(key)/editions.json?limit=20&offset=\(offset)")!)
        return response.entries.filter { Self.validKey($0.key, kind: "books", suffix: "M") }
    }

    static func validKey(_ key: String, kind: String, suffix: String) -> Bool {
        key.range(of: "^/\(kind)/OL[0-9]+\(suffix)$", options: .regularExpression) != nil
    }

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        if let (date, data) = cache[url], Date().timeIntervalSince(date) < 86400 {
            return try JSONDecoder().decode(T.self, from: data)
        }
        // Reserve a slot before suspending so concurrent callers remain spaced.
        let slot = max(Date(), lastRequest.addingTimeInterval(1.1))
        lastRequest = slot
        let delay = slot.timeIntervalSinceNow
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        try Task.checkCancellation()
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 25)
        request.setValue("ReadingTracker/0.1 (https://github.com/ninanguyen26/reading_tracker_native)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenLibraryError.unavailable }
        if http.statusCode == 429 { throw OpenLibraryError.rateLimited }
        if http.statusCode == 404 { throw OpenLibraryError.notFound }
        guard http.statusCode == 200 else { throw OpenLibraryError.unavailable }
        let decoded: T
        do { decoded = try JSONDecoder().decode(T.self, from: data) }
        catch { throw OpenLibraryError.invalidRecord }
        if cache.count >= 100 { cache.removeAll() }
        cache[url] = (Date(), data)
        return decoded
    }
}

#if DEBUG
/// Deterministic UI-test responses. Enabled only by an explicit debug launch argument.
final class OpenLibraryFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "openlibrary.org" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var json: String
        switch request.url!.path {
        case "/search.json":
            json = #"{"docs":[{"key":"/works/OL1W","title":"Field Notes","author_name":["Jordan Lee"],"first_publish_year":2020}]}"#
        case "/works/OL1W/editions.json":
            json = #"{"entries":[{"key":"/books/OL1M","title":"Field Notes","publish_date":"2020","publishers":["Test Press"],"languages":[{"key":"/languages/eng"}],"series":["Nature Journals"]}]}"#
        default:
            json = #"{"key":"/works/OL1W","description":"Observations from the natural world.","subjects":["Nature","Journals"],"series":["Nature Journals"]}"#
        }
        if ProcessInfo.processInfo.arguments.contains("-long-description-fixture"), request.url!.path == "/works/OL1W.json" {
            let synopsis = String(repeating: "A naturalist records the changing seasons and the creatures living along the coast. ", count: 12) + "The final chapter follows the returning birds."
            json = String(data: try! JSONSerialization.data(withJSONObject: ["key": "/works/OL1W", "description": synopsis, "subjects": ["Nature", "Journals"], "series": ["Nature Journals"]]), encoding: .utf8)!
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
