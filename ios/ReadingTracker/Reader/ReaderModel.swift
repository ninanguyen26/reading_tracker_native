import Foundation
import ReadiumNavigator
import ReadiumShared
import UIKit

/// Opens a book, creates the right Readium navigator, and saves the reading position.
@MainActor
final class ReaderModel: ObservableObject {
    enum State {
        case loading
        case ready(ReaderHostViewController)
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var locator: Locator?
    @Published private(set) var positionCount: Int?
    /// Toolbars start hidden so the book opens full-screen, like Apple Books and Kindle.
    @Published var chromeVisible = false

    let book: Book
    private let environment: AppEnvironment
    private var publication: Publication?
    private weak var epubNavigator: EPUBNavigatorViewController?
    /// Follows the system's light or dark appearance (full themes come later).
    private var darkMode = false

    init(book: Book, environment: AppEnvironment) {
        self.book = book
        self.environment = environment
    }

    func setDarkMode(_ dark: Bool) {
        guard dark != darkMode else { return }
        darkMode = dark
        epubNavigator?.submitPreferences(epubPreferences)
    }

    private var epubPreferences: EPUBPreferences {
        EPUBPreferences(theme: darkMode ? .dark : .light)
    }

    func load() async {
        guard case .loading = state, publication == nil else { return }
        do {
            let publication = try await ReadiumServices.shared.openPublication(
                at: environment.storage.url(for: book.fileName)
            )
            self.publication = publication

            // Read the saved position fresh, in case it changed since the library listed this book.
            let saved = try await environment.database.book(id: book.id)?.locator
            let initialLocation = saved.flatMap { try? Locator(jsonString: $0) }

            let navigator: VisualNavigator & UIViewController
            if publication.conforms(to: .pdf) {
                navigator = try PDFNavigatorViewController(
                    publication: publication,
                    initialLocation: initialLocation,
                    delegate: self
                )
            } else {
                let epub = try EPUBNavigatorViewController(
                    publication: publication,
                    initialLocation: initialLocation,
                    config: .init(preferences: epubPreferences)
                )
                epub.delegate = self
                epubNavigator = epub
                navigator = epub
            }
            state = .ready(ReaderHostViewController(
                navigator: navigator,
                onTapCenter: { [weak self] in self?.chromeVisible.toggle() },
                // Like a Kindle, turning the page tucks the toolbars away.
                onPageTurn: { [weak self] in self?.chromeVisible = false }
            ))
            locator = initialLocation
            try? await environment.database.markOpened(id: book.id)
            positionCount = try? await publication.positions().get().count
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: Footer

    var chapterTitle: String? { locator?.title }

    var progressLabel: String {
        guard let locator else { return "" }
        let percent = (locator.locations.totalProgression ?? 0).formatted(.percent.precision(.fractionLength(0)))
        guard let position = locator.locations.position, let positionCount else { return percent }
        let unit = book.format == .pdf ? "Page" : "Location"
        return "\(unit) \(position) of \(positionCount) · \(percent)"
    }

    private func save(_ locator: Locator) {
        guard let json = try? locator.jsonString() else { return }
        let progression = locator.locations.totalProgression ?? 0
        Task { try? await environment.database.saveProgress(id: book.id, locator: json, progression: progression) }
    }
}

extension ReaderModel: EPUBNavigatorDelegate, PDFNavigatorDelegate {
    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        self.locator = locator
        save(locator)
    }

    func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
        state = .failed(error.localizedDescription)
    }
}
