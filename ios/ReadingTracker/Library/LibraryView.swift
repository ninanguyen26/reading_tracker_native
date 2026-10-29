import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @ObservedObject var model: LibraryModel
    @State private var showingImporter = false
    @State private var bookToDelete: Book?
    // Navigate by ID: a Book value changes as soon as it's opened (progress,
    // last-opened date), which SwiftUI would treat as a different destination.
    @State private var path: [String] = []

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 20, alignment: .top)]

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.loaded && model.books.isEmpty {
                    EmptyLibraryView { showingImporter = true }
                } else {
                    ScrollView {
                        importStatus
                        if !model.query.isEmpty && model.visibleBooks.isEmpty {
                            Text("No books match “\(model.query)”.")
                                .foregroundStyle(.secondary)
                                .padding(.top, 40)
                        }
                        LazyVGrid(columns: columns, spacing: 28) {
                            ForEach(model.visibleBooks) { book in
                                NavigationLink(value: book.id) {
                                    BookCell(book: book, coverURL: model.coverURL(for: book))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        bookToDelete = book
                                    } label: {
                                        Label("Delete Book", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                    }
                    .searchable(text: $model.query, prompt: "Title or author")
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: String.self) { id in
                if let book = model.books.first(where: { $0.id == id }) {
                    ReaderScreen(book: book, environment: model.environment)
                        .id(id)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Picker("Sort By", selection: $model.sort) {
                            ForEach(LibrarySort.allCases) { Text($0.label).tag($0) }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                    .disabled(model.books.isEmpty)

                    Button { showingImporter = true } label: {
                        Label("Add Books", systemImage: "plus")
                    }
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

    @ViewBuilder private var importStatus: some View {
        if !model.importing.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                Text(model.importing.count == 1 ? "Adding \(model.importing[0])…" : "Adding \(model.importing.count) books…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
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
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 6) {
                ProgressView(value: book.progression)
                    .tint(.accentColor)
                Text(progressLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
            Text("Your library is empty")
                .font(.system(.title2, design: .serif).weight(.semibold))
            Text("Add EPUB or PDF books from Files, or open one from another app with “Open in Reading Tracker”.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button(action: onAdd) {
                Label("Add Books", systemImage: "plus")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 6)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
