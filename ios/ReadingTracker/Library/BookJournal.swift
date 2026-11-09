import SwiftUI

struct BookJournal: View {
    let bookID: String
    @EnvironmentObject private var environment: AppEnvironment
    @State private var entries: [JournalEntry]?
    @State private var loadFailed = false
    @State private var showingAddEntry = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Journal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppPalette.secondaryText)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button { showingAddEntry = true } label: {
                    Label("Add Entry", systemImage: "plus")
                }
                .buttonStyle(DetailsActionStyle())
            }

            if loadFailed {
                Text("Couldn’t load your journal.").foregroundStyle(AppPalette.error)
            } else if let entries {
                if entries.isEmpty {
                    Text("No journal entries yet.")
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.secondaryText)
                }
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(entries) { entry in
                        Divider()
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.createdAt, format: .dateTime.month().day().year().hour().minute())
                                .font(.caption)
                                .foregroundStyle(AppPalette.secondaryText)
                            Text(verbatim: entry.text)
                                .font(.subheadline)
                                .textSelection(.enabled)
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .sheet(isPresented: $showingAddEntry) { JournalEntryEditor(bookID: bookID) }
        .task(id: bookID) {
            do {
                for try await updated in environment.database.observeJournal(bookId: bookID) {
                    entries = updated
                    loadFailed = false
                }
            } catch {
                if !Task.isCancelled { loadFailed = true }
            }
        }
    }
}

private struct JournalEntryEditor: View {
    let bookID: String
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var text = ""
    @State private var saving = false
    @State private var saveError: String?

    private var canSave: Bool {
        !saving && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $text)
                    .font(.body)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppPalette.border))
                    .accessibilityLabel("Journal entry")
                    .focused($focused)
                if let saveError {
                    Text(saveError).font(.subheadline).foregroundStyle(AppPalette.error)
                }
            }
            .padding()
            .background(AppPalette.background)
            .navigationTitle("Add Journal Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
            .onAppear { focused = true }
        }
        .interactiveDismissDisabled(saving)
    }

    private func save() {
        guard canSave else { return }
        saving = true
        saveError = nil
        let entry = text
        Task {
            defer { saving = false }
            do {
                try await environment.database.addJournalEntry(bookId: bookID, text: entry)
                dismiss()
            } catch {
                saveError = "Couldn’t save your entry. Please try again."
            }
        }
    }
}
