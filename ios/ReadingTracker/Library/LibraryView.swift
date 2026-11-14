import SwiftUI
import UniformTypeIdentifiers

private enum LibraryLayout: String, CaseIterable {
    case grid = "Grid"
    case card = "Card"
}

struct LibraryView: View {
    @ObservedObject var model: LibraryModel
    @AppStorage("library-layout") private var layout: LibraryLayout = .grid
    @State private var showingImporter = false
    @State private var showingWishlistReview = false
    @State private var selectedTab: AppTab = .library
    @FocusState private var searchFocused: Bool
    @State private var bookToDelete: Book?
    @State private var finishedBook: Book?
    @State private var bookToReview: Book?
    @State private var shelfToDelete: Shelf?
    @State private var shelfNaming: ShelfNaming?
    @State private var shelfName = ""
    @State private var selecting = false
    @State private var selectedBookIds: Set<String> = []
    @State private var confirmingBulkDelete = false
    @State private var reactionJump: BookReaction?
    // Navigate by ID: a Book value changes as soon as it's opened (progress,
    // last-opened date), which SwiftUI would treat as a different destination.
    @State private var path: [Route] = []

    private enum Route: Hashable {
        case reader(String, initialReaction: BookReaction? = nil)
        case details(String, fromReader: Bool)
        case genre(BookGenre)
    }

    private enum ShelfNaming {
        case create(adding: [Book])
        case rename(Shelf)

        var title: String {
            switch self {
            case .create: "New Shelf"
            case .rename: "Rename Shelf"
            }
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 20, alignment: .top)]

    private var libraryColumns: [GridItem] {
        layout == .card ? [GridItem(.flexible())] : columns
    }

