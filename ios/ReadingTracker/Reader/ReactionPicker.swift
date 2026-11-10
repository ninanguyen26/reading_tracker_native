import SwiftUI

struct ReactionPicker: View {
    private let title: String
    private let onSave: (Set<ReactionKind>) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selection: Set<ReactionKind>
    @State private var saving = false
    @State private var saveFailed = false

    init(editing spot: ReactionSpot? = nil, onSave: @escaping (Set<ReactionKind>) async throws -> Void) {
        title = spot == nil ? "Log Reactions" : "Edit Reactions"
        _selection = State(initialValue: Set(spot?.kinds ?? []))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(ReactionKind.allCases, content: tile)
                }
                .padding(16)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button(action: save) {
                    Text("Save").frame(maxWidth: .infinity)
                }
                .buttonStyle(AppPrimaryButtonStyle())
                .disabled(selection.isEmpty || saving)
                .padding(16)
                .background(AppPalette.background)
            }
            .background(AppPalette.background)
            .foregroundStyle(AppPalette.text)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(saving)
                }
            }
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(430), .large])
        .interactiveDismissDisabled(saving)
        .alert("Couldn’t save your reactions", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        }
    }

    private func tile(_ kind: ReactionKind) -> some View {
        let selected = selection.contains(kind)
        let shape = RoundedRectangle(cornerRadius: 12)
        return Button {
            if selected { selection.remove(kind) } else { selection.insert(kind) }
        } label: {
            VStack(spacing: 6) {
                Text(kind.emoji)
                    .font(.largeTitle)
                Text(kind.label)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 82)
            .background(selected ? AppPalette.accent.opacity(0.14) : AppPalette.surface, in: shape)
            .overlay(shape.strokeBorder(selected ? AppPalette.accent : AppPalette.border))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(AppPalette.accent)
                        .padding(6)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(saving)
        .accessibilityLabel(kind.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func save() {
        guard !selection.isEmpty, !saving else { return }
        saving = true
        let selected = selection
        Task {
            defer { saving = false }
            do {
                try await onSave(selected)
                dismiss()
            } catch {
                saveFailed = true
            }
        }
    }
}
