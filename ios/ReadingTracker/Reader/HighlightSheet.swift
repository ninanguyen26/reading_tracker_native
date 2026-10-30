import SwiftUI

/// Edit one highlight: its color, its note, or delete it.
struct HighlightSheet: View {
    @ObservedObject var model: ReaderModel
    let highlight: Highlight
    let focusNote: Bool
    @State private var note: String
    @State private var confirmingDelete = false
    @FocusState private var noteFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(model: ReaderModel, highlight: Highlight, focusNote: Bool) {
        self.model = model
        self.highlight = highlight
        self.focusNote = focusNote
        _note = State(initialValue: highlight.note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(highlight.text)
                        .font(.system(.body, design: .serif))
                        .lineLimit(6)
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(uiColor: highlight.color.uiColor(in: model.highlightPalette)))
                                .frame(width: 4)
                        }
                }

                Section("Color") {
                    HStack(spacing: 16) {
                        ForEach(Highlight.Color.allCases) { color in
                            Button { model.setColor(color, of: highlight) } label: {
                                Circle()
                                    .fill(Color(uiColor: color.uiColor(in: model.highlightPalette)))
                                    .frame(width: 34, height: 34)
                                    .overlay(Circle().strokeBorder(.primary, lineWidth: highlight.color == color ? 2.5 : 0).padding(-4))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(color.label)
                            .accessibilityAddTraits(highlight.color == color ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("Note") {
                    TextField("Add a note…", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($noteFocused)
                        .accessibilityIdentifier("highlight-note")
                }

                Section {
                    Button("Delete Highlight", role: .destructive) { confirmingDelete = true }
                }
            }
            .navigationTitle("Highlight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Delete this highlight?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete Highlight", role: .destructive) {
                    model.delete(highlight)
                    dismiss()
                }
            } message: {
                if !highlight.note.isEmpty || !note.isEmpty { Text("Its note will be deleted too.") }
            }
            .onAppear { if focusNote { noteFocused = true } }
            // Saved when the sheet closes, however it closes.
            .onDisappear { model.saveNote(note, of: highlight) }
        }
        .presentationDetents([.medium, .large])
    }
}
