import SwiftUI

struct BookDiscoverySection: View {
    private let book: Book?
    private let catalogBook: DiscoveryBook?
    private let coverURL: URL?
    private let libraryBooks: [Book]
    private let onOpenBook: ((String) -> Void)?
    @EnvironmentObject private var environment: AppEnvironment
    @State private var discovery: BookDiscovery?
    @State private var loadedDiscoveryKey: String?
    @State private var destination: Destination?
    @State private var selectionAfterSeries: DiscoveryBook?
    private let coverWidth: CGFloat = 96

    init(book: Book, coverURL: URL?, libraryBooks: [Book], onOpenBook: @escaping (String) -> Void) {
        self.book = book
        catalogBook = nil
        self.coverURL = coverURL
        self.libraryBooks = libraryBooks
        self.onOpenBook = onOpenBook
    }

    init(catalogBook: DiscoveryBook) {
        book = nil
        self.catalogBook = catalogBook
        coverURL = nil
        libraryBooks = []
        onOpenBook = nil
    }

    private var language: String? {
        book.flatMap(BookDiscoveryClient.language(for:)) ?? BookDetailsText.languageCode(catalogBook?.language)
    }
    private var discoveryKey: String {
        "\(book?.hardcoverBookID ?? catalogBook?.id ?? 0)|\(book?.isbn ?? "")|\(language ?? "")"
    }

    private enum Destination: Identifiable {
        case series(DiscoverySeries)
        case preview(DiscoveryBook)

        var id: String {
            switch self {
            case .series(let series): "series-\(series.id)"
            case .preview(let book): "book-\(book.id)"
            }
        }
    }

