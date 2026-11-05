import XCTest
@testable import ReadingTracker

@MainActor
final class ShelfTests: XCTestCase {
    private var database: AppDatabase!
    private var importer: BookImporter!
    private var storage: BookStorage!

    override func setUp() async throws {
        database = try AppDatabase.inMemory()
        storage = BookStorage(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        importer = BookImporter(database: database, storage: storage)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: storage.directory)
    }

    private func importSample() async throws -> Book {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "sample", withExtension: "epub"))
        return try await importer.importBook(from: url)
    }

    private func shelfList() async throws -> ShelfList {
        var iterator = database.observeShelves().makeAsyncIterator()
        let first = try await iterator.next()
        return try XCTUnwrap(first)
    }

    func testCreatingCleansNamesAndReusesExistingShelves() async throws {
        let created = try await database.createShelf(named: "  To   Read ")
        let shelf = try XCTUnwrap(created)
        XCTAssertEqual(shelf.name, "To Read")
        let again = try await database.createShelf(named: "to read")
        XCTAssertEqual(again?.id, shelf.id)
        let blank = try await database.createShelf(named: "   ")
        XCTAssertNil(blank)
        let list = try await shelfList()
        XCTAssertEqual(list.shelves.count, 1)
    }

    func testShelvesAreInNameOrderAndCanBeRenamed() async throws {
        let created = try await database.createShelf(named: "zebra")
        try await database.createShelf(named: "Apple")
        try await database.renameShelf(id: XCTUnwrap(created).id, to: " Mango ")
        let list = try await shelfList()
        XCTAssertEqual(list.shelves.map(\.name), ["Apple", "Mango"])
    }

    func testBooksCanBeOnSeveralShelvesAndFiltered() async throws {
        let book = try await importSample()
        let other = try await database.createShelf(named: "Other")
        let created = try await database.createShelf(named: "Favorites")
        let favorites = try XCTUnwrap(created)
        let otherId = try XCTUnwrap(other).id

        try await database.setBook(id: book.id, onShelf: favorites.id, true)
        try await database.setBook(id: book.id, onShelf: favorites.id, true) // adding twice is harmless
        try await database.setBook(id: book.id, onShelf: otherId, true)
        var list = try await shelfList()
        XCTAssertEqual(list.count(on: favorites.id), 1)
        XCTAssertEqual(list.books([book], on: favorites.id), [book])
        XCTAssertEqual(list.books([book], on: nil), [book])

        try await database.setBook(id: book.id, onShelf: favorites.id, false)
        list = try await shelfList()
        XCTAssertFalse(list.isBook(book.id, on: favorites.id))
        XCTAssertTrue(list.isBook(book.id, on: otherId))
        XCTAssertEqual(list.books([book], on: favorites.id), [])
    }

    func testAddsAndRemovesSeveralBooksAtOnce() async throws {
        let book = try await importSample()
        let created = try await database.createShelf(named: "Favorites")
        let shelf = try XCTUnwrap(created)
        try await database.setBook(id: book.id, onShelf: shelf.id, true)
        let second = try await importSample()
        XCTAssertNotEqual(book.id, second.id)

        // One of the two is already on the shelf.
        try await database.setBooks(ids: [book.id, second.id], onShelf: shelf.id, true)
        var list = try await shelfList()
        XCTAssertEqual(list.count(on: shelf.id), 2)

        try await database.setBooks(ids: [book.id, second.id], onShelf: shelf.id, false)
        list = try await shelfList()
        XCTAssertEqual(list.count(on: shelf.id), 0)
    }

    func testDeletingAShelfKeepsItsBooks() async throws {
        let book = try await importSample()
        let created = try await database.createShelf(named: "Favorites")
        let shelf = try XCTUnwrap(created)
        try await database.setBook(id: book.id, onShelf: shelf.id, true)
        try await database.deleteShelf(id: shelf.id)

        let list = try await shelfList()
        XCTAssertEqual(list, ShelfList())
        let books = try await database.allBooks()
        XCTAssertEqual(books.count, 1)
    }

    func testDeletingABookTakesItOffItsShelves() async throws {
        let book = try await importSample()
        let created = try await database.createShelf(named: "Favorites")
        let shelf = try XCTUnwrap(created)
        try await database.setBook(id: book.id, onShelf: shelf.id, true)
        try await importer.delete(book)

        let list = try await shelfList()
        XCTAssertEqual(list.shelves.map(\.id), [shelf.id])
        XCTAssertEqual(list.count(on: shelf.id), 0)
    }
}
