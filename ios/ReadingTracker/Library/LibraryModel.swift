import Foundation
import SwiftUI

enum LibraryFilter: Equatable {
    case all, status(ReadingStatus), wishlist

    var label: String {
        switch self {
        case .all: "All Books"
        case .status(let status): status.label
        case .wishlist: "Wishlist"
        }
    }
}

/// State for the library screen: the book list, shelves, search, sort, and imports.
@MainActor
final class LibraryModel: ObservableObject {
    @Published private(set) var books: [Book] = []
    @Published private(set) var loaded = false
    @Published var query = ""
    @Published var filter: LibraryFilter = .all
    @Published var sort: LibrarySort {
        didSet { UserDefaults.standard.set(sort.rawValue, forKey: Self.sortKey) }
    }
    @Published private(set) var shelfList = ShelfList()
    @Published private var selectedShelfId: String? {
        didSet { UserDefaults.standard.set(selectedShelfId, forKey: Self.shelfKey) }
    }
    @Published private(set) var importing: [String] = []
    @Published var errorMessage: String?

    let environment: AppEnvironment
    private static let sortKey = "library-sort"
    private static let shelfKey = "library-shelf"
    private var observation: Task<Void, Never>?
    private var shelfObservation: Task<Void, Never>?

    init(environment: AppEnvironment) {
        self.environment = environment
        sort = UserDefaults.standard.string(forKey: Self.sortKey).flatMap(LibrarySort.init) ?? .recent
        selectedShelfId = UserDefaults.standard.string(forKey: Self.shelfKey)
        observation = Task { [weak self] in
            guard let database = self?.environment.database else { return }
            do {
                for try await books in database.observeBooks() {
                    self?.books = books
                    self?.loaded = true
                }
            } catch {
                self?.errorMessage = "Your library couldn’t be loaded. \(error.localizedDescription)"
            }
        }
        shelfObservation = Task { [weak self] in
            guard let database = self?.environment.database else { return }
            do {
                for try await shelfList in database.observeShelves() { self?.shelfList = shelfList }
            } catch {
                self?.errorMessage = "Your shelves couldn’t be loaded. \(error.localizedDescription)"
            }
        }
    }

    deinit {
        observation?.cancel()
        shelfObservation?.cancel()
    }

    /// The chosen shelf; a remembered one that no longer exists counts as none.
    var activeShelf: Shelf? {
        shelfList.shelves.first { $0.id == selectedShelfId }
    }

    var booksOnActiveShelf: [Book] {
        shelfList.books(books, on: activeShelf?.id)
    }

    var readingStatusFilter: ReadingStatus? {
        if case .status(let status) = filter { return status }
        return nil
    }

    var visibleBooks: [Book] {
        let books = booksOnActiveShelf.matching(query)
        return (readingStatusFilter.map { status in books.filter { $0.readingStatus == status } } ?? books)
            .sorted(by: sort)
    }

    func select(_ shelf: Shelf?) {
        selectedShelfId = shelf?.id
    }

    /// Creates a shelf. With no books (the shelf bar) it opens the new shelf; otherwise it adds them to it.
    func createShelf(named name: String, adding books: [Book] = []) {
        runShelfChange { database in
            guard let shelf = try await database.createShelf(named: name, adding: books.map(\.id)) else { return }
            if books.isEmpty {
                self.select(shelf)
            }
        }
    }

    func rename(_ shelf: Shelf, to name: String) {
        runShelfChange { try await $0.renameShelf(id: shelf.id, to: name) }
    }

    func delete(_ shelf: Shelf) {
        if selectedShelfId == shelf.id { select(nil) }
        runShelfChange { try await $0.deleteShelf(id: shelf.id) }
    }

    func toggle(_ book: Book, on shelf: Shelf) {
        let onShelf = !shelfList.isBook(book.id, on: shelf.id)
        runShelfChange { try await $0.setBook(id: book.id, onShelf: shelf.id, onShelf) }
    }

    func add(_ books: [Book], to shelf: Shelf) {
        runShelfChange { try await $0.setBooks(ids: books.map(\.id), onShelf: shelf.id, true) }
    }

    func remove(_ books: [Book], from shelf: Shelf) {
        runShelfChange { try await $0.setBooks(ids: books.map(\.id), onShelf: shelf.id, false) }
    }

    func setReadingStatus(_ status: ReadingStatus, for books: [Book], onFinished: @escaping (Book) -> Void) {
        Task {
            do {
                if let saved = try await environment.database.setReadingStatus(status, for: books.map(\.id)) {
                    onFinished(saved)
                }
            } catch {
                errorMessage = "Reading status couldn’t be updated. \(error.localizedDescription)"
            }
        }
    }

    private func runShelfChange(_ change: @escaping (AppDatabase) async throws -> Void) {
        Task {
            do {
                try await change(environment.database)
            } catch {
                errorMessage = "Your shelves couldn’t be updated. \(error.localizedDescription)"
            }
        }
    }

    func coverURL(for book: Book) -> URL? {
        book.coverFileName.map(environment.storage.url(for:))
    }

    func importFiles(_ urls: [URL]) {
        Task {
            var failures: [String] = []
            for url in urls {
                importing.append(url.lastPathComponent)
                defer { importing.removeAll { $0 == url.lastPathComponent } }
                do {
                    try await environment.importer.importBook(from: url)
                } catch {
                    failures.append(error.localizedDescription)
                }
                // Files from "Open in…" are copied into an Inbox folder; we have our own copy now.
                if url.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: url) }
            }
            if !failures.isEmpty { errorMessage = failures.joined(separator: "\n") }
        }
    }

    func delete(_ book: Book) {
        delete([book])
    }

    func delete(_ books: [Book]) {
        Task {
            var failures: [String] = []
            for book in books {
                do {
                    try await environment.importer.delete(book)
                } catch {
                    failures.append("“\(book.title)” couldn’t be deleted. \(error.localizedDescription)")
                }
            }
            if !failures.isEmpty { errorMessage = failures.joined(separator: "\n") }
        }
    }
}
