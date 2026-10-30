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
        migrator.registerMigration("v3-embedded-metadata") { db in
            try db.alter(table: "book") { t in
                t.add(column: "description", .text)
                t.add(column: "series", .text).notNull().defaults(to: "[]")
                t.add(column: "subjects", .text).notNull().defaults(to: "[]")
                t.add(column: "languages", .text).notNull().defaults(to: "[]")
            }
        }
        migrator.registerMigration("v4-highlights") { db in
            try db.create(table: "highlight") { t in
                t.primaryKey("id", .text)
                t.column("bookId", .text).notNull().indexed()
                    .references("book", onDelete: .cascade)
                t.column("locator", .text).notNull()
                t.column("text", .text).notNull()
                t.column("color", .text).notNull()
                t.column("note", .text).notNull().defaults(to: "")
                t.column("progression", .double).notNull()
                t.column("chapter", .text)
                t.column("pdfRects", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }
        migrator.registerMigration("v5-open-library") { db in
            try db.alter(table: "book") { t in
                t.add(column: "isbn", .text)
                t.add(column: "openLibraryWorkKey", .text)
                t.add(column: "openLibraryEditionKey", .text)
                t.add(column: "openLibraryFields", .text).notNull().defaults(to: "{}")
            }
        }
        migrator.registerMigration("v6-book-genres") { db in
            try db.alter(table: "book") { t in
                t.add(column: "genre", .text)
                t.add(column: "secondaryGenres", .text).notNull().defaults(to: "[]")
                t.add(column: "genreSource", .text)
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

    // MARK: Highlights

    func addHighlight(_ highlight: Highlight) async throws {
        try await writer.write { try highlight.insert($0) }
    }

    func updateHighlight(id: String, color: Highlight.Color? = nil, note: String? = nil) async throws {
        try await writer.write { db in
            guard var highlight = try Highlight.fetchOne(db, key: id) else { return }
            if let color { highlight.color = color }
            if let note { highlight.note = note }
            highlight.updatedAt = Date()
            try highlight.update(db)
        }
    }

    func deleteHighlight(id: String) async throws {
        _ = try await writer.write { try Highlight.deleteOne($0, key: id) }
    }

    /// A book's highlights in reading order, now and whenever they change.
    func observeHighlights(bookId: String) -> AsyncValueObservation<[Highlight]> {
        ValueObservation
            .tracking { db in
                try Highlight
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
