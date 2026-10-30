import ReadiumShared
import SwiftUI

/// Search the open book; results stream in chapter by chapter.
struct SearchSheet: View {
    @ObservedObject var model: ReaderModel
    @State private var text: String
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    init(model: ReaderModel) {
        self.model = model
        _text = State(initialValue: model.search.query)
    }

    private var search: BookSearch { model.search }

    var body: some View {
        NavigationStack {
            List {
                if search.status == .searching || search.status == .done {
                    Section {
                        Text(summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("search-summary")
                    }
                }
                if case .failed(let message) = search.status {
                    Text(message).foregroundStyle(.secondary)
                }
                ForEach(search.sections) { section in
                    Section(section.title) {
                        ForEach(Array(section.results.enumerated()), id: \.offset) { _, locator in
                            Button {
                                model.go(toSearchResult: locator)
                                dismiss()
                            } label: {
                                ResultText(text: locator.text)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if search.status == .searching && search.count == 0 {
                    ProgressView()
                }
            }
            .safeAreaInset(edge: .top) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search this book", text: $text)
                        .focused($focused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .onSubmit { model.runSearch(text) }
                        .accessibilityIdentifier("search-field")
                    if !text.isEmpty {
                        Button {
                            text = ""
                            model.clearSearch()
                            focused = true
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Clear Search")
                    }
                }
                .padding(10)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal)
                .padding(.bottom, 8)
                .background(.bar)
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { if search.query.isEmpty { focused = true } }
        }
    }

    private var summary: String {
        let count = search.count
        let results = count == 1 ? "1 result" : "\(count) results"
        switch search.status {
        case .searching: return "Searching… \(count > 0 ? "\(results) so far" : "")"
        case .done: return count == 0 ? "No matches for “\(search.query)”." : "\(results) for “\(search.query)”"
        default: return ""
        }
    }
}

/// A result's text with the match in bold.
private struct ResultText: View {
    let text: Locator.Text

    var body: some View {
        (Text("…" + (text.before ?? "").suffix(60).trimmingCharacters(in: .newlines))
            + Text(text.highlight ?? "").bold().foregroundColor(.accentColor)
            + Text((text.after ?? "").prefix(60).trimmingCharacters(in: .newlines) + "…"))
            .font(.subheadline)
            .lineLimit(3)
    }
}
