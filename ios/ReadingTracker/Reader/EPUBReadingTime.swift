import Foundation
import ReadiumShared

enum ReadingTime {
    static func duration(words: Double, wordsPerMinute: Int) -> String {
        let speed = ReaderSettings.readingSpeedRange.contains(wordsPerMinute)
            ? wordsPerMinute : ReaderSettings.defaultReadingSpeed
        let minutes = words / Double(speed)
        guard minutes >= 1 else { return "<1 min" }
        let rounded = Int(minutes.rounded())
        let hours = rounded / 60
        let remainder = rounded % 60
        return hours == 0 ? "About \(rounded) min" : "About \(hours) hr \(remainder) min"
    }
}

/// Counts the text in reading order and maps TOC links to word offsets.
struct EPUBReadingIndex {
    private var resources: [AnyURL: Range<Int>] = [:]
    private var chapterStarts: [Int] = []
    private(set) var totalWords = 0

    static func load(from url: URL) async throws -> Self? {
        let publication = try await ReadiumServices.shared.openPublication(at: url)
        return try await load(publication: publication, contents: [])
    }

    func wordsRemaining(savedLocator: String?, progression: Double) -> Double {
        let locator = savedLocator.flatMap { try? Locator(jsonString: $0) }
        let total = Double(totalWords)
        let offset = locator.flatMap { wordOffset(at: $0) } ?? total * progression
        return total - offset
    }

    static func load(publication: Publication, contents: [Link]) async throws -> Self? {
        func targets(_ links: [Link]) -> [AnyURL] {
            links.flatMap { [$0.url()] + targets($0.children) }
        }
        let chapters = Dictionary(grouping: Set(targets(contents)), by: { $0.removingFragment() })
        var index = Self()
        var hasMissingChapter = false

        for link in publication.readingOrder {
            try Task.checkCancellation()
            let href = link.url().removingFragment()
            let targets = chapters[href] ?? []
            let start = index.totalWords
            let anchors = Set(targets.compactMap(\.fragment))
            guard let (count, offsets) = try await measure(link, in: publication, anchors: anchors) else { return nil }
            index.totalWords += count
            if targets.contains(href) { index.chapterStarts.append(start) }
            index.chapterStarts += offsets.values.map { start + $0 }
            hasMissingChapter = hasMissingChapter || offsets.count != anchors.count
            index.resources[href] = start..<index.totalWords
        }

        guard index.totalWords > 0 else { return nil }
        index.chapterStarts = hasMissingChapter ? [] : Set(index.chapterStarts).sorted()
        return index
    }

    private static func measure(_ link: Link, in publication: Publication, anchors: Set<String>) async throws -> (Int, [String: Int])? {
        let mediaType = link.mediaType ?? .xhtml
        if mediaType.isBitmap || mediaType == .svg { return (0, [:]) }
        guard let resource = publication.get(link) else { return nil }
        let data = try await resource.read().get()
        let scanner = EPUBPageBreakScanner(anchors: anchors)
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = scanner
        if parser.parse(), parser.parserError == nil {
            return wordOffsets(in: scanner.bodyText, anchors: scanner.anchorOffsets)
        }
        // Readium can still display HTML with invalid XHTML markup. Keep book time if its text is readable.
        let fallback = DataResource(data: data)
        guard let extractor = DefaultResourceContentExtractorFactory().makeExtractor(for: fallback, mediaType: mediaType)
        else { return nil }
        let text = try await extractor.extractText(of: fallback).get()
        return (BookPageCounter.wordCount(text), [:])
    }

    private static func wordOffsets(in text: String, anchors: [String: Int]) -> (Int, [String: Int]) {
        guard !anchors.isEmpty else { return (BookPageCounter.wordCount(text), [:]) }
        let sorted = anchors.sorted { $0.value < $1.value }
        var offsets: [String: Int] = [:]
        var anchor = 0
        var words = 0
        var previous = text.startIndex
        var offset = 0
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords, .substringNotRequired]) { _, range, _, _ in
            offset += text.utf16.distance(from: previous, to: range.lowerBound)
            previous = range.lowerBound
            while anchor < sorted.count, sorted[anchor].value <= offset {
                offsets[sorted[anchor].key] = words
                anchor += 1
            }
            words += 1
        }
        for remaining in sorted.dropFirst(anchor) {
            offsets[remaining.key] = words
        }
        return (words, offsets)
    }

    func wordOffset(at locator: Locator) -> Double? {
        guard let range = resources[locator.href.removingFragment()],
              let progression = locator.locations.progression, progression.isFinite else { return nil }
        // Readium reports continuous progression within a resource, even when its screen pages reflow.
        return Double(range.lowerBound) + Double(range.count) * min(max(progression, 0), 1)
    }

    func wordsLeftInChapter(at locator: Locator, wordOffset: Double) -> Double? {
        guard resources[locator.href.removingFragment()]?.isEmpty == false,
              let first = chapterStarts.first, wordOffset >= Double(first) else { return nil }
        let end = chapterStarts.first { Double($0) > wordOffset } ?? totalWords
        return Double(end) - wordOffset
    }
}
