import SwiftUI

struct ReaderScreen: View {
    @StateObject private var model: ReaderModel
    private let coverURL: URL?
    @Environment(\.colorScheme) private var colorScheme
    @State private var sheet: Sheet?
    /// While dragging the slider, the position it would jump to.
    @State private var scrubbing: Double?
    @State private var scrubCommit: Task<Void, Never>?

    enum Sheet: Identifiable {
        case settings, navigation, search, details
        var id: Self { self }
    }

    init(book: Book, environment: AppEnvironment) {
        _model = StateObject(wrappedValue: ReaderModel(book: book, environment: environment))
        coverURL = book.coverFileName.map(environment.storage.url(for:))
    }

    private var palette: ReaderSettings.Palette { model.palette }

    var body: some View {
        ZStack {
            (model.book.format == .pdf ? palette.surround : palette.background).ignoresSafeArea()
            switch model.state {
            case .loading:
                ProgressView()
            case .failed(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text(message)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(palette.secondaryText)
                .padding(32)
            case .ready(let viewController):
                // The book fills the screen; the toolbars float over it, so
                // showing or hiding them never reflows the page.
                ReaderContainer(viewController: viewController)
                    .ignoresSafeArea()
                    .accessibilityIdentifier("reader-content")
            }
        }
        .overlay(alignment: .top) {
            // The navigation bar is translucent; a frosted band behind it keeps
            // the title readable over the page.
            if model.chromeVisible {
                Color.clear
                    .frame(height: 0)
                    .background(.bar, ignoresSafeAreaEdges: .top)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            // After opening a search result, a chip leads back to the results.
            if model.search.selected != nil && sheet == nil {
                searchChip
                    .padding(.top, model.chromeVisible ? 8 : 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if model.chromeVisible, case .ready = model.state {
                bottomBar.transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                footer
            }
        }
        .navigationTitle(model.book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { sheet = .details } label: {
                    Label("Book Details", systemImage: "info.circle")
                }
                Button { sheet = .search } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .disabled(!model.isSearchable)
                Button { sheet = .navigation } label: {
                    Label("Contents and Bookmarks", systemImage: "list.bullet")
                }
                Button { sheet = .settings } label: {
                    Label("Reading Settings", systemImage: "textformat.size")
                }
                Button { model.toggleBookmark() } label: {
                    Label(
                        model.currentBookmark == nil ? "Add Bookmark" : "Remove Bookmark",
                        systemImage: model.currentBookmark == nil ? "bookmark" : "bookmark.fill"
                    )
                }
                .disabled(model.locator == nil)
            }
        }
        .toolbar(model.chromeVisible ? .visible : .hidden, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(palette.isDark ? .dark : .light, for: .navigationBar)
        .statusBarHidden(!model.chromeVisible)
        .animation(.easeInOut(duration: 0.2), value: model.chromeVisible)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .settings:
                ReaderSettingsSheet(settings: $model.settings, format: model.book.format)
            case .navigation:
                NavigationSheet(model: model)
            case .search:
                SearchSheet(model: model)
            case .details:
                BookDetailsScreen(
                    book: model.book,
                    coverURL: coverURL
                )
            }
        }
        .task {
            model.setSystemDark(colorScheme == .dark)
            await model.load()
        }
        .onChange(of: colorScheme) { model.setSystemDark($0 == .dark) }
    }

    private var searchChip: some View {
        HStack(spacing: 0) {
            Button { sheet = .search } label: {
                Label("Results for “\(model.search.query)”", systemImage: "magnifyingglass")
                    .font(.footnote.weight(.medium))
                    .padding(.leading, 12)
                    .padding(.vertical, 8)
            }
            Button { model.clearSearch() } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .padding(10)
            }
            .accessibilityLabel("Clear Search")
        }
        .foregroundStyle(.primary)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .environment(\.colorScheme, palette.isDark ? .dark : .light)
    }

    /// Shown with the toolbar: a slider to move through the book.
    private var bottomBar: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(get: { scrubbing ?? model.progression }, set: { scrub(to: $0) }),
                in: 0...1
            ) { editing in
                if !editing { commitScrub() }
            }
            .accessibilityLabel("Position in book")
            .accessibilityIdentifier("position-slider")
            HStack {
                Text(model.chapterTitle ?? "").lineLimit(1)
                Spacer(minLength: 8)
                Text(scrubbing.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? model.progressLabel)
                    .monospacedDigit()
                    .accessibilityIdentifier("reader-progress")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background(.bar, ignoresSafeAreaEdges: .bottom)
        .environment(\.colorScheme, palette.isDark ? .dark : .light)
    }

    /// Jumps once the slider settles. Not every way of moving a slider ends with
    /// an editing callback (VoiceOver adjustments, for one), so a short pause counts too.
    private func scrub(to value: Double) {
        scrubbing = value
        scrubCommit?.cancel()
        scrubCommit = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            if !Task.isCancelled { commitScrub() }
        }
    }

    private func commitScrub() {
        scrubCommit?.cancel()
        guard let target = scrubbing else { return }
        model.go(toProgression: target)
        scrubbing = nil
    }

    /// Always-visible position line, like a Kindle's footer.
    private var footer: some View {
        HStack(spacing: 12) {
            Text(model.chapterTitle ?? "")
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(model.progressLabel)
                .monospacedDigit()
                .accessibilityIdentifier("reader-progress")
        }
        .font(.caption2)
        .foregroundStyle(palette.secondaryText)
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
        .allowsHitTesting(false)
    }
}
