import SwiftUI

struct BookDetailsScreen: View {
    @State private var book: Book
    let coverURL: URL?
    var onRead: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showingLookup = false
    @State private var showingGenres = false
    @State private var expandedDescription = false
    @State private var expandedSubjects = false
    private var description: String? { BookDetailsText.description(book.description) }

    init(book: Book, coverURL: URL?, onRead: (() -> Void)? = nil) {
        _book = State(initialValue: book)
        self.coverURL = coverURL
        self.onRead = onRead
    }
    private var series: [BookSeries] { book.series.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    private var subjects: [String] { BookDetailsText.nonempty(book.subjects) }
    private var languages: [String] { BookDetailsText.nonempty(book.languages) }
    private var metadataSources: [String: String] {
        book.openLibraryFields.filter {
            ($0.key != "description" || description != nil) &&
            (OpenLibraryClient.validKey($0.value, kind: "books", suffix: "M") ||
             OpenLibraryClient.validKey($0.value, kind: "works", suffix: "W"))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    bookHeader
                    if let onRead {
                        Button {
                            dismiss()
                            onRead()
                        } label: {
                            Label(book.progression > 0 ? "Continue Reading" : "Read Book", systemImage: "book")
                                .frame(maxWidth: .infinity, minHeight: 24)
                        }
                        .buttonStyle(AppPrimaryButtonStyle())
                    }
                    if let description { synopsisCard(description) }
                    informationCard
                    Button { showingLookup = true } label: {
                        Label("Find Missing Details", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DetailsActionStyle())
                    .accessibilityIdentifier("find-missing-details")
                    if !metadataSources.isEmpty { sourcesCard }
                }
                .frame(maxWidth: 600)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .background(AppPalette.background)
            .foregroundStyle(AppPalette.text)
            .toolbarBackground(AppPalette.background, for: .navigationBar)
            .navigationTitle("Book Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showingLookup) { OpenLibraryLookupScreen(book: book) { book = $0 } }
            .sheet(isPresented: $showingGenres) { BookGenreEditor(book: book) { book = $0 } }
            .task {
                do {
                    for try await books in environment.database.observeBooks() {
                        if let saved = books.first(where: { $0.id == book.id }) { book = saved }
                    }
                } catch { /* Keep already loaded details if observation ends. */ }
            }
            .task(id: book.id) {
                guard book.description != nil, description == nil,
                      let key = book.openLibraryWorkKey,
                      OpenLibraryClient.validKey(key, kind: "works", suffix: "W"),
                      let work = try? await OpenLibraryClient.shared.work(key) else { return }
                _ = try? await environment.database.enrichBook(
                    id: book.id, metadata: OpenLibraryMetadata(work: work, edition: nil), fields: [.description]
                )
            }
        }
    }

    private var bookHeader: some View {
        HStack(alignment: .top, spacing: 18) {
            BookCoverView(book: book, coverURL: coverURL)
                .frame(width: 96)
            VStack(alignment: .leading, spacing: 8) {
                Text(book.title)
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if !book.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   book.author != "Unknown author" {
                    Text(book.author)
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.secondaryText)
                }
                Text(book.format.label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(AppPalette.secondarySurface, in: Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    private func synopsisCard(_ description: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("Description")
            Text(description)
                .font(.subheadline)
                .lineSpacing(4)
                .lineLimit(!expandedDescription && description.count > 280 ? 6 : nil)
                .textSelection(.enabled)
                .accessibilityIdentifier("details-description")
            if description.count > 280 {
                Button { expandedDescription.toggle() } label: {
                    Label(expandedDescription ? "Show Less" : "Read More", systemImage: expandedDescription ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(DetailsActionStyle())
            }
        }
        .detailsCard()
    }

    private var informationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                heading("Genres")
                Spacer(minLength: 0)
                Button { showingGenres = true } label: { Label("Edit Genres", systemImage: "pencil") }
                    .buttonStyle(DetailsActionStyle())
            }
            DetailsFlowLayout(spacing: 8) {
                detailChip(book.genre?.rawValue ?? "Unclassified", prominent: book.genre != nil)
                    .accessibilityIdentifier("book-primary-genre")
                ForEach(book.secondaryGenres, id: \.self) { detailChip($0.rawValue) }
            }
            if !series.isEmpty || !languages.isEmpty {
                Divider().overlay(AppPalette.border)
                if !series.isEmpty {
                    metadataRow("Series", value: series.map(BookDetailsText.series).joined(separator: "\n"))
                }
                if !languages.isEmpty {
                    metadataRow(languages.count == 1 ? "Language" : "Languages",
                                value: languages.map { Locale.current.localizedString(forIdentifier: $0) ?? $0 }.joined(separator: ", "))
                }
            }
            if !subjects.isEmpty {
                Divider().overlay(AppPalette.border)
                heading("Subjects")
                DetailsFlowLayout(spacing: 8) {
                    ForEach(Array((expandedSubjects ? subjects : Array(subjects.prefix(6))).enumerated()), id: \.offset) { _, subject in
                        detailChip(subject)
                    }
                }
                if subjects.count > 6 {
                    Button(expandedSubjects ? "Show Fewer Subjects" : "Show All \(subjects.count) Subjects") {
                        expandedSubjects.toggle()
                    }
                    .buttonStyle(DetailsActionStyle())
                }
            }
        }
        .detailsCard()
    }

    private var sourcesCard: some View {
        DisclosureGroup {
            VStack(spacing: 8) {
                ForEach(Array(Set(metadataSources.values)).sorted(), id: \.self) { key in
                    Link(destination: URL(string: "https://openlibrary.org\(key)")!) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Open Library").font(.subheadline.weight(.semibold))
                                Text(metadataSources.filter { $0.value == key }.keys.sorted().map {
                                    OpenLibraryField(rawValue: $0)?.label ?? $0
                                }.joined(separator: ", "))
                                .font(.caption).foregroundStyle(AppPalette.secondaryText)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right.square")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(DetailsActionStyle())
                }
            }
            .padding(.top, 12)
        } label: {
            Label("Metadata Sources", systemImage: "link")
                .font(.subheadline.weight(.medium))
                .frame(minHeight: 44)
                .foregroundStyle(AppPalette.secondaryText)
        }
        .detailsCard()
    }

    private func heading(_ title: String) -> some View {
        Text(title).font(.caption.weight(.semibold))
            .foregroundStyle(AppPalette.secondaryText)
            .accessibilityAddTraits(.isHeader)
    }

    private func metadataRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(.caption).foregroundStyle(AppPalette.secondaryText)
                .frame(width: 72, alignment: .leading)
            Text(value).font(.subheadline).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detailChip(_ text: String, prominent: Bool = false) -> some View {
        Text(text)
            .font(.caption.weight(prominent ? .semibold : .regular))
            .foregroundStyle(prominent ? AppPalette.accent : AppPalette.text)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(prominent ? AppPalette.accent.opacity(0.1) : AppPalette.secondarySurface,
                        in: RoundedRectangle(cornerRadius: 8))
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct DetailsActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppPalette.accent)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(configuration.isPressed ? AppPalette.accent.opacity(0.12) : AppPalette.surface,
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(AppPalette.accent.opacity(0.45), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

private extension View {
    func detailsCard() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(AppPalette.border.opacity(0.65), lineWidth: 1))
    }
}

/// Content-sized chips wrap naturally, including with larger accessibility text.
private struct DetailsFlowLayout: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? 600).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(subviews, width: bounds.width)
        for (index, point) in arrangement.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                                  proposal: ProposedViewSize(width: arrangement.widths[index], height: nil))
        }
    }
    private func arrange(_ subviews: Subviews, width: CGFloat) -> (size: CGSize, positions: [CGPoint], widths: [CGFloat]) {
        let width = max(1, width)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var positions: [CGPoint] = []
        var widths: [CGFloat] = []
        for subview in subviews {
            let ideal = subview.sizeThatFits(.unspecified)
            let itemWidth = min(ideal.width, width)
            let size = subview.sizeThatFits(ProposedViewSize(width: itemWidth, height: nil))
            if x > 0 && x + itemWidth > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            positions.append(CGPoint(x: x, y: y))
            widths.append(itemWidth)
            x += itemWidth + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), positions, widths)
    }
}

