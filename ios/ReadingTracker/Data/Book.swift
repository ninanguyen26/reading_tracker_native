import Foundation
import GRDB

enum BookFormat: String, Codable, DatabaseValueConvertible, Sendable {
    case epub
    case pdf

    var fileExtension: String { rawValue }
    var label: String { rawValue.uppercased() }
}

/// One embedded series membership, including fractional positions such as 2.5.
struct BookSeries: Codable, Hashable, Sendable {
    var name: String
    var position: Double?
}

/// A book in the library. The file itself lives in `BookStorage`.
struct Book: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "book"

    var id: String
    var title: String
    var author: String
    var format: BookFormat
    /// File name inside the books folder
    var fileName: String
    /// Cover image file name inside the books folder, if the book has one
    var coverFileName: String?
    /// Optional embedded book metadata. Arrays are stored as JSON by GRDB.
    var description: String? = nil
    var series: [BookSeries] = []
    var subjects: [String] = []
    /// BCP 47 language tags supplied by the publication, e.g. "en" or "vi".
    var languages: [String] = []
    var size: Int64
    var addedAt: Date
    var lastOpenedAt: Date?
    /// Where the reader left off: a Readium `Locator` as JSON
    var locator: String?
    /// 0…1 through the whole book
    var progression: Double

    enum Columns {
        static let title = Column(CodingKeys.title)
        static let author = Column(CodingKeys.author)
        static let addedAt = Column(CodingKeys.addedAt)
        static let lastOpenedAt = Column(CodingKeys.lastOpenedAt)
    }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case recent, added, title, author

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recent: "Recently Read"
        case .added: "Recently Added"
        case .title: "Title"
        case .author: "Author"
        }
    }
}

extension Array where Element == Book {
    func sorted(by sort: LibrarySort) -> [Book] {
        let byText = { (a: String, b: String) in a.localizedStandardCompare(b) == .orderedAscending }
        switch sort {
        case .recent:
            // Books never opened fall back to when they were added.
            return sorted { ($0.lastOpenedAt ?? $0.addedAt) > ($1.lastOpenedAt ?? $1.addedAt) }
        case .added:
            return sorted { $0.addedAt > $1.addedAt }
        case .title:
            return sorted { byText($0.title, $1.title) }
        case .author:
            return sorted { $0.author == $1.author ? byText($0.title, $1.title) : byText($0.author, $1.author) }
        }
    }

    func matching(_ query: String) -> [Book] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return self }
        return filter { $0.title.localizedCaseInsensitiveContains(q) || $0.author.localizedCaseInsensitiveContains(q) }
    }
}
