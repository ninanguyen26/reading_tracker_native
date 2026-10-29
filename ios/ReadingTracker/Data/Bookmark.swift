import Foundation
import GRDB

/// A saved place in a book.
struct Bookmark: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "bookmark"

    var id: String
    var bookId: String
    /// A Readium `Locator` as JSON
    var locator: String
    /// 0…1 through the whole book, for ordering and display
    var progression: Double
    /// Chapter title at the bookmark, if known
    var title: String?
    var createdAt: Date
}