    private var catalogSeries: [DiscoverySeries] { discovery?.series ?? [] }
    private var embeddedSeries: [BookSeries] {
        (book?.series ?? []).filter { membership in
            !membership.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !catalogSeries.contains { $0.name.localizedCaseInsensitiveCompare(membership.name) == .orderedSame }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !catalogSeries.isEmpty || !embeddedSeries.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    heading("In This Series")
                    ForEach(catalogSeries) { series in
                        seriesRow(series)
                    }
                    if let book {
                        ForEach(embeddedSeries, id: \.self) { series in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(BookDetailsText.series(series.name, position: series.position))
                                    .font(.subheadline.weight(.semibold))
                                coverTile(title: book.title, position: nil, current: true) {
                                    BookCoverView(book: book, coverURL: coverURL, showsPlaceholderTitle: false)
                                }
                            }
                        }
                    }
                }
                .detailsCard()
            }
            if let authorBooks = discovery?.authorBooks, !authorBooks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    heading("More by This Author")
                    coverStrip(authorBooks) { book in
                        relatedTile(book)
                    }
                }
                .detailsCard()
            }
        }
        .task(id: discoveryKey) {
            let key = discoveryKey
            guard loadedDiscoveryKey != key else { return }
            do {
                let result: BookDiscovery?
                if let catalogBook {
                    result = try await BookDiscoveryClient.discover(bookID: catalogBook.id, language: language)
                } else if let book {
                    result = try await BookDiscoveryClient.discover(for: book)
                } else {
                    return
                }
                if !Task.isCancelled, let result {
                    discovery = result
                    loadedDiscoveryKey = key
                }
            } catch {
                // Related books are optional when the catalog can't be reached.
            }
        }
        .sheet(item: $destination, onDismiss: openSelectionAfterSeries) { destination in
            switch destination {
            case .series(let series):
                DiscoverySeriesSheet(series: series, currentBookID: discovery?.bookID, language: language) { selected in
                    selectionAfterSeries = selected
                    self.destination = nil
                }
            case .preview(let book):
                DiscoveryBookPreview(book: book)
            }
        }
    }

    private func seriesRow(_ series: DiscoverySeries) -> some View {
        let currentEntry = series.entries.first { $0.id == discovery?.bookID }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(BookDetailsText.series(series.name, position: series.currentPosition ?? currentEntry?.position))
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                if series.nextOffset != nil {
                    Button("View Series") { destination = .series(series) }
                        .font(.caption.weight(.semibold))
                        .frame(minHeight: 44)
                }
            }
            if discovery != nil, currentEntry == nil {
                Text(series.currentPosition.map { "Current book: \(positionLabel($0))" } ?? "Current book in this series")
                    .font(.caption)
                    .foregroundStyle(AppPalette.secondaryText)
            }
            if !series.entries.isEmpty {
                coverStrip(series.entries) { entry in
                    relatedTile(entry.book, position: entry.position, current: entry.id == discovery?.bookID)
                }
            }
        }
    }

    private func coverStrip<Item: Identifiable, Tile: View>(
        _ items: [Item], @ViewBuilder tile: @escaping (Item) -> Tile
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(items, content: tile)
            }
            .padding(.bottom, 4)
        }
    }

    @ViewBuilder private func relatedTile(_ related: DiscoveryBook, position: Double? = nil, current: Bool = false) -> some View {
        let local = current ? book : related.libraryMatch(in: libraryBooks)
        let tile = coverTile(title: current ? (book?.title ?? catalogBook?.title ?? related.title) : related.title,
                             position: position, current: current) {
            if let local, let file = local.coverFileName,
               current || related.language == nil || related.language == BookDiscoveryClient.language(for: local) {
                BookCoverView(book: local, coverURL: environment.storage.url(for: file), showsPlaceholderTitle: false)
            } else {
                DiscoveryCover(book: current ? (catalogBook ?? related) : related, showsPlaceholderTitle: false)
            }
        }
        if current {
            tile
        } else {
            Button { open(related) } label: { tile }
                .buttonStyle(.plain)
        }
    }

    private func coverTile<Cover: View>(
        title: String, position: Double?, current: Bool, @ViewBuilder cover: () -> Cover
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            cover()
                .frame(width: coverWidth, height: coverWidth * 3 / 2)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(current ? AppPalette.accent : .clear, lineWidth: 2))
            if let position {
                Text(positionLabel(position)).font(.caption2).foregroundStyle(AppPalette.secondaryText)
            }
            if current {
                Text("Current book").font(.caption2.weight(.semibold)).foregroundStyle(AppPalette.accent)
            }
        }
        .frame(width: coverWidth, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue([position.map(positionLabel), current ? "Current book" : nil]
            .compactMap { $0 }.joined(separator: ", "))
    }

    private func heading(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppPalette.secondaryText)
            .accessibilityAddTraits(.isHeader)
    }

    private func open(_ related: DiscoveryBook) {
        if let onOpenBook, let local = related.libraryMatch(in: libraryBooks), local.id != book?.id {
            onOpenBook(local.id)
        } else {
            destination = .preview(related)
        }
    }

    private func openSelectionAfterSeries() {
        guard let selected = selectionAfterSeries else { return }
        selectionAfterSeries = nil
        open(selected)
    }
}

private func positionLabel(_ position: Double) -> String {
    "Book \(position.formatted(.number.grouping(.never)))"
}

private struct DiscoverySeriesSheet: View {
    let series: DiscoverySeries
    let currentBookID: Int?
    let language: String?
    let onSelect: (DiscoveryBook) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [DiscoverySeriesEntry]
    @State private var nextOffset: Int?
    @State private var loading = false
    @State private var loadFailed = false

    init(series: DiscoverySeries, currentBookID: Int?, language: String?, onSelect: @escaping (DiscoveryBook) -> Void) {
        self.series = series
        self.currentBookID = currentBookID
        self.language = language
        self.onSelect = onSelect
        _entries = State(initialValue: series.entries)
        _nextOffset = State(initialValue: series.nextOffset)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(entries) { entry in
                    if entry.id == currentBookID {
                        row(entry, current: true)
                    } else {
                        Button { onSelect(entry.book) } label: { row(entry, current: false) }
                            .buttonStyle(.plain)
                    }
                }
                if loading {
                    ProgressView()
                } else if nextOffset != nil {
                    if loadFailed {
                        Text("Couldn’t load more books.").foregroundStyle(AppPalette.secondaryText)
                    }
                    Button(loadFailed ? "Try Again" : "Load More") { Task { await loadMore() } }
                }
            }
            .navigationTitle(series.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .task { await loadMore() }
    }

