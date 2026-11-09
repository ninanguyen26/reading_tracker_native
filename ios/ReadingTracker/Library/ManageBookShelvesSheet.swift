import SwiftUI

struct ManageBookShelvesSheet: View {
    let bookID: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var environment: AppEnvironment
    @State private var shelfList: ShelfList?
    @State private var loadFailed = false
    @State private var saving = false
    @State private var saveError: String?
    @State private var namingShelf = false
    @State private var shelfName = ""

    var body: some View {
        NavigationStack {
            List {
                if let shelfList {
                    Section {
                        if shelfList.shelves.isEmpty {
                            Text("No shelves yet.").foregroundStyle(AppPalette.secondaryText)
                        }
                        ForEach(shelfList.shelves) { shelf in
                            let selected = shelfList.isBook(bookID, on: shelf.id)
                            Button {
                                save { try await $0.setBook(id: bookID, onShelf: shelf.id, !selected) }
                            } label: {
                                HStack {
                                    Text(shelf.name)
                                    Spacer()
                                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selected ? AppPalette.accent : AppPalette.secondaryText)
                                        .accessibilityHidden(true)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    Section {
                        Button {
                            shelfName = ""
                            namingShelf = true
                        } label: {
                            Label("New Shelf", systemImage: "plus")
                        }
                    }
                } else if !loadFailed {
                    ProgressView()
                }
                if loadFailed || saveError != nil {
                    Text(saveError ?? "Couldn’t load your shelves.").foregroundStyle(AppPalette.error)
                }
            }
            .disabled(saving)
            .scrollContentBackground(.hidden)
            .background(AppPalette.background)
            .navigationTitle("Manage Shelves")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.disabled(saving)
                }
            }
            .alert("New Shelf", isPresented: $namingShelf) {
                TextField("Shelf name", text: $shelfName)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    let name = shelfName
                    save { _ = try await $0.createShelf(named: name, adding: [bookID]) }
                }
                .disabled(Shelf.cleanName(shelfName).isEmpty)
            }
        }
        .interactiveDismissDisabled(saving)
        .task {
            do {
                for try await updated in environment.database.observeShelves() { shelfList = updated }
            } catch {
                if !Task.isCancelled { loadFailed = true }
            }
        }
    }

    private func save(_ change: @escaping (AppDatabase) async throws -> Void) {
        guard !saving else { return }
        saving = true
        saveError = nil
        Task {
            defer { saving = false }
            do {
                try await change(environment.database)
            } catch {
                saveError = "Couldn’t update your shelves. Please try again."
            }
        }
    }
}
