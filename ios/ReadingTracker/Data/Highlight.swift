import Foundation
import GRDB
import UIKit

/// A highlighted passage, optionally with a note.
struct Highlight: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "highlight"

    enum Color: String, Codable, CaseIterable, Identifiable, Sendable, DatabaseValueConvertible {
        case yellow, green, blue, pink
        var id: String { rawValue }
        var label: String { rawValue.capitalized }

        /// Same colors as the web app.
        var uiColor: UIColor {
            switch self {
            case .yellow: UIColor(red: 0.98, green: 0.80, blue: 0.08, alpha: 1)
            case .green: UIColor(red: 0.29, green: 0.87, blue: 0.50, alpha: 1)
            case .blue: UIColor(red: 0.38, green: 0.65, blue: 0.98, alpha: 1)
            case .pink: UIColor(red: 0.96, green: 0.45, blue: 0.71, alpha: 1)
            }
        }
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

    static func encode(_ rects: [PageRect]) -> String? {
        guard !rects.isEmpty, let data = try? JSONEncoder().encode(rects) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
