import Foundation
import PDFKit
import ReadiumShared
import GRDB

enum BookPageSource: String, Codable, Sendable, DatabaseValueConvertible {
    case pdf, embedded, openLibrary, estimated
    var priority: Int {
        switch self { case .pdf: 0; case .embedded: 1; case .openLibrary: 2; case .estimated: 3 }
    }
}
struct BookPageCount: Sendable, Equatable {
    var count: Int
    var source: BookPageSource
    var editionKey: String? = nil
}

@MainActor
enum BookPageCounter {
    static let wordsPerPage = 250

    static func embedded(_ publication: Publication) -> BookPageCount? {
        if let count = publication.metadata.numberOfPages, count > 0 {
            return BookPageCount(count: count, source: .embedded)
        }
        func flatten(_ links: [Link]) -> [Link] { links.flatMap { [$0] + flatten($0.children) } }
        let links = flatten(publication.pageList)
        var seen = Set<String>()
        let titles = links.filter { seen.insert($0.href).inserted }.compactMap(\.title)
        guard titles.count == links.count, let count = paginationCount(titles) else { return nil }
        return BookPageCount(count: count, source: .embedded)
    }

    /// Sparse lists are navigation aids, not a reliable total. Require a complete,
    /// sequential page map; count front-matter Roman pages separately.
    nonisolated static func paginationCount(_ labels: [String]) -> Int? {
        guard !labels.isEmpty else { return nil }
        var arabic: [Int] = []
        var roman: [Int] = []
        for label in labels {
            let text = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                .replacingOccurrences(of: "^page\\s+", with: "", options: .regularExpression)
            if let n = Int(text), n > 0 { arabic.append(n) }
            else if let n = romanValue(text), arabic.isEmpty { roman.append(n) }
            else { return nil }
        }
        if !roman.isEmpty && roman != Array(1...roman.count) { return nil }
        if !arabic.isEmpty && arabic != Array(1...arabic.count) { return nil }
        return labels.count
    }

    private nonisolated static func romanValue(_ text: String) -> Int? {
        let values: [Character: Int] = ["i": 1, "v": 5, "x": 10, "l": 50, "c": 100, "d": 500, "m": 1000]
        guard !text.isEmpty, text.allSatisfy({ values[$0] != nil }) else { return nil }
        var total = 0
        var previous = 0
        for char in text.reversed() {
            let value = values[char]!
            total += value < previous ? -value : value
            previous = max(previous, value)
        }
        return total > 0 ? total : nil
    }

    nonisolated static func estimatedPages(words: Int) -> Int? {
        words > 0 ? (words - 1) / wordsPerPage + 1 : nil
    }
    nonisolated static func wordCount(_ text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { _, _, _, _ in count += 1 }
        return count
    }

    static func measure(publication: Publication, format: BookFormat, url: URL) async throws -> BookPageCount? {
        if format == .pdf {
            guard let count = PDFDocument(url: url)?.pageCount, count > 0 else { return nil }
            return BookPageCount(count: count, source: .pdf)
        }
        if let count = embedded(publication) { return count }
        // EPUBs sometimes have page-break markers without a navigation page-list.
        var labels: [String] = []
        var scannedWords = 0
        var completeScan = true
        for link in publication.readingOrder {
            try Task.checkCancellation()
            if let resource = publication.get(link), let data = try? await resource.read().get() {
                let scanner = EPUBPageBreakScanner()
                let parser = XMLParser(data: data)
                parser.shouldResolveExternalEntities = false
                parser.delegate = scanner
                if parser.parse() {
                    labels += scanner.labels
                    scannedWords += wordCount(scanner.bodyText)
                } else { completeScan = false }
            } else { completeScan = false }
        }
        if completeScan, let count = paginationCount(labels) { return BookPageCount(count: count, source: .embedded) }
        if completeScan, let count = estimatedPages(words: scannedWords) {
            return BookPageCount(count: count, source: .estimated)
        }
        guard let iterator = publication.content()?.iterator() else { return nil }
        var words = 0
        while let element = try await iterator.next() {
            try Task.checkCancellation()
            if let text = (element as? TextContentElement)?.text { words += wordCount(text) }
            await Task.yield()
        }
        guard let count = estimatedPages(words: words) else { return nil }
        return BookPageCount(count: count, source: .estimated)
    }
}

private final class EPUBPageBreakScanner: NSObject, XMLParserDelegate {
    var labels: [String] = []
    var bodyText = ""
    private var bodyDepth: Int?
    private var excludedDepth: Int?
    private var depth = 0
    private var markerDepth: Int?
    private var label = ""
    private var attributedLabel = false
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        depth += 1
        let name = String(elementName.split(separator: ":").last ?? "").lowercased()
        if name == "body" { bodyDepth = depth }
        if excludedDepth == nil && ["nav", "script", "style", "svg"].contains(name) { excludedDepth = depth }
        let isBreak = attributes["role"]?.split(separator: " ").contains("doc-pagebreak") == true ||
            attributes.contains { $0.key.hasSuffix(":type") && $0.value.split(separator: " ").contains("pagebreak") }
        if isBreak {
            markerDepth = depth
            label = attributes["aria-label"] ?? attributes["title"] ?? ""
            attributedLabel = !label.isEmpty
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if markerDepth != nil && !attributedLabel { label += string }
        if bodyDepth != nil && excludedDepth == nil && markerDepth == nil { bodyText += string }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if markerDepth == depth { labels.append(label); markerDepth = nil; label = "" }
        if excludedDepth == depth { excludedDepth = nil }
        if bodyDepth == depth { bodyDepth = nil }
        let name = String(elementName.split(separator: ":").last ?? "").lowercased()
        if bodyDepth != nil && excludedDepth == nil && ["p", "div", "section", "li", "br", "h1", "h2", "h3"].contains(name) { bodyText += " " }
        depth -= 1
    }
}

extension AppDatabase {
    func saveEmbeddedISBN(id: String, isbn: String) async throws {
        try await writer.write { db in
            try db.execute(sql: "UPDATE book SET isbn = ? WHERE id = ? AND (isbn IS NULL OR isbn = '')", arguments: [isbn, id])
        }
    }
    func savePageCount(id: String, measurement: BookPageCount) async throws {
        guard measurement.count > 0 else { return }
        try await writer.write { db in
            guard var book = try Book.fetchOne(db, key: id) else { return }
            if let source = book.pageCountSource, source.priority < measurement.source.priority { return }
            book.pageCount = measurement.count
            book.pageCountSource = measurement.source
            book.pageCountEditionKey = measurement.editionKey
            try book.update(db)
        }
    }
}
