import Foundation
import GRDB

/// A user-named group of books. A book can be on several.
struct Shelf: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "shelf"

    var id: String
    var name: String
    var createdAt: Date

    /// Trims a name and collapses its inner whitespace.
    static func cleanName(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// One book on one shelf.
struct BookShelf: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "bookShelf"

    var bookId: String
    var shelfId: String
}

/// Every shelf, in name order, and which books are on them.
struct ShelfList: Equatable, Sendable {
    var shelves: [Shelf] = []
    var shelfIdsByBook: [String: Set<String>] = [:]

    func isBook(_ bookId: String, on shelfId: String) -> Bool {
        shelfIdsByBook[bookId]?.contains(shelfId) ?? false
    }

    func count(on shelfId: String) -> Int {
        shelfIdsByBook.values.filter { $0.contains(shelfId) }.count
    }

    /// The books on a shelf; a nil shelf means all of them.
    func books(_ books: [Book], on shelfId: String?) -> [Book] {
        guard let shelfId else { return books }
        return books.filter { isBook($0.id, on: shelfId) }
    }
}
