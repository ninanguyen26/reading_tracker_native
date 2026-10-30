import Foundation

/// Highlights and notes as Markdown, the same format as the web app's export.
enum NotesExport {
    struct BookInfo {
        let title: String
        let author: String
    }

    /// One book, grouped by chapter in reading order. `depth` is the heading level of the title.
    static func markdown(for book: BookInfo, highlights: [Highlight], depth: Int = 1) -> String {
        var lines = ["\(String(repeating: "#", count: depth)) \(book.title)", "", "*\(book.author)*", ""]
        var chapter: String??
        for highlight in highlights.sorted(by: { ($0.progression, $0.createdAt) < ($1.progression, $1.createdAt) }) {
            if chapter != .some(highlight.chapter) {
                chapter = .some(highlight.chapter)
                if let title = highlight.chapter { lines += ["\(String(repeating: "#", count: depth + 1)) \(title)", ""] }
            }
            lines += highlight.text
                .split(whereSeparator: \.isNewline)
                .map { "> \($0.trimmingCharacters(in: .whitespaces))" }
            let note = highlight.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty { lines += ["", "**Note:** \(note)"] }
            lines.append("")
        }
        if highlights.isEmpty { lines += ["No highlights yet.", ""] }
        return lines.joined(separator: "\n")
    }

    static func fileName(for title: String) -> String {
        let safe = title.components(separatedBy: CharacterSet(charactersIn: "\\/:*?\"<>|")).joined()
            .trimmingCharacters(in: .whitespaces)
        return "\(safe.isEmpty ? "Book" : safe) - notes.md"
    }

    /// Writes the Markdown to a temporary file, for the share sheet.
    static func temporaryFile(named name: String, contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
