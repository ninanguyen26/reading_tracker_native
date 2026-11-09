import SwiftUI

struct BookDetailsScreen: View {
    @State private var book: Book
    let coverURL: URL?
    let fromReader: Bool
    let libraryBooks: [Book]
    let onRead: () -> Void
    let onDeleted: () -> Void
    let onOpenBook: (String) -> Void
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showingLookup = false
    @State private var showingGenres = false
    @State private var showingShelves = false
    @State private var confirmingDelete = false
    @State private var deletingBook = false
    @State private var deleteError: String?
    @State private var expandedDescription = false
    @State private var loadingPages = true
    @State private var showingContentWarnings = false
    @State private var readingStatusError: String?
    @State private var ratingError = false
    @State private var section: Section = .about
    private var description: String? { BookDetailsText.description(book.description) }

    private enum Section {
        case about, myReading
    }

    init(book: Book, coverURL: URL?, fromReader: Bool, libraryBooks: [Book],
         onRead: @escaping () -> Void, onDeleted: @escaping () -> Void, onOpenBook: @escaping (String) -> Void) {
        _book = State(initialValue: book)
        self.coverURL = coverURL
        self.fromReader = fromReader
        self.libraryBooks = libraryBooks
        self.onRead = onRead
        self.onDeleted = onDeleted
        self.onOpenBook = onOpenBook
    }
    private var languages: [String] { BookDetailsText.nonempty(book.languages) }
    private var metadataSources: [String: String] {
        var sources = book.openLibraryFields.filter {
            ($0.key != "description" || description != nil) && $0.key != "subjects" &&
            (OpenLibraryClient.validKey($0.value, kind: "books", suffix: "M") ||
             OpenLibraryClient.validKey($0.value, kind: "works", suffix: "W"))
        }
        if book.pageCountSource == .openLibrary, let key = book.pageCountEditionKey,
           OpenLibraryClient.validKey(key, kind: "books", suffix: "M") { sources["pages"] = key }
        for (field, url) in book.hardcoverFields where
            (field != "description" || description != nil) && Self.validHardcoverURL(url) {
            sources[field] = url
        }
        if book.pageCountSource == .hardcover, let url = book.pageCountEditionKey,
           Self.validHardcoverURL(url) { sources["pages"] = url }
        if let publicationYear = book.publicationYear, let url = publicationYear.sourceURL,
           Self.validHardcoverURL(url) { sources[publicationYear.label] = url }
        return sources
    }
    private static func validHardcoverURL(_ value: String) -> Bool {
        value.range(of: #"^https://hardcover\.app/books/[0-9]+(?:/editions/[0-9]+)?$"#,
                    options: .regularExpression) != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                bookHeader
                readingStatusControl
                progressRow
                Picker("Book Details Section", selection: $section) {
                    Text("About").tag(Section.about)
                    Text("My Reading").tag(Section.myReading)
                }
                .pickerStyle(.segmented)

                switch section {
                case .about:
                    about
                case .myReading:
                    BookJournal(bookID: book.id).detailsCard()
                }
            }
            .frame(maxWidth: 600)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { readFooter }
        .background(AppPalette.background)
        .foregroundStyle(AppPalette.text)
        .toolbarBackground(AppPalette.background, for: .navigationBar)
        .navigationTitle("Book Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { bookActions }
        }
        .disabled(deletingBook)
        .sheet(isPresented: $showingLookup) { OpenLibraryLookupScreen(book: book) { book = $0 } }
        .sheet(isPresented: $showingGenres) { BookGenreEditor(book: book) { book = $0 } }
        .sheet(isPresented: $showingShelves) { ManageBookShelvesSheet(bookID: book.id) }
        .alert("Delete “\(book.title)”?", isPresented: $confirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Book", role: .destructive, action: deleteBook)
        } message: {
            Text("This removes the book and its reading progress, bookmarks, highlights, rating, and journal entries from this device.")
        }
        .alert("Couldn’t delete book", isPresented: Binding(
            get: { deleteError != nil }, set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
        .alert("Couldn’t update reading status", isPresented: Binding(
            get: { readingStatusError != nil },
            set: { if !$0 { readingStatusError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(readingStatusError ?? "")
        }
        .task {
            do {
                for try await books in environment.database.observeBooks() {
                    if let saved = books.first(where: { $0.id == book.id }) { book = saved }
                }
            } catch { /* Keep already loaded details if observation ends. */ }
        }
        .task(id: book.id + "|" + (book.openLibraryEditionKey ?? "")) {
            await environment.importer.updatePageCount(for: book)
            loadingPages = false
        }
        .task(id: book.id) {
            await environment.importer.updatePublicationYears(id: book.id)
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

    private var bookActions: some View {
        Menu {
            Button { showingShelves = true } label: {
                Label("Manage Shelves", systemImage: "books.vertical")
            }
            Button(role: .destructive) { confirmingDelete = true } label: {
                Label("Delete Book", systemImage: "trash")
            }
        } label: {
            Label("Book Actions", systemImage: "ellipsis")
        }
        .disabled(deletingBook)
    }

    private func deleteBook() {
        guard !deletingBook else { return }
        deletingBook = true
        let book = book
        Task {
            do {
                try await environment.importer.delete(book)
                onDeleted()
            } catch {
                deletingBook = false
                deleteError = error.localizedDescription
            }
        }
    }

    private var readFooter: some View {
        Button(action: onRead) {
            Label(fromReader || book.progression > 0 ? "Continue Reading" : "Read Book", systemImage: "book")
                .frame(maxWidth: .infinity, minHeight: 24)
        }
        .buttonStyle(AppPrimaryButtonStyle())
        .frame(maxWidth: 600)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(AppPalette.surface, ignoresSafeAreaEdges: .bottom)
        .overlay(alignment: .top) { Divider().overlay(AppPalette.border) }
    }

    @ViewBuilder private var about: some View {
        if let description { synopsisCard(description) }
        genresCard
        if let moods = book.hardcoverMoods, !moods.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                heading("Moods")
                readingTagChips(moods, lowercase: true)
            }
            .detailsCard()
        }
        if let warnings = book.hardcoverContentWarnings, !warnings.isEmpty {
            contentWarningsCard(warnings)
        }
        metadataCard
        BookDiscoverySection(book: book, coverURL: coverURL, libraryBooks: libraryBooks, onOpenBook: onOpenBook)
        Button { showingLookup = true } label: {
            Label("Find Missing Details", systemImage: "magnifyingglass")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(DetailsActionStyle())
        .accessibilityIdentifier("find-missing-details")
        if !metadataSources.isEmpty { sourcesCard }
    }

    private var readingStatusControl: some View {
        HStack {
            heading("Reading Status")
            Spacer()
            Menu {
                ReadingStatusOptions(current: book.readingStatus) { status in
                    let id = book.id
                    Task {
                        do {
                            try await environment.database.setReadingStatus(status, for: [id])
                        } catch {
                            readingStatusError = error.localizedDescription
                        }
                    }
                }
            } label: {
                Label(book.readingStatus.label, systemImage: "chevron.up.chevron.down")
            }
            .buttonStyle(DetailsActionStyle())
            .accessibilityLabel("Reading Status")
            .accessibilityValue(book.readingStatus.label)
            .accessibilityIdentifier("book-reading-status")
        }
    }

    private var progressRow: some View {
        HStack(spacing: 10) {
            Text("Progress")
                .font(.caption.weight(.semibold))
            ProgressView(value: book.progression)
                .tint(AppPalette.accent)
            Text(book.progression.formatted(.percent.precision(.fractionLength(0))))
                .font(.caption.monospacedDigit())
        }
        .foregroundStyle(AppPalette.secondaryText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reading progress")
        .accessibilityValue(book.progression.formatted(.percent.precision(.fractionLength(0))))
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
                personalRatingControl
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    private var personalRatingControl: some View {
        Menu {
            ForEach(1...5, id: \.self) { stars in
                let label = stars == 1 ? "1 star" : "\(stars) stars"
                Button { setPersonalRating(stars) } label: {
                    if stars == book.personalRating {
                        Label(label, systemImage: "checkmark")
                    } else {
                        Text(label)
                    }
                }
            }
            if book.personalRating != nil {
                Button("Clear Rating") { setPersonalRating(nil) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your Rating")
                    .font(.caption)
                    .foregroundStyle(AppPalette.secondaryText)
                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: "star.fill")
                            .foregroundStyle(star <= (book.personalRating ?? 0) ? AppPalette.accent : Color.gray)
                    }
                }
                .font(.subheadline)
            }
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Your Rating")
        .accessibilityValue(book.personalRating.map { "\($0) out of 5" } ?? "Not rated")
        .accessibilityIdentifier("personal-rating")
        .alert("Couldn’t save your rating", isPresented: $ratingError) {
            Button("OK", role: .cancel) {}
        }
    }

    private func setPersonalRating(_ rating: Int?) {
        let id = book.id
        Task {
            do {
                try await environment.database.setPersonalRating(rating, for: id)
            } catch {
                ratingError = true
            }
        }
    }

    private func synopsisCard(_ description: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("Description")
            Text(synopsisText(description))
                .font(.subheadline)
                .lineSpacing(4)
                .textSelection(.enabled)
                .accessibilityIdentifier("details-description")
                .environment(\.openURL, OpenURLAction { url in
                    guard url.scheme == "book-description" else { return .systemAction }
                    withAnimation(.easeInOut(duration: 0.2)) { expandedDescription.toggle() }
                    return .handled
                })
        }
        .detailsCard()
    }

    private var pageCountLabel: String {
        guard let count = book.pageCount, count > 0 else { return loadingPages ? "Calculating…" : "Unavailable" }
        return count.formatted() + (book.pageCountSource == .estimated ? " (estimated)" : "")
    }

    private func synopsisText(_ description: String) -> AttributedString {
        guard description.count > 280 else { return AttributedString(description) }
        var excerpt = String(description.prefix(220)).trimmingCharacters(in: .whitespacesAndNewlines)
        if let boundary = excerpt.lastIndex(where: \.isWhitespace), excerpt[..<boundary].count > 140 {
            excerpt = String(excerpt[..<boundary])
        }
        var text = AttributedString(expandedDescription ? description + " " : excerpt + "… ")
        var action = AttributedString(expandedDescription ? "Show Less" : "Read More")
        action.link = URL(string: "book-description://toggle")!
        action.foregroundColor = AppPalette.accent
        action.underlineStyle = .single
        action.inlinePresentationIntent = .stronglyEmphasized
        text.append(action)
        return text
    }

    private var genresCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                heading("Genres")
                Spacer(minLength: 0)
                Button { showingGenres = true } label: {
                    Label("Edit", systemImage: "pencil")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppPalette.accent)
                        .padding(.top, 12)
                        .frame(minWidth: 44, minHeight: 44, alignment: .topTrailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit Genres")
                .padding(.top, -12)
            }
            DetailsFlowLayout(spacing: 8) {
                if book.genres.isEmpty {
                    detailChip("Unclassified")
                }
                ForEach(book.genres) { detailChip($0.displayName) }
            }
        }
        .detailsCard()
    }

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Metadata")
            metadataRow("Format", value: book.format.label)
            if let publicationYear = book.publicationYear {
                metadataRow(publicationYear.label, value: String(publicationYear.year))
            }
            metadataRow("Pages", value: pageCountLabel)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("details-pages")
            if !languages.isEmpty {
                metadataRow(languages.count == 1 ? "Language" : "Languages",
                            value: languages.map { Locale.current.localizedString(forIdentifier: $0) ?? $0 }.joined(separator: ", "))
            }
            if let rating = book.hardcoverRating, let count = book.hardcoverRatingsCount, count > 0 {
                hardcoverRatingRow(rating, count: count)
                    .accessibilityIdentifier("hardcover-rating")
            }
        }
        .detailsCard()
    }

    private func readingTagChips(_ tags: [String], lowercase: Bool = false) -> some View {
        DetailsFlowLayout(spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                detailChip(lowercase ? tag.lowercased() : tag)
            }
        }
    }

