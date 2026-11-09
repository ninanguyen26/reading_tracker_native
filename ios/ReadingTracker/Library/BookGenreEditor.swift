import SwiftUI

struct BookGenreEditor: View {
    let book: Book
    let onSave: (Book) -> Void
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var selectedGenres: Set<BookGenre>
    @State private var saving = false
    @State private var error: String?

    init(book: Book, onSave: @escaping (Book) -> Void) {
        self.book = book
        self.onSave = onSave
        _selectedGenres = State(initialValue: Set(book.genres))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Use Automatic Classification") { save(automatic: true) }
                        .accessibilityIdentifier("automatic-genre")
                } footer: {
                    Text("Uses subjects and, when available, on-device Apple Intelligence. Uncertain books remain unclassified.")
                }
                Section {
                    ForEach(BookGenre.allCases) { genre in
                        let selected = selectedGenres.contains(genre)
                        Button {
                            if selected {
                                selectedGenres.remove(genre)
                            } else {
                                selectedGenres.insert(genre)
                            }
                        } label: {
                            HStack {
                                Text(genre.displayName)
                                Spacer()
                                if selected {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(AppPalette.accent)
                                        .accessibilityHidden(true)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("genre-option-\(genre.rawValue)")
                    }
                } footer: {
                    Text("Your selections take priority over automatic classification. An empty selection leaves the book unclassified.")
                }
                if saving { ProgressView("Updating genre…") }
                if let error { Text(error).foregroundStyle(AppPalette.error) }
            }
            .disabled(saving)
            .scrollContentBackground(.hidden)
            .background(AppPalette.background)
            .navigationTitle("Edit Genres")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(automatic: false) }.disabled(saving) }
            }
        }
    }

    private func save(automatic: Bool) {
        saving = true
        error = nil
        Task { @MainActor in
            defer { saving = false }
            do {
                if automatic {
                    try await environment.database.resetManualGenre(id: book.id)
                    await BookGenreClassifier.shared.classifyBook(id: book.id, database: environment.database)
                } else {
                    _ = try await environment.database.saveManualGenres(id: book.id, genres: selectedGenres)
                }
                guard let saved = try await environment.database.book(id: book.id) else { throw OpenLibraryError.missingBook }
                onSave(saved)
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
