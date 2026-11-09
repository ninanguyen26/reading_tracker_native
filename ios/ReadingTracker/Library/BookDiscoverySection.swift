import SwiftUI

struct BookDiscoverySection: View {
    let book: Book
    let coverURL: URL?
    let libraryBooks: [Book]
    let onOpenBook: (String) -> Void
    @EnvironmentObject private var environment: AppEnvironment
    @State private var discovery: BookDiscovery?
    @State private var loadedDiscoveryKey: String?
    @State private var destination: Destination?
    @State private var selectionAfterSeries: DiscoveryBook?
    private let coverWidth: CGFloat = 96

    private var language: String? { BookDiscoveryClient.language(for: book) }
    private var discoveryKey: String { "\(book.hardcoverBookID ?? 0)|\(book.isbn ?? "")|\(language ?? "")" }

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
        book.series.filter { membership in
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
            if let result = try? await BookDiscoveryClient.discover(for: book), !Task.isCancelled {
                discovery = result
                loadedDiscoveryKey = key
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
        let tile = coverTile(title: current ? book.title : related.title, position: position, current: current) {
            if let local, let file = local.coverFileName,
               current || related.language == nil || related.language == BookDiscoveryClient.language(for: local) {
                BookCoverView(book: local, coverURL: environment.storage.url(for: file), showsPlaceholderTitle: false)
            } else {
                DiscoveryCover(book: related, showsPlaceholderTitle: false)
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
        if let local = related.libraryMatch(in: libraryBooks), local.id != book.id {
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

private struct DiscoveryBookPreview: View {
    let book: DiscoveryBook
    @Environment(\.dismiss) private var dismiss
    @State private var metadata: DiscoveryPreviewMetadata?
    @State private var fallbackSynopsis: String?

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
                    if let moods = metadata?.moods, !moods.isEmpty {
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
                    Link(destination: book.sourceURL) {
                        Label("View on Hardcover", systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DetailsActionStyle())
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AppPalette.background)
            .navigationTitle("Book Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .task(id: book.id) {
            let fetched = try? await BookDiscoveryClient.preview(for: book.id)
            guard !Task.isCancelled else { return }
            metadata = fetched
            if synopsis == nil, let language {
                let fallback = try? await OpenLibraryClient.shared.previewSynopsis(for: book, language: language)
                if !Task.isCancelled { fallbackSynopsis = fallback }
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

private struct DiscoveryCover: View {
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
