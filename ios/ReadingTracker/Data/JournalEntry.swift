import Foundation
import GRDB

struct JournalEntry: Codable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "journalEntry"

    var id: String
    var bookId: String
    var text: String
    var createdAt: Date
}

extension AppDatabase {
    func addJournalEntry(bookId: String, text: String) async throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        try await writer.write { db in
            let entry = JournalEntry(id: UUID().uuidString, bookId: bookId, text: text, createdAt: Date())
            try entry.insert(db)
        }
    }

    func updateJournalEntry(id: String, text: String) async throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        try await writer.write { db in
            try db.execute(sql: "UPDATE journalEntry SET text = ? WHERE id = ?", arguments: [text, id])
            guard db.changesCount > 0 else {
                throw RecordError.recordNotFound(databaseTableName: JournalEntry.databaseTableName, key: ["id": id.databaseValue])
            }
        }
    }

    func deleteJournalEntry(id: String) async throws {
        _ = try await writer.write { try JournalEntry.deleteOne($0, key: id) }
    }

    func observeJournal(bookId: String) -> AsyncValueObservation<[JournalEntry]> {
        ValueObservation.tracking { db in
            try JournalEntry.filter(Column("bookId") == bookId)
                .order(Column("createdAt").desc, Column.rowID.desc)
                .fetchAll(db)
        }
        .values(in: writer)
    }
}