enum BookDetailsText {
    static func nonempty(_ values: [String]) -> [String] {
        values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    static func series(_ series: BookSeries) -> String {
        guard let position = series.position, position.isFinite else { return series.name }
        return "\(series.name) · Book \(position.formatted(.number.grouping(.never)))"
    }

    /// Descriptions can contain HTML. Strip markup before decoding entities so
    /// remote images, stylesheets, and other embedded resources are never loaded.
    static func description(_ value: String?) -> String? {
        guard let value else { return nil }
        let stripped = value
            .replacingOccurrences(of: "(?is)<(script|style)\\b[^>]*>.*?</\\1\\s*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?i)<br\\s*/?>|</(?:p|div|li|h[1-6])\\s*>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // Decode text without the HTML attributed-string importer, which starts
        // WebKit and can re-enter SwiftUI's render loop when a record arrives.
        let entities = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
                        "nbsp": " ", "ndash": "–", "mdash": "—", "lsquo": "‘", "rsquo": "’",
                        "ldquo": "“", "rdquo": "”", "hellip": "…", "copy": "©", "reg": "®"]
        let pattern = try! NSRegularExpression(pattern: "&(#(?:[xX][0-9a-fA-F]+|[0-9]+)|[a-zA-Z]+);")
        var decoded = stripped
        for match in pattern.matches(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)).reversed() {
            guard let tokenRange = Range(match.range(at: 1), in: stripped),
                  let fullRange = Range(match.range, in: decoded) else { continue }
            let token = String(stripped[tokenRange])
            let replacement: String?
            if token.hasPrefix("#x") || token.hasPrefix("#X") {
                replacement = UInt32(token.dropFirst(2), radix: 16).flatMap(UnicodeScalar.init).map(String.init)
            } else if token.hasPrefix("#") {
                replacement = UInt32(token.dropFirst()).flatMap(UnicodeScalar.init).map(String.init)
            } else { replacement = entities[token] }
            if let replacement { decoded.replaceSubrange(fullRange, with: replacement) }
        }
        let cleaned = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = cleaned.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
        guard !descriptionPlaceholders.contains(normalized) else { return nil }
        // Linguistic word boundaries also support languages without spaces.
        var words = 0
        cleaned.enumerateSubstrings(in: cleaned.startIndex..<cleaned.endIndex, options: .byWords) { _, _, _, stop in
            words += 1
            if words > 1 { stop = true }
        }
        return words > 1 ? cleaned : nil
    }

    private static let descriptionPlaceholders: Set<String> = [
        "hardcover", "hard cover", "hardback", "hardcover edition", "hardback edition",
        "paperback", "paper back", "paperback edition", "softcover", "soft cover", "softback",
        "mass market paperback", "trade paperback", "kindle edition", "digital edition",
        "ebook", "e book", "electronic book", "audiobook", "audio book", "large print",
        "library binding", "a novel", "unknown", "n a", "not available", "no description",
        "no description available", "description unavailable", "none", "null"
    ]
}
