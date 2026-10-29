import Foundation
import ReadiumNavigator
import ReadiumShared
import SwiftUI

/// How books look. One set of settings applies to every book.
struct ReaderSettings: Codable, Equatable {
    enum Theme: String, CaseIterable, Codable, Identifiable {
        case system, light, sepia, dark
        var id: String { rawValue }
        var label: String {
            switch self {
            case .system: "Auto"
            case .light: "White"
            case .sepia: "Sepia"
            case .dark: "Dark"
            }
        }
    }

    enum Font: String, CaseIterable, Codable, Identifiable {
        case original, serif, sans
        var id: String { rawValue }
        var label: String {
            switch self {
            case .original: "Original"
            case .serif: "Serif"
            case .sans: "Sans"
            }
        }
    }

    enum Spacing: String, CaseIterable, Codable, Identifiable {
        case tight, normal, loose
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    enum Margins: String, CaseIterable, Codable, Identifiable {
        case narrow, normal, wide
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    var theme: Theme = .system
    /// 1.0 is the book's own size.
    var fontSize: Double = 1.0
    var font: Font = .original
    var spacing: Spacing = .normal
    var margins: Margins = .normal
    var scroll = false

    static let fontSizeRange = 0.7 ... 2.0
    static let fontSizeStep = 0.1

    /// The theme actually shown, resolving "Auto" against the system appearance.
    func resolvedTheme(systemDark: Bool) -> Theme {
        theme == .system ? (systemDark ? .dark : .light) : theme
    }

    // MARK: Readium preferences

    func epubPreferences(systemDark: Bool) -> EPUBPreferences {
        // Custom fonts and spacing only take effect with the book's own styles turned off.
        let customTypography = font != .original || spacing != .normal
        return EPUBPreferences(
            fontFamily: {
                switch font {
                case .original: nil
                case .serif: .iowanOldStyle
                case .sans: .sansSerif
                }
            }(),
            fontSize: fontSize,
            lineHeight: {
                switch spacing {
                case .tight: 1.3
                case .normal: customTypography ? 1.5 : nil
                case .loose: 1.8
                }
            }(),
            pageMargins: {
                switch margins {
                case .narrow: 0.5
                case .normal: 1.0
                case .wide: 1.6
                }
            }(),
            publisherStyles: !customTypography,
            scroll: scroll,
            theme: {
                switch resolvedTheme(systemDark: systemDark) {
                case .dark: .dark
                case .sepia: .sepia
                default: .light
                }
            }()
        )
    }

    func pdfPreferences(systemDark: Bool) -> PDFPreferences {
        PDFPreferences(
            backgroundColor: ReadiumNavigator.Color(hex: palette(systemDark: systemDark).surroundHex),
            scroll: scroll
        )
    }

    // MARK: Colors for the reader's own UI

    struct Palette {
        /// Matches Readium's page background for the theme
        let backgroundHex: String
        /// Behind PDF pages
        let surroundHex: String
        let secondaryTextHex: String
        let isDark: Bool

        var background: SwiftUI.Color { SwiftUI.Color(hex: backgroundHex) }
        var surround: SwiftUI.Color { SwiftUI.Color(hex: surroundHex) }
        var secondaryText: SwiftUI.Color { SwiftUI.Color(hex: secondaryTextHex) }
    }

    func palette(systemDark: Bool) -> Palette {
        switch resolvedTheme(systemDark: systemDark) {
        case .sepia: Palette(backgroundHex: "#FAF4E8", surroundHex: "#E9DFC9", secondaryTextHex: "#7A6650", isDark: false)
        case .dark: Palette(backgroundHex: "#000000", surroundHex: "#1C1C1E", secondaryTextHex: "#9A9A9A", isDark: true)
        default: Palette(backgroundHex: "#FFFFFF", surroundHex: "#EDEDED", secondaryTextHex: "#737373", isDark: false)
        }
    }
}

/// Saves the settings between launches.
enum ReaderSettingsStore {
    private static let key = "reader-settings"

    static func load(from defaults: UserDefaults = .standard) -> ReaderSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(ReaderSettings.self, from: data)
        else { return ReaderSettings() }
        return settings
    }

    static func save(_ settings: ReaderSettings, to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(settings), forKey: key)
    }
}

extension SwiftUI.Color {
    /// "#RRGGBB"
    init(hex: String) {
        let value = UInt64(hex.dropFirst(), radix: 16) ?? 0
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
