import SwiftUI

struct BookJournal: View {
    let bookID: String
    @EnvironmentObject private var environment: AppEnvironment
    @State private var entries: [JournalEntry]?
    @State private var loadFailed = false
    @State private var editor: Editor?
    @State private var entryToDelete: JournalEntry?
    @State private var deleteFailed = false

    private enum Editor: Identifiable {
        case add
        case edit(JournalEntry)

        var entry: JournalEntry? {
            if case .edit(let entry) = self { return entry }
            return nil
        }

        var id: String { entry?.id ?? "add" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Journal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppPalette.secondaryText)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button { editor = .add } label: {
                    Label("Add Entry", systemImage: "plus")
                }
                .buttonStyle(DetailsHeaderActionStyle())
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
                        entryRow(entry)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .sheet(item: $editor) { editor in
            JournalEntryEditor(bookID: bookID, entry: editor.entry)
        }
        .alert(
            "Delete this journal entry?",
            isPresented: Binding(get: { entryToDelete != nil }, set: { if !$0 { entryToDelete = nil } }),
            presenting: entryToDelete
        ) { entry in
            Button("Delete Entry", role: .destructive) { delete(entry) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Couldn’t delete your entry", isPresented: $deleteFailed) {
            Button("OK", role: .cancel) {}
        }
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

    private func entryRow(_ entry: JournalEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.createdAt, format: .dateTime.month().day().year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(AppPalette.secondaryText)
                Text(verbatim: entry.text)
                    .font(.subheadline)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Button { editor = .edit(entry) } label: {
                    Label("Edit Entry", systemImage: "pencil")
                }
                Button(role: .destructive) { entryToDelete = entry } label: {
                    Label("Delete Entry", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppPalette.accent)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Journal entry actions")
        }
    }

    private func delete(_ entry: JournalEntry) {
        Task {
            do {
                try await environment.database.deleteJournalEntry(id: entry.id)
            } catch {
                deleteFailed = true
            }
        }
    }
}

private struct JournalEntryEditor: View {
    let bookID: String
    let entry: JournalEntry?
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var text: String
    @State private var saving = false
    @State private var saveError: String?

    init(bookID: String, entry: JournalEntry?) {
        self.bookID = bookID
        self.entry = entry
        _text = State(initialValue: entry?.text ?? "")
    }

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
            .navigationTitle(entry == nil ? "Add Journal Entry" : "Edit Journal Entry")
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
        let draft = text
        Task {
            defer { saving = false }
            do {
                if let entry {
                    try await environment.database.updateJournalEntry(id: entry.id, text: draft)
                } else {
                    try await environment.database.addJournalEntry(bookId: bookID, text: draft)
                }
                dismiss()
            } catch {
                saveError = "Couldn’t save your entry. Please try again."
            }
        }
    }
}
