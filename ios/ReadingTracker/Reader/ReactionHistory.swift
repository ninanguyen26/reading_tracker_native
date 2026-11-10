import SwiftUI

struct ReactionHistory: View {
    let bookID: String
    var inReader = false
    let onJump: (BookReaction) -> Void
    @EnvironmentObject private var environment: AppEnvironment
    @State private var spots: [ReactionSpot]?
    @State private var loadFailed = false
    @State private var editingSpot: ReactionSpot?
    @State private var spotToDelete: ReactionSpot?
    @State private var deleteFailed = false

    var body: some View {
        Group {
            if inReader {
                if spots?.isEmpty == true, !loadFailed {
                    readerNavigationEmptyState(
                        "No reactions yet. Tap the smiley to open the picker. Press and hold it to add one reaction quickly.",
                        systemImage: "face.smiling"
                    )
                } else {
                    List { entries }
                        .listStyle(.plain)
                }
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text("Reactions")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppPalette.secondaryText)
                        .accessibilityAddTraits(.isHeader)
                    entries
                }
                .detailsCard()
            }
        }
        .sheet(item: $editingSpot) { spot in
            ReactionPicker(editing: spot) { selection in
                try await environment.database.editReactions(at: spot, selection: selection)
            }
        }
        .alert(
            "Delete reactions at this spot?",
            isPresented: Binding(get: { spotToDelete != nil }, set: { if !$0 { spotToDelete = nil } }),
            presenting: spotToDelete
        ) { spot in
            Button("Delete Reactions", role: .destructive) { delete(spot) }
            Button("Cancel", role: .cancel) {}
        } message: { spot in
            Text(location(for: spot.anchor))
        }
        .alert("Couldn’t delete your reactions", isPresented: $deleteFailed) {
            Button("OK", role: .cancel) {}
        }
        .task(id: bookID) {
            do {
                for try await saved in environment.database.observeReactions(bookId: bookID) {
                    spots = ReactionSpot.group(saved)
                    loadFailed = false
                }
            } catch {
                if !Task.isCancelled { loadFailed = true }
            }
        }
    }

    @ViewBuilder private var entries: some View {
        if loadFailed {
            Text("Couldn’t load your reactions.")
                .foregroundStyle(AppPalette.error)
        } else if let spots {
            if spots.isEmpty {
                Text("No reactions yet.")
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.secondaryText)
            }
            ForEach(spots) { spot in
                if !inReader, spot.id != spots.first?.id {
                    Divider()
                        .overlay(AppPalette.border.opacity(0.65))
                }
                reactionRow(spot)
            }
        } else {
            ProgressView()
        }
    }

    private func reactionRow(_ spot: ReactionSpot) -> some View {
        HStack(spacing: 8) {
            Button { onJump(spot.anchor) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    DetailsFlowLayout(spacing: 6) {
                        ForEach(spot.kinds) { kind in
                            detailChip("\(kind.emoji) \(kind.label)")
                                .accessibilityLabel(kind.label)
                        }
                    }
                    Text(location(for: spot.anchor))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Jumps to this spot in the book")

            Menu {
                Button { editingSpot = spot } label: {
                    Label("Edit Reactions", systemImage: "pencil")
                }
                Button(role: .destructive) { spotToDelete = spot } label: {
                    Label("Delete Reactions", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppPalette.accent)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reaction actions")
            .accessibilityHint(location(for: spot.anchor))
        }
    }

    private func delete(_ spot: ReactionSpot) {
        Task {
            do {
                try await environment.database.deleteReactions(at: spot.anchor)
            } catch {
                deleteFailed = true
            }
        }
    }

    private func location(for reaction: BookReaction) -> String {
        let percent = reaction.progression.formatted(.percent.precision(.fractionLength(0)))
        return reaction.locationTitle.map { "\($0) · \(percent)" } ?? percent
    }
}
