import Foundation
import GRDB

/// The library database (SQLite via GRDB).
final class AppDatabase: Sendable {
    let writer: any DatabaseWriter

    init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    static var migrator: DatabaseMigrator {
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
        migrator.registerMigration("v7-page-counts") { db in
            try db.alter(table: "book") { t in
                t.add(column: "pageCount", .integer)
                t.add(column: "pageCountSource", .text)
                t.add(column: "pageCountEditionKey", .text)
            }
        }
        migrator.registerMigration("v8-shelves") { db in
            try db.create(table: "shelf") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "bookShelf") { t in
                t.column("bookId", .text).notNull().references("book", onDelete: .cascade)
                t.column("shelfId", .text).notNull().indexed().references("shelf", onDelete: .cascade)
                t.primaryKey(["bookId", "shelfId"])
            }
        }
        migrator.registerMigration("v9-hardcover") { db in
            try db.alter(table: "book") { t in
                t.add(column: "hardcoverBookID", .integer)
                t.add(column: "hardcoverGenres", .text).notNull().defaults(to: "[]")
                t.add(column: "hardcoverFields", .text).notNull().defaults(to: "{}")
            }
        }
        migrator.registerMigration("v10-genre-list") { db in
            try db.alter(table: "book") { t in
                t.add(column: "genres", .text).notNull().defaults(to: "[]")
            }
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, genre, secondaryGenres FROM book
                WHERE genre IS NOT NULL OR secondaryGenres <> '[]'
                """)
            let decoder = JSONDecoder()
            let encoder = JSONEncoder()
            for row in rows {
                let id: String = row["id"]
                let genre: String? = row["genre"]
                let secondary: String = row["secondaryGenres"]
                let saved = try decoder.decode([String].self, from: Data(secondary.utf8))
                let selected = Set([genre].compactMap { $0 } + saved)
                let genres = BookGenre.allCases.filter { selected.contains($0.rawValue) }
                let json = String(decoding: try encoder.encode(genres), as: UTF8.self)
                try db.execute(sql: "UPDATE book SET genres = ? WHERE id = ?", arguments: [json, id])
            }
            try db.execute(sql: "ALTER TABLE book DROP COLUMN genre")
            try db.execute(sql: "ALTER TABLE book DROP COLUMN secondaryGenres")
        }
        migrator.registerMigration("v11-hardcover-reading-tags") { db in
            try db.alter(table: "book") { t in
                t.add(column: "hardcoverMoods", .text)
                t.add(column: "hardcoverContentWarnings", .text)
            }
        }
        migrator.registerMigration("v12-hardcover-rating") { db in
            try db.alter(table: "book") { t in
                t.add(column: "hardcoverRating", .double)
                t.add(column: "hardcoverRatingsCount", .integer)
            }
        }
        migrator.registerMigration("v13-reading-status") { db in
            try db.alter(table: "book") { t in
                t.add(column: "readingStatus", .text).notNull().defaults(to: ReadingStatus.tbr.rawValue)
            }
        }
        migrator.registerMigration("v14-publication-years") { db in
            try db.alter(table: "book") { t in
                t.add(column: "embeddedEditionYear", .integer)
                t.add(column: "didReadEmbeddedEditionYear", .boolean).notNull().defaults(to: false)
                t.add(column: "hardcoverPublicationYears", .text)
            }
        }
        migrator.registerMigration("v15-personal-reading") { db in
            try db.alter(table: "book") { t in
                t.add(column: "personalRating", .integer).check { (1...5).contains($0) }
            }
            try db.create(table: JournalEntry.databaseTableName) { t in
                t.primaryKey("id", .text)
                t.column("bookId", .text).notNull().indexed().references("book", onDelete: .cascade)
                t.column("text", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
        }
        migrator.registerMigration("v16-quarter-star-ratings-and-thoughts") { db in
            try db.alter(table: "book") { t in
                t.add(column: "personalRatingQuarterStars", .integer).check { (1...20).contains($0) }
                t.add(column: "personalThoughts", .text)
            }
            try db.execute(sql: "UPDATE book SET personalRatingQuarterStars = personalRating * 4")
            try db.alter(table: "book") { $0.drop(column: "personalRating") }
        }
        migrator.registerMigration("v17-personal-moods") { db in
            try db.alter(table: "book") { $0.add(column: "personalMoods", .text) }
        }
        migrator.registerMigration("v18-book-reactions") { db in
            try db.create(table: BookReaction.databaseTableName) { t in
                t.primaryKey("id", .text)
                t.column("bookId", .text).notNull().indexed().references("book", onDelete: .cascade)
                t.column("kind", .text).notNull()
                t.column("locator", .text).notNull()
                t.column("progression", .double).notNull()
                t.column("locationTitle", .text)
                t.column("createdAt", .datetime).notNull()
            }
        }
        migrator.registerMigration("v19-wishlist") { db in
            try db.create(table: "wishlist") { t in
                t.primaryKey("id", .integer)
                t.column("book", .blob).notNull()
                t.column("savedAt", .datetime).notNull()
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

    func saveEmbeddedPublicationYear(id: String, year: Int?, isbn: String? = nil) async throws {
        try await writer.write { db in
            guard var book = try Book.fetchOne(db, key: id), !book.didReadEmbeddedEditionYear else { return }
            book.embeddedEditionYear = year
            book.didReadEmbeddedEditionYear = true
            if book.isbn == nil, let isbn {
                book.isbn = isbn
                if book.hardcoverPublicationYears?.release == nil {
                    book.hardcoverPublicationYears = nil
                }
            }
            try book.update(db)
        }
    }

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

    /// Returns the saved book when a single book changes to Finished.
    @discardableResult
    func setReadingStatus(_ status: ReadingStatus, for bookIDs: [String]) async throws -> Book? {
        try await writer.write { db in
            for id in bookIDs {
                try db.execute(
                    sql: "UPDATE book SET readingStatus = ? WHERE id = ? AND readingStatus <> ?",
                    arguments: [status, id, status]
                )
                if status == .finished, bookIDs.count == 1, db.changesCount > 0 {
                    return try Book.fetchOne(db, key: id)
                }
            }
            return nil
        }
    }

    func savePersonalReview(quarterStars: Int?, moods: Set<BookMood>, thoughts: String, for bookID: String) async throws {
        let savedThoughts = thoughts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : thoughts
        let orderedMoods = BookMood.allCases.filter { moods.contains($0) }
        let savedMoods = orderedMoods.isEmpty ? nil : String(decoding: try JSONEncoder().encode(orderedMoods), as: UTF8.self)
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE book SET personalRatingQuarterStars = ?, personalMoods = ?, personalThoughts = ? WHERE id = ?",
                arguments: [quarterStars, savedMoods, savedThoughts, bookID]
            )
            guard db.changesCount > 0 else {
                throw RecordError.recordNotFound(databaseTableName: Book.databaseTableName, key: ["id": bookID.databaseValue])
            }
        }
    }

    func markReadingIfTBR(id: String) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE book SET readingStatus = ? WHERE id = ? AND readingStatus = ?",
                arguments: [ReadingStatus.reading, id, ReadingStatus.tbr]
            )
        }
    }

    // MARK: Wishlist

    func isWishlisted(_ bookID: Int) async throws -> Bool {
        try await writer.read { db in
            try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM wishlist WHERE id = ?)", arguments: [bookID]) ?? false
        }
    }

    func setWishlisted(_ book: DiscoveryBook, saved: Bool) async throws {
        try await writer.write { db in
            if saved {
                let data = try JSONEncoder().encode(book)
                try db.execute(
                    sql: "INSERT INTO wishlist (id, book, savedAt) VALUES (?, ?, ?) ON CONFLICT(id) DO NOTHING",
                    arguments: [book.id, data, Date()]
                )
            } else {
                try db.execute(sql: "DELETE FROM wishlist WHERE id = ?", arguments: [book.id])
            }
        }
    }

    func observeWishlist() -> AsyncValueObservation<[DiscoveryBook]> {
        ValueObservation.tracking { db in
            let books = try Data.fetchAll(db, sql: "SELECT book FROM wishlist ORDER BY savedAt DESC, id DESC")
            let decoder = JSONDecoder()
            return try books.map { try decoder.decode(DiscoveryBook.self, from: $0) }
        }.values(in: writer)
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

    // MARK: Shelves

    /// Creates or reuses a shelf by name and adds the supplied books in the same transaction.
    @discardableResult
    func createShelf(named name: String, adding bookIDs: [String] = []) async throws -> Shelf? {
        let clean = Shelf.cleanName(name)
        guard !clean.isEmpty else { return nil }
        return try await writer.write { db in
            let shelf: Shelf
            if let existing = try Shelf.fetchAll(db).first(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame }) {
                shelf = existing
            } else {
                shelf = Shelf(id: UUID().uuidString, name: clean, createdAt: Date())
                try shelf.insert(db)
            }
            for bookID in bookIDs {
                try BookShelf(bookId: bookID, shelfId: shelf.id).insert(db, onConflict: .ignore)
            }
            return shelf
        }
    }

    func renameShelf(id: String, to name: String) async throws {
        let clean = Shelf.cleanName(name)
        guard !clean.isEmpty else { return }
        try await writer.write { db in
            try db.execute(sql: "UPDATE shelf SET name = ? WHERE id = ?", arguments: [clean, id])
        }
    }

    /// Deletes a shelf. Its books stay in the library.
    func deleteShelf(id: String) async throws {
        _ = try await writer.write { try Shelf.deleteOne($0, key: id) }
    }

    func setBook(id bookId: String, onShelf shelfId: String, _ onShelf: Bool) async throws {
        try await setBooks(ids: [bookId], onShelf: shelfId, onShelf)
    }

    /// Adds books to a shelf or takes them off it, all or none.
    func setBooks(ids bookIds: [String], onShelf shelfId: String, _ onShelf: Bool) async throws {
        try await writer.write { db in
            for bookId in bookIds {
                let entry = BookShelf(bookId: bookId, shelfId: shelfId)
                if onShelf {
                    try entry.insert(db, onConflict: .ignore)
                } else {
                    try entry.delete(db)
                }
            }
        }
    }

    /// Every shelf and its books, now and whenever they change.
    func observeShelves() -> AsyncValueObservation<ShelfList> {
        ValueObservation
            .tracking { db in
                let shelves = try Shelf.fetchAll(db).sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                var shelfIdsByBook: [String: Set<String>] = [:]
                for entry in try BookShelf.fetchAll(db) {
                    shelfIdsByBook[entry.bookId, default: []].insert(entry.shelfId)
                }
                return ShelfList(shelves: shelves, shelfIdsByBook: shelfIdsByBook)
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