    private var canReviewWishlistMatches: Bool {
        !model.wishlistSuggestions.isEmpty && path.isEmpty && !showingImporter &&
            finishedBook == nil && bookToReview == nil && model.errorMessage == nil
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                if selectedTab == .home {
                    Text("Home")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("home-title")
                }
                rootContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                if selecting {
                    selectionBar
                } else {
                    AppNavigationBar(selection: $selectedTab) {
                        searchFocused = false
                        showingImporter = true
                    }
                }
            }
            .background(AppPalette.background)
            .foregroundStyle(AppPalette.text)
            .toolbarBackground(AppPalette.background, for: .navigationBar)
            .navigationTitle(selecting ? "\(selectedBooks.count) Selected" : selectedTab.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(selectedTab == .home ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                if selectedTab == .library && model.filter != .wishlist && !model.books.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(selecting ? "Done" : "Select") {
                            searchFocused = false
                            selectedBookIds = []
                            selecting.toggle()
                        }
                    }
                }
                if selecting {
                    ToolbarItem(placement: .topBarLeading) {
                        let allSelected = selectedBooks.count == model.visibleBooks.count && !selectedBooks.isEmpty
                        Button(allSelected ? "Deselect All" : "Select All") {
                            selectedBookIds = allSelected ? [] : Set(model.visibleBooks.map(\.id))
                        }
                    }
                }
            }
            .navigationDestination(for: Route.self, destination: destination)
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.epub, .pdf],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls): model.importFiles(urls)
                case .failure(let error): model.errorMessage = error.localizedDescription
                }
            }
            .confirmationDialog(
                "Delete “\(bookToDelete?.title ?? "")”?",
                isPresented: Binding(get: { bookToDelete != nil }, set: { if !$0 { bookToDelete = nil } }),
                titleVisibility: .visible,
                presenting: bookToDelete
            ) { book in
                Button("Delete Book", role: .destructive) { model.delete(book) }
            } message: { _ in
                Text("The book and your reading position will be removed from this device.")
            }
            .confirmationDialog(
                "Delete \(bookCount(selectedBooks.count))?",
                isPresented: $confirmingBulkDelete,
                titleVisibility: .visible
            ) {
                Button("Delete \(bookCount(selectedBooks.count))", role: .destructive) {
                    model.delete(selectedBooks)
                    endSelecting()
                }
            } message: {
                Text("These books and your reading positions will be removed from this device.")
            }
            .confirmationDialog(
                "Delete the “\(shelfToDelete?.name ?? "")” shelf?",
                isPresented: Binding(get: { shelfToDelete != nil }, set: { if !$0 { shelfToDelete = nil } }),
                titleVisibility: .visible,
                presenting: shelfToDelete
            ) { shelf in
                Button("Delete Shelf", role: .destructive) { model.delete(shelf) }
            } message: { _ in
                Text("Its books stay in your library.")
            }
            .alert(
                shelfNaming?.title ?? "",
                isPresented: Binding(get: { shelfNaming != nil }, set: { if !$0 { shelfNaming = nil } })
            ) {
                TextField("Shelf name", text: $shelfName)
                Button("Cancel", role: .cancel) {}
                Button("Save") { saveShelfName() }
                    .disabled(Shelf.cleanName(shelfName).isEmpty)
            }
            .alert(
                "Something went wrong",
                isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
            .personalReview(finishedBook: $finishedBook, bookToReview: $bookToReview)
            .onChange(of: canReviewWishlistMatches) { showingWishlistReview = $0 }
            .sheet(isPresented: $showingWishlistReview) {
                if let suggestion = model.wishlistSuggestions.first {
                    WishlistImportReview(suggestion: suggestion) { savedBookID in
                        try await model.resolveWishlistSuggestion(suggestion, savedBookID: savedBookID)
                    }
                    .id(suggestion.id)
                    .interactiveDismissDisabled()
                }
            }
        }
    }

    @ViewBuilder private func destination(_ route: Route) -> some View {
        switch route {
        case .reader(let id, let initialReaction):
            if let book = model.books.first(where: { $0.id == id }) {
                ReaderScreen(book: book, environment: model.environment, initialReaction: initialReaction,
                             reactionJump: Binding(
                                get: { path.last == route ? reactionJump : nil },
                                set: { reactionJump = $0 }
                             )) {
                    path.append(.details(book.id, fromReader: true))
                }
                .id(book.id)
            }
        case .details(let id, let fromReader):
            if let book = model.books.first(where: { $0.id == id }) {
                BookDetailsScreen(book: book, coverURL: model.coverURL(for: book),
                                  fromReader: fromReader, libraryBooks: model.books) {
                    guard path.last == route else { return }
                    if fromReader {
                        path.removeLast()
                    } else {
                        path[path.count - 1] = .reader(book.id)
                    }
                } onDeleted: {
                    selectedTab = .library
                    path.removeAll()
                } onOpenBook: { id in
                    path.append(.details(id, fromReader: false))
                } onOpenGenre: { genre in
                    path.append(.genre(genre))
                } onOpenReaction: { reaction in
                    guard path.last == route else { return }
                    if fromReader {
                        reactionJump = reaction
                        path.removeLast()
                    } else {
                        path.append(.reader(book.id, initialReaction: reaction))
                    }
                }
            }
        case .genre(let genre):
            genreBooks(genre)
        }
    }

    private struct GenreResults<Content: View>: View {
        @State private var query = ""
        @FocusState private var searchFocused: Bool
        @ViewBuilder let content: (Binding<String>, FocusState<Bool>.Binding) -> Content

        var body: some View {
            content($query, $searchFocused)
        }
    }

    private func genreBooks(_ genre: BookGenre) -> some View {
        GenreResults { query, focus in
            let books = model.books.filter { $0.genres.contains(genre) }
            let matches = books.matching(query.wrappedValue).sorted(by: model.sort)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    searchField(query: query, focus: focus)
                    sortMenu(isWishlist: false, disabled: books.isEmpty)
                }
                .modifier(LibrarySearchRowSpacing())

                ScrollView {
                    if matches.isEmpty {
                        Text(books.isEmpty ? "No books in this genre." : "No books match “\(query.wrappedValue)”.")
                            .foregroundStyle(AppPalette.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                    bookResults(matches, allowsSelection: false)
                }
                .scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("genre-results")
            }
        }
        .background(AppPalette.background)
        .foregroundStyle(AppPalette.text)
        .toolbarBackground(AppPalette.background, for: .navigationBar)
        .navigationTitle(genre.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func bookResults(_ books: [Book], allowsSelection: Bool) -> some View {
        let isSelecting = allowsSelection && selecting
        return LazyVGrid(columns: libraryColumns, spacing: layout == .card ? 12 : 28) {
            ForEach(books) { book in
                if layout == .card {
                    bookCard(book, isSelecting: isSelecting)
                } else if isSelecting {
                    selectableBook(book)
                } else {
                    bookLink(book)
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 24)
    }

    @ViewBuilder private var rootContent: some View {
        switch selectedTab {
        case .library:
            VStack(spacing: 0) {
                librarySearch
                if model.filter == .wishlist {
                    importStatus
                    WishlistView(query: model.query, sort: model.sort)
                } else if model.loaded && model.books.isEmpty {
                    EmptyLibraryView { showingImporter = true }
                } else {
                    shelfBar
                    ScrollView {
                        importStatus
                        if model.activeShelf != nil && model.booksOnActiveShelf.isEmpty {
                            Text(layout == .card
                                 ? "No books on this shelf yet. Use a book’s three-dot menu to add it."
                                 : "No books on this shelf yet. Touch and hold a book to add it.")
                                .foregroundStyle(AppPalette.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                                .padding(.top, 40)
                        } else if model.genreFilter != .all && model.visibleBooks.isEmpty {
                            Text("No books match this genre filter.")
                                .foregroundStyle(AppPalette.secondaryText)
                                .padding(.top, 40)
                        } else if !model.query.isEmpty && model.visibleBooks.isEmpty {
                            Text("No books match “\(model.query)”.")
                                .foregroundStyle(AppPalette.secondaryText)
                                .padding(.top, 40)
                        } else if let status = model.readingStatusFilter, model.visibleBooks.isEmpty {
                            Text("No books with the \(status.label) status.")
                                .foregroundStyle(AppPalette.secondaryText)
                                .padding(.top, 40)
                        }
                        bookResults(model.visibleBooks, allowsSelection: true)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .accessibilityIdentifier("library-scroll")
                }
            }
        case .home:
            homeContent
        case .stats:
            LibraryStatsView(books: model.books)
        case .settings:
            AppSettingsView()
        }
    }

    private var homeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                importStatus
                if let book = model.books.filter({ $0.readingStatus == .reading }).sorted(by: .recent).first {
                    Text("Continue Reading")
                        .font(.system(.title2, design: .serif).weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    NavigationLink(value: Route.reader(book.id)) {
                        HStack(spacing: 14) {
                            BookCoverView(book: book, coverURL: model.coverURL(for: book), showsPlaceholderTitle: false)
                                .frame(width: 72)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(book.title)
                                    .font(.headline)
                                Text(book.author)
                                    .font(.subheadline)
                                    .foregroundStyle(AppPalette.secondaryText)
                                Text(book.progression.formatted(.percent.precision(.fractionLength(0))) + " read")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(AppPalette.secondaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppPalette.secondaryText)
                        }
                        .padding(12)
                        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("book-\(book.title)")
                } else if model.loaded && model.importing.isEmpty {
                    if model.books.isEmpty {
                        EmptyLibraryView { showingImporter = true }
                    } else {
                        Text("Nothing in progress")
                            .font(.system(.title2, design: .serif).weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        Button("Browse Library") { selectedTab = .library }
                            .buttonStyle(AppPrimaryButtonStyle())
                    }
                }
                if model.loaded {
                    HomeDiscoverSection(library: model.books)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .accessibilityIdentifier("home-scroll")
    }

    private var filterMenu: some View {
        Menu {
            filterOption(.all)
            ForEach(ReadingStatus.allCases) { status in
                filterOption(.status(status))
            }
            Divider()
            filterOption(.wishlist)
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.title3)
                .frame(width: 48, height: 48)
                .foregroundStyle(model.filter == .all ? Color.primary : AppPalette.accent)
                .modifier(LibraryControlSurface())
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Filter books")
        .accessibilityValue(model.filter.label)
    }

    private func filterOption(_ filter: LibraryFilter) -> some View {
        Button {
            searchFocused = false
            if filter == .wishlist && selecting { endSelecting() }
            model.filter = filter
        } label: {
            if model.filter == filter {
                Label(filter.label, systemImage: "checkmark")
            } else {
                Text(filter.label)
            }
        }
    }

    private var librarySearch: some View {
        HStack(spacing: 12) {
            searchField(query: $model.query, focus: $searchFocused)
            filterMenu
            let isWishlist = model.filter == .wishlist
            sortMenu(isWishlist: isWishlist, disabled: !isWishlist && model.books.isEmpty)
        }
        .modifier(LibrarySearchRowSpacing())
    }

    private func searchField(query: Binding<String>, focus: FocusState<Bool>.Binding) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Title or author", text: query)
                .focused(focus)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { focus.wrappedValue = false }
                .accessibilityIdentifier("library-search")
            if !query.wrappedValue.isEmpty {
                Button { query.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .foregroundStyle(.primary)
        .modifier(LibraryControlSurface())
    }

    private func sortMenu(isWishlist: Bool, disabled: Bool) -> some View {
        let sortOptions = LibrarySort.allCases.filter { !isWishlist || ($0 != .recent && $0 != .rating) }
        let sortSelection = Binding(
            get: { sortOptions.contains(model.sort) ? model.sort : .added },
            set: { model.sort = $0 }
        )
        return Menu {
            Picker("Sort By", selection: sortSelection) {
                ForEach(sortOptions) { sort in
                    Text(isWishlist && sort == .added ? "Recently Saved" : sort.label).tag(sort)
                }
            }
            if !isWishlist {
                Divider()
                ForEach(LibraryLayout.allCases, id: \.self) { option in
                    Button {
                        layout = option
                    } label: {
                        if layout == option {
                            Label(option.rawValue, systemImage: "checkmark")
                        } else {
                            Text(option.rawValue)
                        }
                    }
                    .accessibilityAddTraits(layout == option ? .isSelected : [])
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.title3)
                .frame(width: 48, height: 48)
                .foregroundStyle(.primary)
                .modifier(LibraryControlSurface())
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Sort")
        .disabled(disabled)
    }

    private var genreMenu: some View {
        let counts = model.genreCounts
        let selected = model.genreFilter
        let isFiltered = selected != .all
        let genres = BookGenre.allCases
            .map(LibraryGenreFilter.genre)
            .filter { counts[$0] != nil || $0 == selected }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }

        return Menu {
            Picker("Genres", selection: $model.genreFilter) {
                Text("All Genres (\(counts[.all, default: 0].formatted()))").tag(LibraryGenreFilter.all)
                ForEach(genres, id: \.self) { genre in
                    Text("\(genre.label) (\(counts[genre, default: 0].formatted()))").tag(genre)
                }
                if counts[.unclassified] != nil || selected == .unclassified {
                    Text("\(LibraryGenreFilter.unclassified.label) (\(counts[.unclassified, default: 0].formatted()))")
                        .tag(LibraryGenreFilter.unclassified)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 5) {
                Text(isFiltered ? selected.label : "Genres")
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Genres")
        .accessibilityValue(selected.label)
        .accessibilityIdentifier("library-genres")
        .font(.footnote.weight(.medium))
        .foregroundStyle(isFiltered ? AppPalette.onAccent : AppPalette.text)
        .background {
            Capsule()
                .fill(isFiltered ? AppPalette.accent : AppPalette.surface)
                .overlay(Capsule().strokeBorder(isFiltered ? Color.clear : AppPalette.border))
                .frame(height: 34)
        }
    }

    /// Filters the library by genre and shelf, with ways to manage shelves.
    private var shelfBar: some View {
        HStack(spacing: 8) {
            genreMenu
                .padding(.leading)
            Rectangle()
                .fill(AppPalette.border)
                .frame(width: 1, height: 17)
                .accessibilityHidden(true)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    shelfChip("All Books", count: model.books.count, id: "all", selected: model.activeShelf == nil) {
                        model.select(nil)
                    }
                    ForEach(model.shelfList.shelves) { shelf in
                        shelfChip(shelf.name, count: model.shelfList.count(on: shelf.id), id: shelf.name, selected: model.activeShelf == shelf) {
                            model.select(shelf)
                        }
                    }
                    Button { nameShelf(.create(adding: [])) } label: {
                        Label("New Shelf", systemImage: "plus")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AppPalette.secondaryText)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                            .overlay(Capsule().strokeBorder(AppPalette.border, style: StrokeStyle(lineWidth: 1, dash: [4])))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.trailing)
                .padding(.vertical, 1)
            }
            if let shelf = model.activeShelf {
                Menu {
                    Button { nameShelf(.rename(shelf)) } label: {
                        Label("Rename Shelf", systemImage: "pencil")
                    }
                    Button(role: .destructive) { shelfToDelete = shelf } label: {
                        Label("Delete Shelf", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 34, height: 34)
                        .foregroundStyle(.primary)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Shelf Options")
                .padding(.trailing)
            }
        }
        .padding(.bottom, 14)
    }

    private func shelfChip(_ title: String, count: Int, id: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title).lineLimit(1)
                Text(count.formatted()).monospacedDigit().opacity(0.7)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(selected ? AppPalette.onAccent : AppPalette.text)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(selected ? AppPalette.accent : AppPalette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.clear : AppPalette.border))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(count) \(count == 1 ? "book" : "books")")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("shelf-\(id)")
    }

    private func nameShelf(_ naming: ShelfNaming) {
        searchFocused = false
        if case .rename(let shelf) = naming { shelfName = shelf.name } else { shelfName = "" }
        shelfNaming = naming
    }

    private func saveShelfName() {
        switch shelfNaming {
        case .create(let books):
            model.createShelf(named: shelfName, adding: books)
            if selecting && !books.isEmpty { endSelecting() }
        case .rename(let shelf): model.rename(shelf, to: shelfName)
        case nil: break
        }
    }

    /// Only books still in view count, so a search or shelf change can't act on books you can't see.
    private var selectedBooks: [Book] {
        model.visibleBooks.filter { selectedBookIds.contains($0.id) }
    }

    private func bookCount(_ count: Int) -> String {
        count == 1 ? "1 Book" : "\(count) Books"
    }

    private func endSelecting() {
        selecting = false
        selectedBookIds = []
    }

    private func selectableBook(_ book: Book, layout: LibraryLayout = .grid) -> some View {
        let selected = selectedBookIds.contains(book.id)
        return Button {
            if selected { selectedBookIds.remove(book.id) } else { selectedBookIds.insert(book.id) }
        } label: {
            BookCell(book: book, coverURL: model.coverURL(for: book), layout: layout, selected: selected)
        }
        .buttonStyle(.plain)
    }

    /// Replaces the tab bar while selecting books.
    private var selectionBar: some View {
        let books = selectedBooks
        return HStack(spacing: 0) {
            Menu {
                ReadingStatusOptions { status in
                    model.setReadingStatus(status, for: books) { finishedBook = $0 }
                    endSelecting()
                }
            } label: {
                selectionAction("Change Status", systemImage: "checklist")
            }
            Menu {
                ForEach(model.shelfList.shelves) { shelf in
                    Button(shelf.name) {
                        model.add(books, to: shelf)
                        endSelecting()
                    }
                }
                Button { nameShelf(.create(adding: books)) } label: {
                    Label("New Shelf…", systemImage: "plus")
                }
            } label: {
                selectionAction("Add to Shelf", systemImage: "books.vertical")
            }
            if let shelf = model.activeShelf {
                Button {
                    model.remove(books, from: shelf)
                    endSelecting()
                } label: {
                    selectionAction("Remove from Shelf", systemImage: "minus.circle")
                }
            }
            Button(role: .destructive) { confirmingBulkDelete = true } label: {
                selectionAction("Delete", systemImage: "trash")
                    .foregroundStyle(AppPalette.error)
            }
        }
        .disabled(books.isEmpty)
        .opacity(books.isEmpty ? 0.4 : 1)
        .padding(.vertical, 8)
        .background(AppPalette.surface, ignoresSafeAreaEdges: .bottom)
    }

    private func selectionAction(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 20))
                .frame(height: 25)
            Text(title).font(.caption2)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .contentShape(Rectangle())
    }

    private func bookLink(_ book: Book) -> some View {
        NavigationLink(value: Route.reader(book.id)) {
            BookCell(book: book, coverURL: model.coverURL(for: book))
        }
        .buttonStyle(.plain)
        .contextMenu { bookActions(book) }
        .accessibilityAction(named: "Book Details") { showDetails(for: book) }
    }

    private func bookCard(_ book: Book, isSelecting: Bool) -> some View {
        VStack(spacing: 0) {
            if isSelecting {
                selectableBook(book, layout: .card)
            } else {
                ZStack(alignment: .topTrailing) {
                    NavigationLink(value: Route.reader(book.id)) {
                        BookCell(book: book, coverURL: model.coverURL(for: book), layout: .card)
                    }
                    .buttonStyle(.plain)

                    Menu { bookActions(book, includesDetails: false) } label: {
                        Image(systemName: "ellipsis")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .menuOrder(.fixed)
                    .accessibilityLabel("More actions for \(book.title)")
                }

                HStack(spacing: 8) {
                    NavigationLink(value: Route.reader(book.id)) {
                        Label(book.readingStatus == .reading ? "Continue Reading" : "Read Book", systemImage: "book")
                    }
                    .buttonStyle(LibraryCardActionStyle(outlined: false))

                    Button { showDetails(for: book) } label: {
                        Label("Book Details", systemImage: "info.circle")
                    }
                    .buttonStyle(LibraryCardActionStyle(outlined: true))
                }
                .multilineTextAlignment(.center)
                .padding([.horizontal, .bottom], 12)
            }
        }
        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(AppPalette.border)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private func bookActions(_ book: Book, includesDetails: Bool = true) -> some View {
        if includesDetails {
            Button { showDetails(for: book) } label: {
                Label("Book Details", systemImage: "info.circle")
            }
        }
        Menu {
            ReadingStatusOptions(current: book.readingStatus) { status in
                model.setReadingStatus(status, for: [book]) { finishedBook = $0 }
            }
        } label: {
            Label("Change Status", systemImage: "checklist")
        }
        Menu {
            ForEach(model.shelfList.shelves) { shelf in
                Button { model.toggle(book, on: shelf) } label: {
                    if model.shelfList.isBook(book.id, on: shelf.id) {
                        Label(shelf.name, systemImage: "checkmark")
                    } else {
                        Text(shelf.name)
                    }
                }
            }
            Button { nameShelf(.create(adding: [book])) } label: {
                Label("New Shelf…", systemImage: "plus")
            }
        } label: {
            Label("Shelves", systemImage: "books.vertical")
        }
        Button(role: .destructive) { bookToDelete = book } label: {
            Label("Delete Book", systemImage: "trash")
        }
    }

    private func showDetails(for book: Book) {
        searchFocused = false
        path.append(.details(book.id, fromReader: false))
    }

    @ViewBuilder private var importStatus: some View {
        if !model.importing.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                Text(model.importing.count == 1 ? "Adding \(model.importing[0])…" : "Adding \(model.importing.count) books…")
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.secondaryText)
            }
            .padding(.vertical, 8)
        }
    }
}

struct ReadingStatusOptions: View {
    var current: ReadingStatus? = nil
    let onSelect: (ReadingStatus) -> Void

    var body: some View {
        ForEach(ReadingStatus.allCases) { status in
            Button {
                onSelect(status)
            } label: {
                if status == current {
                    Label(status.label, systemImage: "checkmark")
                } else {
                    Text(status.label)
                }
            }
        }
    }
}

/// Keep the original system glass/pill treatment after moving the controls.
private struct LibrarySearchRowSpacing: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 10)
    }
}

private struct LibraryControlSurface: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}

private struct LibraryCardActionStyle: ButtonStyle {
    let outlined: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        configuration.label
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(AppPalette.accent)
            .background(outlined ? .clear : AppPalette.accent.opacity(0.12), in: shape)
            .overlay(shape.strokeBorder(outlined ? AppPalette.border : .clear))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(shape)
    }
}

private struct BookCell: View {
    let book: Book
    let coverURL: URL?
    var layout: LibraryLayout = .grid
    /// Set while selecting books: whether this one is selected.
    var selected: Bool?

    private var progress: Double { min(1, max(0, book.progression)) }

    private var progressPercentage: String {
        progress.formatted(.percent.precision(.fractionLength(0)))
    }

    private var bookAccessibilityLabel: String {
        let name = "\(book.title), by \(book.author)"
        let rating = book.personalRatingQuarterStars.map { "\(personalRatingNumber($0)) out of 5 stars" } ?? "Unrated"
        return "\(name), \(rating), \(progressPercentage) read"
    }

    var body: some View {
        Group {
            if layout == .card {
                cardContent
            } else {
                gridContent
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bookAccessibilityLabel)
        .accessibilityAddTraits(selected == true ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("book-\(book.title)")
    }

    private var cardContent: some View {
        HStack(alignment: .top, spacing: 12) {
            cover.frame(width: 80)
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    bookTitle
                    bookAuthor
                }
                .padding(.trailing, selected == nil ? 32 : 0)
                VStack(alignment: .leading, spacing: 6) {
                    ratingStars
                    progressBar(label: progressPercentage)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
    }

    private var gridContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            cover
            HStack(spacing: 6) {
                ratingStars
                Spacer(minLength: 0)
                progressBadge
            }
        }
    }

    private var cover: some View {
        BookCoverView(book: book, coverURL: coverURL, showsPlaceholderTitle: false)
            .overlay(alignment: .topTrailing) {
                if let selected {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selected ? AppPalette.onAccent : .white, AppPalette.accent)
                        .background(Circle().fill(selected ? .clear : .black.opacity(0.35)))
                        .padding(6)
                }
            }
    }

    private var bookTitle: some View {
        Text(book.title)
            .font(.subheadline.weight(layout == .card ? .semibold : .medium))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
    }

    private var bookAuthor: some View {
        Text(book.author)
            .font(.caption)
            .foregroundStyle(AppPalette.secondaryText)
            .lineLimit(1)
    }

    private var ratingStars: some View {
        PersonalRatingStars(quarterStars: book.personalRatingQuarterStars ?? 0)
            .font(.system(size: 13))
    }

    private func progressBar(label: String) -> some View {
        HStack(spacing: 6) {
            ProgressView(value: progress)
                .tint(AppPalette.accent)
            Text(label)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(AppPalette.secondaryText)
        }
    }

    private var progressBadge: some View {
        let diameter: CGFloat = 38
        return Circle()
            .fill(AppPalette.secondarySurface)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AppPalette.accent.opacity(0.32))
                    .frame(height: diameter * progress)
            }
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(AppPalette.accent.opacity(0.55)))
            .overlay {
                Text(progressPercentage)
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(AppPalette.text)
            }
            .frame(width: diameter, height: diameter)
    }
}

private struct EmptyLibraryView: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "books.vertical")
                .font(.system(size: 52))
                .foregroundStyle(AppPalette.secondaryText)
            Text("Your library is empty")
                .font(.system(.title2, design: .serif).weight(.semibold))
            Text("Add EPUB or PDF books from Files, or open one from another app with “Open in Reading Tracker”.")
                .font(.subheadline)
                .foregroundStyle(AppPalette.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button(action: onAdd) {
                Label("Add Books", systemImage: "plus")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(AppPrimaryButtonStyle())
            .padding(.top, 6)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
