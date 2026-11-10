import Foundation
import ReadiumShared

/// Counts the text in reading order and maps TOC links to word offsets.
struct EPUBReadingIndex {
    private var resources: [AnyURL: Range<Int>] = [:]
    private var chapterStarts: [Int] = []
    private(set) var totalWords = 0

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

struct EPUBReadingPace: Codable {
    private var wordsPerMinute = 0.0
    private var activeSeconds = 0.0
    private var sampleCount = 0

    var learnedSpeed: Double? {
        guard sampleCount >= 3, activeSeconds >= 60 else { return nil }
        return wordsPerMinute
    }

    func speed(startingWith baseline: Double?) -> Double? {
        guard let learnedSpeed else { return baseline }
        guard let baseline else { return learnedSpeed }
        let weight = min(activeSeconds / 180, 1)
        return baseline + (learnedSpeed - baseline) * weight
    }

    /// Only count plausible reading intervals. Weight longer samples more heavily and let old samples fade.
    mutating func record(words: Double, seconds: Double) -> Bool {
        guard (2...120).contains(seconds), words >= 8 else { return false }
        let rate = words * 60 / seconds
        guard (60...900).contains(rate) else { return false }
        let priorSeconds = min(activeSeconds, 240)
        wordsPerMinute = (wordsPerMinute * priorSeconds + rate * seconds) / (priorSeconds + seconds)
        activeSeconds = min(priorSeconds + seconds, 240)
        sampleCount = min(sampleCount + 1, 3)
        return true
    }
}

enum EPUBReadingPaceStore {
    private static func key(for bookID: String?) -> String {
        bookID.map { "epub-reading-pace.\($0)" } ?? "epub-reading-pace"
    }

    static func load(bookID: String? = nil) -> EPUBReadingPace {
        guard let data = UserDefaults.standard.data(forKey: key(for: bookID)),
              let pace = try? JSONDecoder().decode(EPUBReadingPace.self, from: data) else { return EPUBReadingPace() }
        return pace
    }

    static func save(_ pace: EPUBReadingPace, bookID: String? = nil) {
        UserDefaults.standard.set(try? JSONEncoder().encode(pace), forKey: key(for: bookID))
    }
}
