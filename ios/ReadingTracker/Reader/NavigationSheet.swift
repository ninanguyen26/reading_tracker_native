import ReadiumShared
import SwiftUI

/// Contents and bookmarks for the open book.
struct NavigationSheet: View {
    enum Tab: String, CaseIterable, Identifiable {
        case contents = "Contents"
        case bookmarks = "Bookmarks"
        case notes = "Notes"
        var id: String { rawValue }
    }

    @ObservedObject var model: ReaderModel
    @State var tab: Tab = .contents
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch tab {
                case .contents: contents
                case .bookmarks: bookmarkList
                case .notes: notesList
                }
            }
            .safeAreaInset(edge: .top) {
                Picker("Show", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .background(.bar)
            }
            .navigationTitle(model.book.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                if tab == .notes, let exportFile {
                    ToolbarItem(placement: .topBarLeading) {
                        ShareLink(item: exportFile) {
                            Label("Export Notes", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
    }

    // MARK: Contents

    private var flatContents: [(link: ReadiumShared.Link, depth: Int)] {
        func flatten(_ links: [ReadiumShared.Link], depth: Int) -> [(ReadiumShared.Link, Int)] {
            links.flatMap { [($0, depth)] + flatten($0.children, depth: depth + 1) }
        }
        return flatten(model.tableOfContents, depth: 0)
    }

    @ViewBuilder private var contents: some View {
        if model.tableOfContents.isEmpty {
            emptyState("This book has no table of contents.", systemImage: "list.bullet")
        } else {
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(flatContents.enumerated()), id: \.offset) { index, entry in
                        let current = isCurrent(entry.link)
                        Button {
                            model.go(to: entry.link)
                            dismiss()
                        } label: {
                            Text(entry.link.title ?? "Untitled")
                                .fontWeight(current ? .semibold : .regular)
                                .foregroundStyle(current ? Color.accentColor : .primary)
                                .padding(.leading, CGFloat(entry.depth) * 16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(index)
                        .accessibilityAddTraits(current ? .isSelected : [])
                    }
                }
                .listStyle(.plain)
                .onAppear {
                    if let index = flatContents.lastIndex(where: { isCurrent($0.link) }) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            }
        }
    }

    /// The chapter being read: its file matches the current position.
    private func isCurrent(_ link: ReadiumShared.Link) -> Bool {
        guard let current = model.currentChapterHref else { return false }
        let href = link.href.split(separator: "#").first.map(String.init) ?? link.href
        return current.hasSuffix(href) || href.hasSuffix(current)
    }

    // MARK: Bookmarks

    @ViewBuilder private var bookmarkList: some View {
        if model.bookmarks.isEmpty {
            emptyState("No bookmarks yet. Tap the bookmark button while reading to save your place.", systemImage: "bookmark")
        } else {
            List {
                ForEach(model.bookmarks) { bookmark in
                    Button {
                        model.go(to: bookmark)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(bookmark.title ?? "Bookmark")
                                .foregroundStyle(.primary)
                            Text("\(bookmark.progression.formatted(.percent.precision(.fractionLength(0)))) · \(bookmark.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    offsets.map { model.bookmarks[$0] }.forEach(model.deleteBookmark)
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: Notes

    @ViewBuilder private var notesList: some View {
        if model.highlights.isEmpty {
            emptyState("No highlights yet. Select text while reading and choose Highlight or Note.", systemImage: "highlighter")
        } else {
            List {
                ForEach(model.highlights) { highlight in
                    Button {
                        model.go(to: highlight)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(highlight.chapter.map { "\($0) · " } ?? "")\(highlight.progression.formatted(.percent.precision(.fractionLength(0))))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(highlight.text)
                                .font(.system(.subheadline, design: .serif))
                                .lineLimit(4)
                                .padding(.leading, 9)
                                .overlay(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 1.5)
                                        .fill(Color(uiColor: highlight.color.uiColor(in: model.highlightPalette)))
                                        .frame(width: 3)
                                }
                            if !highlight.note.isEmpty {
                                Text(highlight.note)
                                    .font(.subheadline)
                                    .italic()
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 12)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("note-\(highlight.text)")
                }
                .onDelete { offsets in
                    offsets.map { model.highlights[$0] }.forEach(model.delete)
                }
            }
            .listStyle(.plain)
        }
    }

    /// This book's notes as a Markdown file, for the share sheet.
    private var exportFile: URL? {
        guard !model.highlights.isEmpty else { return nil }
        let book = NotesExport.BookInfo(title: model.book.title, author: model.book.author)
        return try? NotesExport.temporaryFile(
            named: NotesExport.fileName(for: model.book.title),
            contents: NotesExport.markdown(for: book, highlights: model.highlights)
        )
    }

    private func emptyState(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(text)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
