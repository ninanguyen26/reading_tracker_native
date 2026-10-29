import Foundation
import SwiftUI

/// State for the library screen: the book list, search, sort, and imports.
@MainActor
final class LibraryModel: ObservableObject {
    @Published private(set) var books: [Book] = []
    @Published private(set) var loaded = false
    @Published var query = ""
    @Published var sort: LibrarySort {
        didSet { UserDefaults.standard.set(sort.rawValue, forKey: Self.sortKey) }
    }
    @Published private(set) var importing: [String] = []
    @Published var errorMessage: String?

    let environment: AppEnvironment
    private static let sortKey = "library-sort"
    private var observation: Task<Void, Never>?

    init(environment: AppEnvironment) {
        self.environment = environment
        sort = UserDefaults.standard.string(forKey: Self.sortKey).flatMap(LibrarySort.init) ?? .recent
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
    }

    deinit { observation?.cancel() }

    var visibleBooks: [Book] {
        books.matching(query).sorted(by: sort)
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
        Task {
            do {
                try await environment.importer.delete(book)
            } catch {
                errorMessage = "“\(book.title)” couldn’t be deleted. \(error.localizedDescription)"
            }
        }
    }
}
