import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @ObservedObject var model: LibraryModel
    @State private var showingImporter = false
    @State private var selectedTab: AppTab = .library
    @FocusState private var searchFocused: Bool
    @State private var bookToDelete: Book?
    @State private var bookToInspect: Book?
    // Navigate by ID: a Book value changes as soon as it's opened (progress,
    // last-opened date), which SwiftUI would treat as a different destination.
    @State private var path: [String] = []

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 20, alignment: .top)]

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
                AppNavigationBar(selection: $selectedTab) {
                    searchFocused = false
                    showingImporter = true
                }
            }
            .background(AppPalette.background)
            .foregroundStyle(AppPalette.text)
            .toolbarBackground(AppPalette.background, for: .navigationBar)
            .navigationTitle(selectedTab.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(selectedTab == .home ? .hidden : .visible, for: .navigationBar)
            .navigationDestination(for: String.self) { id in
                if let book = model.books.first(where: { $0.id == id }) {
                    ReaderScreen(book: book, environment: model.environment)
                        .id(id)
                }
            }
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
            .sheet(item: $bookToInspect) { book in
                BookDetailsScreen(book: book, coverURL: model.coverURL(for: book)) {
                    path.append(book.id)
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
            .alert(
                "Something went wrong",
                isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    @ViewBuilder private var rootContent: some View {
        switch selectedTab {
        case .library:
            VStack(spacing: 0) {
                librarySearch
                if model.loaded && model.books.isEmpty {
                    EmptyLibraryView { showingImporter = true }
                } else {
                    ScrollView {
                        importStatus
                        if !model.query.isEmpty && model.visibleBooks.isEmpty {
                            Text("No books match “\(model.query)”.")
                                .foregroundStyle(AppPalette.secondaryText)
                                .padding(.top, 40)
                        }
                        LazyVGrid(columns: columns, spacing: 28) {
                            ForEach(model.visibleBooks) { book in bookLink(book) }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .accessibilityIdentifier("library-scroll")
                }
            }
        case .home:
            if model.books.isEmpty {
                EmptyLibraryView { showingImporter = true }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        importStatus
                        Text("Pick up a book")
                            .font(.system(.title2, design: .serif).weight(.semibold))
                        Text("Your next chapter is waiting.")
                            .foregroundStyle(AppPalette.secondaryText)
                        LazyVGrid(columns: columns, spacing: 28) {
                            ForEach(Array(model.books.sorted(by: .recent).prefix(4))) { book in bookLink(book) }
                        }
                    }
                    .padding()
                }
                .accessibilityIdentifier("home-scroll")
            }
        case .stats:
            LibraryStatsView(books: model.books)
        case .settings:
            AppSettingsView()
        }
    }

    private var librarySearch: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Title or author", text: $model.query)
                    .focused($searchFocused)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { searchFocused = false }
                    .accessibilityIdentifier("library-search")
                if !model.query.isEmpty {
                    Button { model.query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Clear Search")
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .foregroundStyle(.primary)
            .modifier(LibraryControlSurface())

            Menu {
                Picker("Sort By", selection: $model.sort) {
                    ForEach(LibrarySort.allCases) { Text($0.label).tag($0) }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.title3)
                    .frame(width: 48, height: 48)
                    .foregroundStyle(.primary)
                    .modifier(LibraryControlSurface())
            }
            .accessibilityLabel("Sort")
            .disabled(model.books.isEmpty)
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 18)
    }

    private func bookLink(_ book: Book) -> some View {
        NavigationLink(value: book.id) {
            BookCell(book: book, coverURL: model.coverURL(for: book))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { bookToInspect = book } label: {
                Label("Book Details", systemImage: "info.circle")
            }
            Button(role: .destructive) { bookToDelete = book } label: {
                Label("Delete Book", systemImage: "trash")
            }
        }
        .accessibilityAction(named: "Book Details") { bookToInspect = book }
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

/// Keep the original system glass/pill treatment after moving the controls.
private struct LibraryControlSurface: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}

private struct BookCell: View {
    let book: Book
    let coverURL: URL?

    private var progressLabel: String {
        if book.progression >= 0.995 { return "Done" }
        if book.progression > 0 { return book.progression.formatted(.percent.precision(.fractionLength(0))) }
        return "New"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            BookCoverView(book: book, coverURL: coverURL)
                .overlay(alignment: .topLeading) {
                    Text(book.format.label)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(.white)
                        .padding(6)
                }
            Text(book.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(book.author)
                .font(.caption)
                .foregroundStyle(AppPalette.secondaryText)
                .lineLimit(1)
            HStack(spacing: 6) {
                ProgressView(value: book.progression)
                    .tint(AppPalette.accent)
                Text(progressLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(AppPalette.secondaryText)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(book.title), by \(book.author), \(progressLabel)")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("book-\(book.title)")
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
