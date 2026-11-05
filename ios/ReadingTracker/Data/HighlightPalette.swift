import Foundation
import UIKit

struct HighlightPalette: Identifiable, Equatable {
    let id: String
    let name: String
    /// Hex colors for the five Highlight.Color slots: yellow, green, blue, pink, purple.
    let colors: (String, String, String, String, String)

    static func == (lhs: HighlightPalette, rhs: HighlightPalette) -> Bool { lhs.id == rhs.id }

    func uiColor(for slot: Highlight.Color) -> UIColor {
        let hex: String
        switch slot {
        case .yellow: hex = colors.0
        case .green:  hex = colors.1
        case .blue:   hex = colors.2
        case .pink:   hex = colors.3
        case .purple: hex = colors.4
        }
        return UIColor(hex: hex)
    }

    // MARK: Built-in palettes

    static let gardenParty = HighlightPalette(
        id: "gardenParty",
        name: "Garden Party",
        colors: ("#FACC14", "#4ADE80", "#60A5FA", "#F472B6", "#C084FC")
    )
    static let honeyAndDusk = HighlightPalette(
        id: "honeyAndDusk",
        name: "Honey & Dusk",
        colors: ("#F59E0B", "#FB923C", "#F87171", "#FDA4AF", "#FDE68A")
    )
    static let petalAndDusk = HighlightPalette(
        id: "petalAndDusk",
        name: "Petal & Dusk",
        colors: ("#6C0820", "#F2AEBC", "#F2DCDB", "#5A86CB", "#3D5D91")
    )
    static let emberAndMoss = HighlightPalette(
        id: "emberAndMoss",
        name: "Ember & Moss",
        colors: ("#EED9C4", "#DDA28A", "#B47A7A", "#8F9B6E", "#7B5E4A")
    )
    static let cloverAndCustard = HighlightPalette(
        id: "cloverAndCustard",
        name: "Clover & Custard",
        colors: ("#F0F7EA", "#FFFAE0", "#EEE59F", "#AAD480", "#75C97F")
    )

    static let all: [HighlightPalette] = [
        .gardenParty, .honeyAndDusk, .petalAndDusk, .emberAndMoss, .cloverAndCustard
    ]
}

enum HighlightPaletteStore {
    private static let key = "highlight-palette"

    static func load(from defaults: UserDefaults = .standard) -> HighlightPalette {
        guard let id = defaults.string(forKey: key),
              let palette = HighlightPalette.all.first(where: { $0.id == id })
        else { return .gardenParty }
        return palette
    }

    static func save(_ palette: HighlightPalette, to defaults: UserDefaults = .standard) {
        defaults.set(palette.id, forKey: key)
        NotificationCenter.default.post(name: .highlightPaletteDidChange, object: nil)
    }
}

extension Notification.Name {
    static let highlightPaletteDidChange = Notification.Name("highlightPaletteDidChange")
}

extension UIColor {
    convenience init(hex: String) {
        let value = UInt64(hex.dropFirst(), radix: 16) ?? 0
        self.init(
            red:   CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8)  & 0xFF) / 255,
            blue:  CGFloat(value         & 0xFF) / 255,
            alpha: 1
        )
    }
}