    private func contentWarningsCard(_ warnings: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation { showingContentWarnings.toggle() }
            } label: {
                HStack {
                    heading("Content Warnings")
                    Spacer()
                    Image(systemName: showingContentWarnings ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppPalette.secondaryText)
                        .accessibilityHidden(true)
                }
                .padding([.top, .horizontal], 16)
                .padding(.bottom, showingContentWarnings ? 10 : 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showingContentWarnings ? "Hide content warnings" : "Show content warnings")
            .accessibilityIdentifier("content-warnings-disclosure")

            if showingContentWarnings {
                readingTagChips(warnings)
                    .padding([.horizontal, .bottom], 16)
            }
        }
        .detailsCard(padding: 0)
    }

    private var sourcesCard: some View {
        DisclosureGroup {
            VStack(spacing: 8) {
                ForEach(Array(Set(metadataSources.values)).sorted(), id: \.self) { key in
                    Link(destination: URL(string: key.hasPrefix("https://hardcover.app/") ? key : "https://openlibrary.org\(key)")!) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(key.hasPrefix("https://hardcover.app/") ? "Hardcover" : "Open Library").font(.subheadline.weight(.semibold))
                                Text(metadataSources.filter { $0.value == key }.keys.sorted().map {
                                    $0 == "contentWarnings" ? "Content Warnings" :
                                        OpenLibraryField(rawValue: $0)?.label ?? $0.capitalized
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
}

func metadataRow(_ title: String, value: String) -> some View {
    metadataRow(title, value: Text(value))
}

private func metadataRow(_ title: String, value: Text) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(title).font(.caption).foregroundStyle(AppPalette.secondaryText)
            .frame(width: 120, alignment: .leading)
        value.font(.subheadline).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

func hardcoverRatingRow(_ rating: Double, count: Int) -> some View {
    let average = rating.formatted(.number.precision(.fractionLength(1)))
    let countLabel = "\(count.formatted()) \(count == 1 ? "rating" : "ratings")"
    return metadataRow("Hardcover Rating", value: Text("\(average) \(Image(systemName: "star.fill"))/5 · \(countLabel)"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hardcover rating, \(average) out of 5, \(countLabel)")
}

func detailChip(_ text: String) -> some View {
    Text(text)
        .font(.caption)
        .foregroundStyle(AppPalette.text)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(AppPalette.secondarySurface, in: RoundedRectangle(cornerRadius: 8))
        .fixedSize(horizontal: false, vertical: true)
}

struct DetailsActionStyle: ButtonStyle {
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

extension View {
    func detailsCard(padding: CGFloat = 16) -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(AppPalette.border.opacity(0.65), lineWidth: 1))
    }
}

/// Content-sized chips wrap naturally, including with larger accessibility text.
struct DetailsFlowLayout: Layout {
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

    static func languageCode(_ value: String?) -> String? {
        guard let value else { return nil }
        let identifier = Locale.canonicalLanguageIdentifier(from: value.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let code = Locale.Language(identifier: identifier).languageCode,
              let normalized = code.identifier(.alpha2) ?? code.identifier(.alpha3),
              !["und", "mul", "zxx"].contains(normalized) else { return nil }
        return normalized
    }

    static func previewSynopsis(_ value: String?) -> String? {
        guard let text = description(value) else { return nil }
        let lines = text.components(separatedBy: .newlines).filter { line in
            catalogExtent.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) == nil
        }
        return usableDescription(lines.joined(separator: "\n"))
    }

    private static let catalogExtent: NSRegularExpression = {
        let extent = #"(?:\d+(?:\s*[-–]\s*\d+)?\s*(?:pages?|pp?\.?|leaves)|\d+(?:[.,]\d+)?\s*(?:cm|mm|inches|in\.?)|ISBN(?:[- ](?:10|13))?\s*:?\s*(?:[0-9][- ]?){9,12}[0-9X])"#
        return try! NSRegularExpression(pattern: #"^\s*\#(extent)(?:\s*[,;:]\s*\#(extent))*[.;]?\s*$"#,
                                        options: .caseInsensitive)
    }()

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
        return usableDescription(decoded)
    }

    private static func usableDescription(_ text: String) -> String? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
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
