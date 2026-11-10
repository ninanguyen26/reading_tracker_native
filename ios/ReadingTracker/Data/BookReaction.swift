import Foundation
import GRDB
import ReadiumShared

enum ReactionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case lovedIt, laughed, moved, surprised, tense, scared, sad, frustrated, confused

    var id: Self { self }

    var emoji: String {
        switch self {
        case .lovedIt: "❤️"
        case .laughed: "😂"
        case .moved: "🥹"
        case .surprised: "😮"
        case .tense: "😬"
        case .scared: "😱"
        case .sad: "😢"
        case .frustrated: "😤"
        case .confused: "😕"
        }
    }

    var label: String {
        switch self {
        case .lovedIt: "Loved it"
        case .laughed: "Laughed"
        case .moved: "Moved"
        case .surprised: "Surprised"
        case .tense: "Tense"
        case .scared: "Scared"
        case .sad: "Sad"
        case .frustrated: "Frustrated"
        case .confused: "Confused"
        }
    }
}

struct BookReaction: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "bookReaction"

    var id: String
    var bookId: String
    var kind: ReactionKind
    /// The reader's exact Readium locator as JSON.
    var locator: String
    var progression: Double
    var locationTitle: String?
    var createdAt: Date
}

struct ReactionSpot: Identifiable, Sendable {
    let anchor: BookReaction
    private(set) var kinds: [ReactionKind]

    var id: String { anchor.id }

    /// Keep the order of the saved reactions, which arrive sorted by reading position.
    static func group(_ reactions: [BookReaction]) -> [ReactionSpot] {
        var spots: [ReactionSpot] = []
        var indices: [LocationKey: Int] = [:]
        for reaction in reactions {
            let key = LocationKey(reaction.locator)
            if let index = indices[key] {
                if !spots[index].kinds.contains(reaction.kind) {
                    spots[index].kinds.append(reaction.kind)
                }
            } else {
                indices[key] = spots.count
                spots.append(ReactionSpot(anchor: reaction, kinds: [reaction.kind]))
            }
        }
        return spots
    }

    fileprivate enum LocationKey: Hashable {
        case position(AnyURL, Locator.Locations)
        case raw(String)

        init(_ json: String) {
            if let locator = try? Locator(jsonString: json) {
                self = .position(locator.href, locator.locations)
            } else {
                self = .raw(json)
            }
        }
    }
}

extension AppDatabase {
    func addReactions(_ kinds: Set<ReactionKind>, bookId: String, locator: String,
                      progression: Double, locationTitle: String?) async throws {
        try await writer.write { db in
            try Self.insertReactions(kinds, bookId: bookId, locator: locator,
                                     progression: progression, locationTitle: locationTitle, in: db)
        }
    }

    func editReactions(at spot: ReactionSpot, selection: Set<ReactionKind>) async throws {
        let original = Set(spot.kinds)
        let removed = original.subtracting(selection)
        let added = selection.subtracting(original)
        let anchor = spot.anchor
        try await writer.write { db in
            let current = try Self.reactions(at: anchor, in: db)
            guard !current.isEmpty else { return }
            let removedIDs = current.filter { removed.contains($0.kind) }.map(\.id)
            try BookReaction.deleteAll(db, keys: removedIDs)
            try Self.insertReactions(added.subtracting(current.map(\.kind)), bookId: anchor.bookId,
                                     locator: anchor.locator, progression: anchor.progression,
                                     locationTitle: anchor.locationTitle, in: db)
        }
    }

    func deleteReactions(at anchor: BookReaction) async throws {
        try await writer.write { db in
            let ids = try Self.reactions(at: anchor, in: db).map(\.id)
            try BookReaction.deleteAll(db, keys: ids)
        }
    }

    private static func reactions(at anchor: BookReaction, in db: Database) throws -> [BookReaction] {
        let location = ReactionSpot.LocationKey(anchor.locator)
        return try BookReaction.filter(Column("bookId") == anchor.bookId)
            .fetchAll(db)
            .filter { ReactionSpot.LocationKey($0.locator) == location }
    }

    private static func insertReactions(_ kinds: Set<ReactionKind>, bookId: String, locator: String,
                                        progression: Double, locationTitle: String?, in db: Database) throws {
        let createdAt = Date()
        for kind in ReactionKind.allCases where kinds.contains(kind) {
            try BookReaction(id: UUID().uuidString, bookId: bookId, kind: kind,
                             locator: locator, progression: progression,
                             locationTitle: locationTitle, createdAt: createdAt).insert(db)
        }
    }

    func observeReactions(bookId: String) -> AsyncValueObservation<[BookReaction]> {
        ValueObservation.tracking { db in
            try BookReaction.filter(Column("bookId") == bookId)
                .order(Column("progression"), Column("createdAt"), Column.rowID)
                .fetchAll(db)
        }
        .values(in: writer)
    }
}
