import SwiftUI

struct OpenLibraryLookupScreen: View {
    let book: Book
    let onSave: (Book) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var author: String
    @State private var isbn: String
    @State private var matches: [OpenLibraryMatch] = []
    @State private var searching = false
    @State private var searched = false
    @State private var error: String?
    @State private var searchTask: Task<Void, Never>?

    init(book: Book, onSave: @escaping (Book) -> Void) {
        self.book = book
        self.onSave = onSave
        _title = State(initialValue: book.title)
        _author = State(initialValue: book.author == "Unknown author" ? "" : book.author)
        _isbn = State(initialValue: book.isbn ?? "")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Title", text: $title).accessibilityIdentifier("lookup-title")
                    TextField("Author", text: $author)
                    TextField("ISBN (optional)", text: $isbn)
                        .textInputAutocapitalization(.never)
                    Button(action: search) {
                        HStack {
                            Text("Search Open Library")
                            if searching { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(searching || (title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && OpenLibraryISBN.normalize(isbn) == nil))
                } footer: {
                    Text("Search sends the title and author, or ISBN, to Open Library. Your book file stays on this device. Existing details and covers are preserved.")
                }
                if let error {
                    Section { Text(error).foregroundStyle(AppPalette.error) }
                }
                if searched && matches.isEmpty && !searching && error == nil {
                    Section { Text("No matches. Try changing the title or removing the author or ISBN.") }
                }
                if !matches.isEmpty {
                    Section("Choose the matching book") {
                        ForEach(matches) { match in
                            NavigationLink {
                                OpenLibraryEditionScreen(book: book, match: match, onSave: saved)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(match.title)
                                    Text((match.author_name ?? []).joined(separator: ", "))
                                        .font(.subheadline).foregroundStyle(AppPalette.secondaryText)
                                    if let year = match.first_publish_year {
                                        Text("First published \(String(year))").font(.caption).foregroundStyle(AppPalette.secondaryText)
                                    }
                                }
                            }
                            .accessibilityIdentifier("lookup-match-\(match.key)")
                        }
                    }
                }
                Section {
                    Link("About Open Library", destination: URL(string: "https://openlibrary.org")!)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppPalette.background)
            .navigationTitle("Find Missing Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .onDisappear { searchTask?.cancel() }
    }

    private func saved(_ updated: Book) { onSave(updated); dismiss() }

    private func search() {
        searching = true
        error = nil
        matches = []
        searchTask = Task { @MainActor in
            defer { searching = false }
            do {
                if !isbn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && OpenLibraryISBN.normalize(isbn) == nil {
                    error = "Enter a valid ISBN, or clear it to search by title and author."
                    return
                }
                matches = try await OpenLibraryClient.shared.search(title: title, author: author, isbn: isbn)
                searched = true
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
}

private struct OpenLibraryEditionScreen: View {
    let book: Book
    let match: OpenLibraryMatch
    let onSave: (Book) -> Void
    @State private var work: OpenLibraryRecord?
    @State private var editions: [OpenLibraryRecord] = []
    @State private var loading = false
    @State private var hasMore = true
    @State private var offset = 0
    @State private var error: String?

    var body: some View {
        List {
            if let work {
                Section {
                    NavigationLink("Use general book details") {
                        OpenLibraryReviewScreen(book: book, metadata: OpenLibraryMetadata(work: work, edition: nil), onSave: onSave)
                    }
                } footer: {
                    Text("Choose your edition below to include its language and any edition-specific details.")
                }
                Section("Editions") {
                    ForEach(editions) { edition in
                        NavigationLink {
                            OpenLibraryReviewScreen(book: book, metadata: OpenLibraryMetadata(work: work, edition: edition), onSave: onSave)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(edition.title ?? match.title)
                                Text(([edition.publishDate].compactMap { $0 } + edition.publishers).joined(separator: " · "))
                                    .font(.subheadline).foregroundStyle(AppPalette.secondaryText)
                                if !edition.languages.isEmpty {
                                    Text(edition.languages.map { Locale.current.localizedString(forLanguageCode: $0) ?? $0 }.joined(separator: ", "))
                                        .font(.caption).foregroundStyle(AppPalette.secondaryText)
                                }
                            }
                        }
                        .accessibilityIdentifier("lookup-edition-\(edition.key)")
                    }
                    if hasMore && !loading { Button("Load More Editions") { Task { await load() } } }
                }
            }
            if loading { ProgressView("Loading details…") }
            if let error {
                Text(error).foregroundStyle(AppPalette.error)
                Button("Try Again") { Task { await load() } }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppPalette.background)
        .navigationTitle(match.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { if work == nil { await load() } }
    }

    @MainActor private func load() async {
        guard !loading else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            if work == nil { work = try await OpenLibraryClient.shared.work(match.key) }
            let page = try await OpenLibraryClient.shared.editions(match.key, offset: offset)
            let ids = Set(editions.map(\.key))
            editions += page.filter { !ids.contains($0.key) }
            offset += 20
            hasMore = page.count == 20
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

private struct OpenLibraryReviewScreen: View {
    let book: Book
    let metadata: OpenLibraryMetadata
    let onSave: (Book) -> Void
    @EnvironmentObject private var environment: AppEnvironment
    @State private var selected: Set<OpenLibraryField>
    @State private var saving = false
    @State private var error: String?

    init(book: Book, metadata: OpenLibraryMetadata, onSave: @escaping (Book) -> Void) {
        self.book = book
        self.metadata = metadata
        self.onSave = onSave
        _selected = State(initialValue: Set(metadata.availableFields(for: book)))
    }

    var body: some View {
        List {
            if metadata.availableFields(for: book).isEmpty {
                Text("This record has no additional details for the empty fields in your book.")
            } else {
                Section {
                    ForEach(metadata.availableFields(for: book)) { field in
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(field.label, isOn: Binding(get: { selected.contains(field) }, set: {
                                if $0 { selected.insert(field) } else { selected.remove(field) }
                            }))
                            Text(metadata.value(for: field)).font(.subheadline).textSelection(.enabled)
                        }.padding(.vertical, 4)
                    }
                } footer: { Text("Only selected, currently empty fields will be added. Your existing metadata and cover stay as they are.") }
                Button("Save Selected Details") { save() }
                    .disabled(selected.isEmpty || saving)
            }
            if saving { ProgressView("Saving…") }
            if let error { Text(error).foregroundStyle(AppPalette.error) }
            Section("Source") {
                Link("Open Library record", destination: URL(string: "https://openlibrary.org\(metadata.editionKey ?? metadata.workKey)")!)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppPalette.background)
        .navigationTitle("Review Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() {
        saving = true
        error = nil
        Task { @MainActor in
            defer { saving = false }
            do { onSave(try await environment.database.enrichBook(id: book.id, metadata: metadata, fields: selected)) }
            catch { self.error = error.localizedDescription }
        }
    }
}
