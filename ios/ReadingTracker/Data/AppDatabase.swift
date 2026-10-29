import Foundation
import GRDB

/// The library database (SQLite via GRDB).
final class AppDatabase: Sendable {
    let writer: any DatabaseWriter

    init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try migrator.migrate(writer)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "book") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("author", .text).notNull()
                t.column("format", .text).notNull()
                t.column("fileName", .text).notNull()
                t.column("coverFileName", .text)
                t.column("size", .integer).notNull()
                t.column("addedAt", .datetime).notNull().indexed()
                t.column("lastOpenedAt", .datetime)
                t.column("locator", .text)
                t.column("progression", .double).notNull().defaults(to: 0)
            }
        }
        migrator.registerMigration("v2-bookmarks") { db in
            try db.create(table: "bookmark") { t in
                t.primaryKey("id", .text)
                t.column("bookId", .text).notNull().indexed()
                    .references("book", onDelete: .cascade)
                t.column("locator", .text).notNull()
                t.column("progression", .double).notNull()
                t.column("title", .text)
                t.column("createdAt", .datetime).notNull()
            }
        }
        return migrator
    }

    /// The database stored in Application Support, which iOS never clears.
    static func onDisk(directory: URL) throws -> AppDatabase {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: directory.appendingPathComponent("library.sqlite").path)
        return try AppDatabase(queue)
    }

    static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    // MARK: Books

    func insert(_ book: Book) async throws {
        try await writer.write { try book.insert($0) }
    }

    func book(id: String) async throws -> Book? {
        try await writer.read { try Book.fetchOne($0, key: id) }
    }

    func allBooks() async throws -> [Book] {
        try await writer.read { try Book.fetchAll($0) }
    }

    func deleteBook(id: String) async throws {
        _ = try await writer.write { try Book.deleteOne($0, key: id) }
    }

    func markOpened(id: String, at date: Date = Date()) async throws {
        try await writer.write { db in
            try db.execute(sql: "UPDATE book SET lastOpenedAt = ? WHERE id = ?", arguments: [date, id])
        }
    }

    func saveProgress(id: String, locator: String, progression: Double) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE book SET locator = ?, progression = ? WHERE id = ?",
                arguments: [locator, min(max(progression, 0), 1), id]
            )
        }
    }

    // MARK: Bookmarks

    func addBookmark(_ bookmark: Bookmark) async throws {
        try await writer.write { try bookmark.insert($0) }
    }

    func deleteBookmark(id: String) async throws {
        _ = try await writer.write { try Bookmark.deleteOne($0, key: id) }
    }

    /// A book's bookmarks in reading order, now and whenever they change.
    func observeBookmarks(bookId: String) -> AsyncValueObservation<[Bookmark]> {
        ValueObservation
            .tracking { db in
                try Bookmark
                    .filter(Column("bookId") == bookId)
                    .order(Column("progression"), Column("createdAt"))
                    .fetchAll(db)
            }
            .values(in: writer)
    }

    /// Emits the full list of books now and whenever it changes.
    func observeBooks() -> AsyncValueObservation<[Book]> {
        ValueObservation
            .tracking { try Book.fetchAll($0) }
            .values(in: writer)
    }
}
