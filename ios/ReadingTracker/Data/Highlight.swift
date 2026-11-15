import Foundation
import GRDB
import struct ReadiumShared.Locator
import UIKit

/// A highlighted passage, optionally with a note.
struct Highlight: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "highlight"

    enum Color: String, Codable, CaseIterable, Identifiable, Sendable, DatabaseValueConvertible {
        case yellow, green, blue, pink, purple
        var id: String { rawValue }
        var label: String { rawValue.capitalized }

        func uiColor(in palette: HighlightPalette) -> UIColor {
            palette.uiColor(for: self)
        }

        /// Convenience using the globally saved palette.
        var uiColor: UIColor { uiColor(in: HighlightPaletteStore.load()) }
    }

    /// Where a PDF highlight sits: a rectangle on a page, in PDF page coordinates.
    struct PageRect: Codable, Hashable, Sendable {
        var page: Int
        var x: Double
        var y: Double
        var width: Double
        var height: Double

        var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    }

    var id: String
    var bookId: String
    /// A Readium `Locator` as JSON, used to jump to the highlight
    var locator: String
    var text: String
    var color: Color
    var note: String
    /// 0…1 through the whole book, for ordering
    var progression: Double
    var chapter: String?
    /// PDF only: the highlighted area, as JSON-encoded `[PageRect]`
    var pdfRects: String?
    var createdAt: Date
    var updatedAt: Date

    var pageRects: [PageRect] {
        guard let data = pdfRects?.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([PageRect].self, from: data)) ?? []
    }

    var readerLocator: Locator? {
        guard let location = try? Locator(jsonString: locator) else { return nil }
        // In a PDF spread, the current page can differ from the page containing the selection.
        guard let page = pageRects.first?.page else { return location }
        return location.copy(locations: { $0.fragments = ["page=\(page + 1)"] })
    }

    static func encode(_ rects: [PageRect]) -> String? {
        guard !rects.isEmpty, let data = try? JSONEncoder().encode(rects) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
