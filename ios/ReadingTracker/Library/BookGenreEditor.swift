import SwiftUI

struct BookGenreEditor: View {
    let book: Book
    let onSave: (Book) -> Void
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var primary: BookGenre?
    @State private var secondary: Set<BookGenre>
    @State private var saving = false
    @State private var error: String?

    init(book: Book, onSave: @escaping (Book) -> Void) {
        self.book = book
        self.onSave = onSave
        _primary = State(initialValue: book.genre)
        _secondary = State(initialValue: Set(book.secondaryGenres))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Primary Genre", selection: $primary) {
                        Text("Unclassified").tag(nil as BookGenre?)
                        Section("Fiction") {
                            ForEach(BookGenre.allCases.filter(\.isFiction)) { Text($0.rawValue).tag(Optional($0)) }
                        }
                        Section("Non-Fiction") {
                            ForEach(BookGenre.allCases.filter { !$0.isFiction }) { Text($0.rawValue).tag(Optional($0)) }
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .accessibilityIdentifier("primary-genre-picker")
                } footer: {
                    Text("Your selection takes priority over automatic classification. You can also leave a book unclassified.")
                }
                Section {
                    Button("Use Automatic Classification") { save(automatic: true) }
                        .accessibilityIdentifier("automatic-genre")
                } footer: {
                    Text("Uses subjects and, when available, on-device Apple Intelligence. Uncertain books remain unclassified.")
                }
                if primary != nil {
                    Section("Secondary Genres (up to 2)") {
                        ForEach(BookGenre.allCases.filter { $0 != primary }) { genre in
                            Toggle(genre.rawValue, isOn: Binding(get: { secondary.contains(genre) }, set: {
                                if $0 { secondary.insert(genre) } else { secondary.remove(genre) }
                            }))
                            .disabled(!secondary.contains(genre) && secondary.count >= 2)
                        }
                    }
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
            .onChange(of: primary) { selected in
                if let selected { secondary.remove(selected) } else { secondary.removeAll() }
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
                    _ = try await environment.database.saveManualGenre(id: book.id, primary: primary,
                        secondary: BookGenre.allCases.filter { secondary.contains($0) })
                }
                guard let saved = try await environment.database.book(id: book.id) else { throw OpenLibraryError.missingBook }
                onSave(saved)
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
