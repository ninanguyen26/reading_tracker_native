import Foundation
import PDFKit
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

    @Published var settings: ReaderSettings {
        didSet {
            guard settings != oldValue else { return }
            ReaderSettingsStore.save(settings)
            applySettings()
        }
    }
    @Published private(set) var tableOfContents: [Link] = []
    @Published private(set) var bookmarks: [Bookmark] = []
    @Published private(set) var search = BookSearch()
    @Published var highlights: [Highlight] = []
    @Published var highlightPalette: HighlightPalette = HighlightPaletteStore.load()
    /// The highlight open in the editor sheet; `focusNote` puts the cursor in the note.
    @Published var editing: (id: String, focusNote: Bool)?
    /// Whether the system is in dark mode, for the "Auto" theme.
    @Published private(set) var systemDark = false

    let book: Book
    private let environment: AppEnvironment
    private(set) var publication: Publication?
    private(set) var navigator: (VisualNavigator & UIViewController)?
    private var bookmarkObservation: Task<Void, Never>?
    var highlightObservation: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var readingMovement: (origin: Locator, deadline: ContinuousClock.Instant?)?
    /// PDFKit's view inside the PDF navigator, used for search marks and highlights.
    weak var pdfView: PDFView?
    /// PDF highlights drawn as annotations, by highlight ID.
    var pdfAnnotations: [String: [PDFAnnotation]] = [:]

    var environmentDatabase: AppDatabase { environment.database }

    init(book: Book, environment: AppEnvironment) {
        self.book = book
        self.environment = environment
        settings = ReaderSettingsStore.load()
        NotificationCenter.default.addObserver(
            self, selector: #selector(paletteDidChange),
            name: .highlightPaletteDidChange, object: nil
        )
    }

    @objc private func paletteDidChange() {
        highlightPalette = HighlightPaletteStore.load()
        drawHighlights()
    }

    var palette: ReaderSettings.Palette { settings.palette(systemDark: systemDark) }

    func setSystemDark(_ dark: Bool) {
        guard dark != systemDark else { return }
        systemDark = dark
        applySettings()
    }

    private func applySettings() {
        cancelReadingMovement()
        if let epub = navigator as? EPUBNavigatorViewController {
            epub.submitPreferences(settings.epubPreferences(systemDark: systemDark))
        } else if let pdf = navigator as? PDFNavigatorViewController {
            pdf.submitPreferences(settings.pdfPreferences(systemDark: systemDark))
        }
    }

    func load(startingAt reaction: BookReaction? = nil) async {
        guard case .loading = state, publication == nil else { return }
        do {
            let publication = try await ReadiumServices.shared.openPublication(
                at: environment.storage.url(for: book.fileName)
            )
            self.publication = publication

            let initialLocation: Locator?
            if let reaction, let target = try? Locator(jsonString: reaction.locator) {
                initialLocation = target
            } else {
                // Read the saved position fresh, in case it changed since the library listed this book.
                let saved = try await environment.database.book(id: book.id)?.locator
                initialLocation = saved.flatMap { try? Locator(jsonString: $0) }
            }

            let navigator: VisualNavigator & UIViewController
            if publication.conforms(to: .pdf) {
                navigator = try PDFNavigatorViewController(
                    publication: publication,
                    initialLocation: initialLocation,
                    config: .init(
                        preferences: settings.pdfPreferences(systemDark: systemDark),
                        editingActions: ReaderHostViewController.editingActions
                    ),
                    delegate: self
                )
            } else {
                let epub = try EPUBNavigatorViewController(
                    publication: publication,
                    initialLocation: initialLocation,
                    config: .init(
                        preferences: settings.epubPreferences(systemDark: systemDark),
                        editingActions: ReaderHostViewController.editingActions
                    )
                )
                epub.delegate = self
                navigator = epub
            }
            self.navigator = navigator
            state = .ready(ReaderHostViewController(navigator: navigator, actions: .init(
                isScrolling: { [weak self] in self?.settings.scroll ?? false },
                onTapCenter: { [weak self] in self?.chromeVisible.toggle() },
                // Like a Kindle, turning the page tucks the toolbars away.
                onPageTurn: { [weak self] in self?.chromeVisible = false },
                onReadingMovement: { [weak self] movement in self?.trackReadingMovement(movement) },
                onHighlightSelection: { [weak self] in self?.highlightSelection(openNote: false) },
                onNoteOnSelection: { [weak self] in self?.highlightSelection(openNote: true) },
                openPDFHighlight: { [weak self] point in self?.openPDFHighlight(at: point) ?? false }
            )))
            locator = initialLocation
            observeBookmarks()
            observeHighlights()
            try? await environment.database.markOpened(id: book.id)
            tableOfContents = (try? await publication.tableOfContents().get()) ?? []
            positionCount = try? await publication.positions().get().count
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    deinit {
        bookmarkObservation?.cancel()
        highlightObservation?.cancel()
        searchTask?.cancel()
    }

    // MARK: Search

    var isSearchable: Bool { publication?.isSearchable ?? false }

    func runSearch(_ query: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let publication else { return }
        searchTask?.cancel()
        clearSearchMarks()
        search = BookSearch(query: query, status: .searching)
        searchTask = Task { [weak self] in
            switch await publication.search(query: query) {
            case .failure(let error):
                self?.search.status = .failed(error.localizedDescription)
            case .success(let iterator):
                defer { iterator.close() }
                while !Task.isCancelled {
                    switch await iterator.next() {
                    case .success(let page?):
                        self?.search.append(page.locators)
                    case .success(nil):
                        self?.search.status = .done
                        return
                    case .failure(let error):
                        self?.search.status = .failed(error.localizedDescription)
                        return
                    }
                }
            }
        }
    }

    func go(toSearchResult locator: Locator) {
        search.selected = locator
        cancelReadingMovement()
        Task { _ = await navigator?.go(to: locator, options: .animated) }
        markSearchResult(locator)
    }

    func clearSearch() {
        searchTask?.cancel()
        search = BookSearch()
        clearSearchMarks()
    }

    /// EPUB: Readium draws a decoration. PDF: PDFKit marks every match of the query.
    private func markSearchResult(_ locator: Locator) {
        if let decorable = navigator as? DecorableNavigator {
            decorable.apply(
                decorations: [Decoration(id: "search", locator: locator, style: .highlight(tint: .systemYellow, isActive: true))],
                in: "search"
            )
        } else if let pdfView, let document = pdfView.document {
            pdfView.highlightedSelections = document.findString(search.query, withOptions: .caseInsensitive)
        }
    }

    private func clearSearchMarks() {
        (navigator as? DecorableNavigator)?.apply(decorations: [], in: "search")
        pdfView?.highlightedSelections = nil
    }

    // MARK: Navigation

    func go(to link: Link) {
        cancelReadingMovement()
        Task { _ = await navigator?.go(to: link, options: .animated) }
    }

    func go(to bookmark: Bookmark) {
        guard let locator = try? Locator(jsonString: bookmark.locator) else { return }
        cancelReadingMovement()
        Task { _ = await navigator?.go(to: locator, options: .animated) }
    }

    func go(to reaction: BookReaction) async -> Bool {
        guard reaction.bookId == book.id, let navigator,
              let target = try? Locator(jsonString: reaction.locator) else { return false }
        cancelReadingMovement()
        return await navigator.go(to: target, options: .animated)
    }

    func saveReactions(_ kinds: Set<ReactionKind>, at location: Locator) async throws {
        let title: String?
        if book.format == .pdf, let page = location.locations.position {
            title = "Page \(page)"
        } else {
            title = location.title
        }
        try await environment.database.addReactions(
            kinds, bookId: book.id, locator: location.jsonString(),
            progression: location.locations.totalProgression ?? 0, locationTitle: title
        )
    }

    /// Jumps to a point (0…1) through the whole book, e.g. from the slider.
    func go(toProgression progression: Double) {
        cancelReadingMovement()
        Task {
            guard let target = await publication?.locate(progression: progression) else { return }
            _ = await navigator?.go(to: target, options: .animated)
        }
    }

    func cancelReadingMovement() {
        readingMovement = nil
    }

    private func trackReadingMovement(_ movement: ReaderHostViewController.ReadingMovement) {
        switch movement {
        case .began:
            readingMovement = locator.map { ($0, nil) }
        case .completed:
            // A navigator can report its settled location after a swipe or page animation ends.
            readingMovement?.deadline = .now.advanced(by: .seconds(3))
            if let locator { checkReadingMovement(at: locator) }
        case .cancelled:
            cancelReadingMovement()
        }
    }

    private func checkReadingMovement(at destination: Locator) {
        guard let movement = readingMovement, let deadline = movement.deadline else { return }
        guard ContinuousClock.now <= deadline else {
            cancelReadingMovement()
            return
        }
        let origin = movement.origin
        let old = origin.locations
        let new = destination.locations
        let forward: Bool?
        if let start = old.totalProgression, let end = new.totalProgression, start != end {
            forward = end > start
        } else if let start = old.position, let end = new.position, start != end {
            forward = end > start
        } else if origin.href == destination.href,
                  let start = old.progression, let end = new.progression, start != end {
            forward = end > start
        } else {
            forward = nil
        }
        guard let forward else { return }
        cancelReadingMovement()
        if forward {
            Task { try? await environment.database.markReadingIfTBR(id: book.id) }
        }
    }

    /// The table of contents entry for the current chapter, to highlight it in the list.
    var currentChapterHref: String? {
        locator.map { $0.href.string }
    }

    // MARK: Bookmarks

    private func observeBookmarks() {
        let observation = environment.database.observeBookmarks(bookId: book.id)
        bookmarkObservation = Task { [weak self] in
            do {
                for try await bookmarks in observation { self?.bookmarks = bookmarks }
            } catch {}
        }
    }

    /// The bookmark on the page being read, if any.
    var currentBookmark: Bookmark? {
        guard let locator else { return nil }
        return bookmarks.first { bookmark in
            guard let saved = try? Locator(jsonString: bookmark.locator) else { return false }
            return Self.isSamePlace(saved, locator)
        }
    }

    /// Bookmarks match the page they were made on, not just the exact same character.
    nonisolated static func isSamePlace(_ a: Locator, _ b: Locator) -> Bool {
        guard a.href == b.href else { return false }
        if let pa = a.locations.progression, let pb = b.locations.progression {
            return abs(pa - pb) < 0.001
        }
        return a.locations.position == b.locations.position
    }

    func toggleBookmark() {
        if let existing = currentBookmark {
            Task { try? await environment.database.deleteBookmark(id: existing.id) }
            return
        }
        guard let locator, let json = try? locator.jsonString() else { return }
        let bookmark = Bookmark(
            id: UUID().uuidString,
            bookId: book.id,
            locator: json,
            progression: locator.locations.totalProgression ?? 0,
            title: locator.title,
            createdAt: Date()
        )
        Task { try? await environment.database.addBookmark(bookmark) }
    }

    func deleteBookmark(_ bookmark: Bookmark) {
        Task { try? await environment.database.deleteBookmark(id: bookmark.id) }
    }

    // MARK: Footer

    var chapterTitle: String? { locator?.title }

    var progression: Double { locator?.locations.totalProgression ?? 0 }

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
        checkReadingMovement(at: locator)
        save(locator)
    }

    func navigator(_ navigator: Navigator, didJumpTo locator: Locator) {
        cancelReadingMovement()
    }

    func navigator(_ navigator: PDFNavigatorViewController, setupPDFView view: PDFDocumentView) {
        pdfView = view
        // Highlights may have loaded before PDFKit's view existed.
        drawHighlights()
    }

    func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
        state = .failed(error.localizedDescription)
    }
}
