import SwiftUI

/// Sage & Lantern. Named assets resolve light/dark appearance automatically.
/// Reader page colors deliberately remain in ReaderSettings.Palette.
enum AppPalette {
    static let background = Color("AppBackground")
    static let surface = Color("AppSurface")
    static let secondarySurface = Color("AppSecondarySurface")
    static let border = Color("AppBorder")
    static let text = Color("AppText")
    static let secondaryText = Color("AppSecondaryText")
    static let accent = Color.accentColor
    static let accentPressed = Color("AppAccentPressed")
    static let onAccent = Color("AppOnAccent")
    static let highlight = Color("AppHighlight")
    static let onHighlight = Color("AppOnHighlight")
    /// Keep the reference button's white mark readable in both appearances.
    static let addButtonHighlight = Color(hex: "#66816A")
    static let addButtonFill = Color(hex: "#526D59")
    static let addButtonEdge = Color(hex: "#3F5846")

    /// Status colors are separate from chart categories.
    static let success = Color("StatusSuccess")
    static let warning = Color("StatusWarning")
    static let error = Color("StatusError")

    enum ChartSeries: String, CaseIterable, Identifiable {
        case forest = "Forest"
        case amber = "Amber"
        case terracotta = "Terracotta"
        case slateBlue = "SlateBlue"
        case dustyRose = "DustyRose"
        case olive = "Olive"
        case teal = "Teal"
        var id: String { rawValue }
        var color: Color { Color("Chart" + rawValue) }

        /// Pair with labels and point symbols when displaying multiple lines.
        var dash: [CGFloat] {
            switch self {
            case .forest: []
            case .teal: [6, 3]
            case .terracotta: [2, 3]
            case .amber: [8, 3, 2, 3]
            case .slateBlue: [10, 4]
            case .dustyRose: [4, 3, 1, 3]
            case .olive: [12, 3, 3, 3]
            }
        }
    }

    /// Stable categorical order for Swift Charts foreground-style scales.
    static let chartColors = ChartSeries.allCases.map(\.color)
    /// Empty through highest activity; sequential rather than categorical.
    static let heatmapColors = (0...5).map { Color("Heatmap\($0)") }
}

/// Explicit foreground contrast for the light and dark accent colors.
struct AppPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .foregroundStyle(AppPalette.onAccent)
            .background(configuration.isPressed ? AppPalette.accentPressed : AppPalette.accent, in: Capsule())
            .opacity(enabled ? 1 : 0.5)
    }
}