    private func row(_ entry: DiscoverySeriesEntry, current: Bool) -> some View {
        HStack(spacing: 12) {
            DiscoveryCover(book: entry.book).frame(width: 44)
            VStack(alignment: .leading, spacing: 3) {
                if let position = entry.position { Text(positionLabel(position)).font(.caption) }
                Text(entry.book.title)
                if current {
                    Text("Current book").font(.caption.weight(.semibold)).foregroundStyle(AppPalette.accent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func loadMore() async {
        guard let offset = nextOffset, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await BookDiscoveryClient.seriesPage(
                id: series.id, offset: offset, currentBookID: currentBookID, language: language
            )
            var seen = Set(entries.map(\.id))
            entries.append(contentsOf: page.entries.filter { seen.insert($0.id).inserted })
            nextOffset = page.nextOffset
            loadFailed = false
        } catch {
            if !Task.isCancelled { loadFailed = true }
        }
    }
}

struct WishlistView: View {
    let query: String
    let sort: LibrarySort

    @EnvironmentObject private var environment: AppEnvironment
    @State private var books: [DiscoveryBook]?
    @State private var selectedBook: DiscoveryBook?
    @State private var loadFailed = false
    @State private var retry = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        Group {
            if loadFailed {
                VStack(spacing: 12) {
                    Text("Couldn’t load your wishlist.")
                    Button("Try Again") { retry.toggle() }
                        .buttonStyle(DetailsActionStyle())
                }
            } else if let books {
                if books.isEmpty {
                    VStack(spacing: 12) {
                        Label("Your wishlist is empty", systemImage: "bookmark")
                            .font(.headline)
                        Text("Save a book from Book Preview to find it here later.")
                            .foregroundStyle(AppPalette.secondaryText)
                    }
                    .multilineTextAlignment(.center)
                    .padding()
                } else {
                    let matches = visibleBooks(in: books)
                    ScrollView {
                        if matches.isEmpty {
                            Text("No books match “\(query)”.")
                                .foregroundStyle(AppPalette.secondaryText)
                                .padding(.top, 40)
                        }
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(matches) { book in
                                Button { selectedBook = book } label: {
                                    DiscoveryCover(book: book, showsPlaceholderTitle: false)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(book.author.isEmpty ? book.title : "\(book.title), by \(book.author)")
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $selectedBook) { book in
            DiscoveryBookPreview(book: book)
        }
        .task(id: retry) {
            loadFailed = false
            do {
                for try await savedBooks in environment.database.observeWishlist() {
                    books = savedBooks
                }
            } catch {
                if !Task.isCancelled { loadFailed = true }
            }
        }
    }

    private func visibleBooks(in books: [DiscoveryBook]) -> [DiscoveryBook] {
        let search = query.trimmingCharacters(in: .whitespaces)
        let matches = search.isEmpty ? books : books.filter {
            $0.title.localizedCaseInsensitiveContains(search) || $0.author.localizedCaseInsensitiveContains(search)
        }
        switch sort {
        case .recent, .added, .rating:
            return matches
        case .title:
            return matches.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .author:
            return matches.sorted {
                let comparison = $0.author.localizedStandardCompare($1.author)
                if comparison == .orderedSame {
                    return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
                return comparison == .orderedAscending
            }
        }
    }
}

struct WishlistImportReview: View {
    let suggestion: WishlistImportSuggestion
    let onResolve: (Int?) async throws -> Void

    @State private var selectedID: Int?
    @State private var resolving = false
    @State private var errorMessage: String?

    private var selection: Int? {
        suggestion.candidates.count == 1 ? suggestion.candidates.first?.id : selectedID
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(suggestion.candidates.count == 1
                         ? "Move this book from Wishlist to Library?"
                         : "Which Wishlist book matches your import?")
                        .font(.headline)
                    Text("Imported “\(suggestion.book.title)”")
                        .foregroundStyle(AppPalette.secondaryText)
                    ForEach(suggestion.candidates) { book in
                        Button {
                            selectedID = book.id
                        } label: {
                            HStack(spacing: 12) {
                                DiscoveryCover(book: book, showsPlaceholderTitle: false).frame(width: 44)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(book.title).font(.subheadline.weight(.semibold))
                                    if !book.author.isEmpty {
                                        Text(book.author).font(.caption).foregroundStyle(AppPalette.secondaryText)
                                    }
                                }
                                Spacer()
                                Image(systemName: selection == book.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(AppPalette.accent)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection == book.id ? .isSelected : [])
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(AppPalette.error)
                    }
                    Button("Move to Library") { resolve(selection) }
                        .buttonStyle(AppPrimaryButtonStyle())
                        .disabled(selection == nil)
                }
                .padding(20)
            }
            .navigationTitle("Wishlist Match")
            .navigationBarTitleDisplayMode(.inline)
            .background(AppPalette.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { resolve(nil) }
                }
            }
            .disabled(resolving)
        }
    }

    private func resolve(_ bookID: Int?) {
        resolving = true
        errorMessage = nil
        Task {
            defer { resolving = false }
            do {
                try await onResolve(bookID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct DiscoveryBookPreview: View {
    let book: DiscoveryBook
    var recommendationReason: String? = nil
    var likedRecommendation = false
    var onRecommendationFeedback: ((RecommendationFeedback) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var environment: AppEnvironment
    @State private var metadata: DiscoveryPreviewMetadata?
    @State private var fallbackSynopsis: String?
    @State private var isSaved: Bool?
    @State private var updatingWishlist = false
    @State private var wishlistError: String?
    @State private var liked = false

    private var synopsis: String? { fallbackSynopsis ?? BookDetailsText.previewSynopsis(book.description) }
    private var language: String? {
        BookDetailsText.languageCode(book.language) ?? BookDetailsText.languageCode(metadata?.language)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        DiscoveryCover(book: book).frame(width: 96)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(book.title).font(.title3.weight(.semibold))
                            if !book.author.isEmpty { Text(book.author).foregroundStyle(AppPalette.secondaryText) }
                            wishlistButton
                        }
                    }
                    if let recommendationReason {
                        section("Why this pick?") {
                            Text(recommendationReason).font(.subheadline)
                        }
                    }
                    if let synopsis {
                        section("Description") {
                            Text(synopsis).font(.subheadline).lineSpacing(4).textSelection(.enabled)
                        }
                    }
                    if let metadata, let genres = SubjectGenreMapping.classifyHardcover(metadata.genres)?.genres {
                        tagSection("Genres", tags: genres.map(\.displayName))
                    }
                    let moods = BookDetailsText.hardcoverMoods(metadata?.moods ?? [])
                    if !moods.isEmpty {
                        tagSection("Moods", tags: moods.map { $0.lowercased() })
                    }
                    if metadata?.releaseYear != nil || language != nil || metadata?.rating != nil {
                        section("Metadata") {
                            if let year = metadata?.releaseYear {
                                metadataRow("Release Year", value: String(year))
                            }
                            if let language {
                                metadataRow("Language", value: Locale.current.localizedString(forLanguageCode: language) ?? language)
                            }
                            if let rating = metadata?.rating, let count = metadata?.ratingsCount, count > 0 {
                                hardcoverRatingRow(rating, count: count)
                            }
                        }
                    }
                    BookDiscoverySection(catalogBook: book)
                    Link(destination: book.sourceURL) {
                        Label("View on Hardcover", systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DetailsActionStyle())
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .clipped()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let onRecommendationFeedback {
                    feedbackBar(onRecommendationFeedback)
                }
            }
            .background(AppPalette.background)
            .navigationTitle("Book Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .alert("Wishlist", isPresented: Binding(
                get: { wishlistError != nil },
                set: { if !$0 { wishlistError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(wishlistError ?? "")
            }
        }
        .onAppear { liked = likedRecommendation }
        .task { await updateWishlist() }
        .task(id: book.id) {
            let fetched = try? await BookDiscoveryClient.preview(for: book.id)
            guard !Task.isCancelled else { return }
            metadata = fetched
            if synopsis == nil, onRecommendationFeedback != nil,
               let isbn = book.isbns.first,
               let details = try? await HardcoverClient.shared.metadata(matchingISBN: isbn),
               details.bookID == book.id, !Task.isCancelled {
                fallbackSynopsis = BookDetailsText.previewSynopsis(details.description)
            }
            if synopsis == nil, let language, !Task.isCancelled {
                let fallback = try? await OpenLibraryClient.shared.previewSynopsis(for: book, language: language)
                if !Task.isCancelled { fallbackSynopsis = fallback }
            }
        }
    }

    private func feedbackBar(_ onFeedback: @escaping (RecommendationFeedback) -> Void) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                feedbackButtons(onFeedback, stacked: true)
            }
            VStack(spacing: 0) {
                feedbackButtons(onFeedback, stacked: false)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(AppPalette.surface, ignoresSafeAreaEdges: .bottom)
        .overlay(alignment: .top) { Divider() }
    }

    private func feedbackButtons(_ onFeedback: @escaping (RecommendationFeedback) -> Void, stacked: Bool) -> some View {
        ForEach(RecommendationFeedback.allCases, id: \.self) { action in
            let selected = action == .moreLikeThis && liked
            Button {
                if action == .moreLikeThis { liked.toggle() }
                onFeedback(action)
            } label: {
                let layout = stacked ? AnyLayout(VStackLayout(spacing: 5)) : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    Image(systemName: selected ? "hand.thumbsup.fill" : action.symbol)
                        .font(.body.weight(.semibold))
                        .overlay(alignment: .bottomTrailing) {
                            if action == .alreadyRead {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .background(AppPalette.surface, in: Circle())
                                    .offset(x: 3, y: 2)
                            }
                        }
                    Text(action.label)
                        .font(.caption.weight(.semibold))
                }
                .fixedSize(horizontal: stacked, vertical: false)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
                .foregroundStyle(selected ? AppPalette.accent : AppPalette.text)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("discover-feedback-\(action.rawValue)")
        }
    }

    private var wishlistButton: some View {
        Button {
            Task { await updateWishlist(saved: isSaved.map { !$0 }) }
        } label: {
            Label(isSaved == true ? "Saved" : "Save to Wishlist",
                  systemImage: isSaved == true ? "bookmark.fill" : "bookmark")
                .multilineTextAlignment(.leading)
                .padding(.vertical, 4)
        }
        .buttonStyle(DetailsActionStyle())
        .disabled(updatingWishlist)
        .accessibilityHint(isSaved == true ? "Removes this book from your wishlist" : "Adds this book to your wishlist")
    }

    private func updateWishlist(saved: Bool? = nil) async {
        guard !updatingWishlist else { return }
        updatingWishlist = true
        defer { updatingWishlist = false }
        do {
            if let saved {
                try await environment.database.setWishlisted(book, saved: saved)
                isSaved = saved
            } else {
                isSaved = try await environment.database.isWishlisted(book.id)
            }
        } catch {
            if !Task.isCancelled {
                wishlistError = saved == nil ? "Couldn’t check if this book is saved." : "Couldn’t update your wishlist."
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.caption.weight(.semibold))
                .foregroundStyle(AppPalette.secondaryText)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .detailsCard()
    }

    private func tagSection(_ title: String, tags: [String]) -> some View {
        section(title) {
            DetailsFlowLayout(spacing: 8) {
                ForEach(Array(Set(tags)).sorted(), id: \.self) { detailChip($0) }
            }
        }
    }
}

struct DiscoveryCover: View {
    let book: DiscoveryBook
    var showsPlaceholderTitle = true
    @State private var sourceIndex = 0

    var body: some View {
        let sources = book.coverSources
        let index = sourceIndex
        Color.clear
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                if sources.indices.contains(index) {
                    let url = sources[index]
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        case .failure:
                            placeholder.task {
                                if sourceIndex == index { sourceIndex = index + 1 }
                            }
                        default: placeholder
                        }
                    }
                    .id(url)
                } else {
                    placeholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .accessibilityHidden(true)
            .onChange(of: sources) { _ in sourceIndex = 0 }
    }

    private var placeholder: some View {
        Group {
            if showsPlaceholderTitle {
                Text(book.title).font(.caption.weight(.semibold)).lineLimit(4).padding(8)
            } else {
                Image(systemName: "book.closed").foregroundStyle(AppPalette.secondaryText)
            }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppPalette.secondarySurface)
    }
}
