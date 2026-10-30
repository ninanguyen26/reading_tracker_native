import SwiftUI

struct BookDetailsScreen: View {
    let book: Book
    let coverURL: URL?
    var onRead: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    private let description: String?

    init(book: Book, coverURL: URL?, onRead: (() -> Void)? = nil) {
        self.book = book
        self.coverURL = coverURL
        self.onRead = onRead
        description = BookDetailsText.description(book.description)
    }
    private var series: [BookSeries] { book.series.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    private var subjects: [String] { BookDetailsText.nonempty(book.subjects) }
    private var languages: [String] { BookDetailsText.nonempty(book.languages) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(spacing: 12) {
                        BookCoverView(book: book, coverURL: coverURL)
                            .frame(width: 150)
                            .padding(.bottom, 8)
                        Text(book.title)
                            .font(.system(.title2, design: .serif).weight(.semibold))
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                        if !book.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           book.author != "Unknown author" {
                            Text(book.author)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        Text(book.format.label)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())
                        if let onRead {
                            Button(book.progression > 0 ? "Continue Reading" : "Read Book") {
                                dismiss()
                                onRead()
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    if let description {
                        section("Description") {
                            Text(description)
                                .textSelection(.enabled)
                                .accessibilityIdentifier("details-description")
                        }
                    }
                    if !series.isEmpty {
                        section("Series") {
                            ForEach(Array(series.enumerated()), id: \.offset) { _, item in
                                Text(BookDetailsText.series(item))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    if !subjects.isEmpty {
                        section("Subjects") {
                            Text(subjects.joined(separator: " · "))
                                .textSelection(.enabled)
                        }
                    }
                    if !languages.isEmpty {
                        section(languages.count == 1 ? "Language" : "Languages") {
                            ForEach(Array(languages.enumerated()), id: \.offset) { _, code in
                                Text(Locale.current.localizedString(forIdentifier: code) ?? code)
                            }
                        }
                    }
                }
                .frame(maxWidth: 600)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Book Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            content()
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        // Reintroduce only our own line breaks; escape literal angle brackets.
        let html = stripped.replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br>")
        let decoded = (try? NSAttributedString(
            data: Data(html.utf8),
            options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil
        ).string) ?? stripped
        let cleaned = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}
