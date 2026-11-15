import SwiftUI

enum AppTab: String, CaseIterable {
    case home, library, stats, settings

    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .home: "house"
        case .library: "books.vertical"
        case .stats: "chart.bar"
        case .settings: "gearshape"
        }
    }
}

struct AppNavigationBar: View {
    @Binding var selection: AppTab
    let addBooks: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            tab(.home)
            tab(.library)
            Button(action: addBooks) {
                ZStack {
                    Capsule().fill(.white).frame(width: 1.5, height: 20)
                    Capsule().fill(.white).frame(width: 20, height: 1.5)
                }
                    .frame(width: 60, height: 60)
                    .background(
                        RadialGradient(colors: [AppPalette.addButtonHighlight, AppPalette.addButtonFill, AppPalette.addButtonEdge], center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 60),
                        in: Circle()
                    )
                    .overlay(Circle().strokeBorder(AppPalette.addButtonEdge, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add Books")
            .offset(y: -10)
            .frame(maxWidth: .infinity)
            tab(.stats)
            tab(.settings)
        }
        .frame(height: 64)
        .background {
            CenterNotch()
                .fill(AppPalette.surface)
                .shadow(color: .black.opacity(0.05), radius: 5, y: -2)
                .ignoresSafeArea(edges: .bottom)
        }
        .padding(.top, 10)
    }

    private func tab(_ tab: AppTab) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: 5) {
                Image(systemName: selection == tab ? tab.symbol + ".fill" : tab.symbol)
                    .font(.system(size: 22, weight: .regular))
                    .frame(height: 25)
                Text(tab.title)
                    .font(.caption2.weight(selection == tab ? .semibold : .regular))
            }
            .foregroundStyle(selection == tab ? AppPalette.accent : AppPalette.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tab-" + tab.rawValue)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }
}

private struct CenterNotch: Shape {
    func path(in rect: CGRect) -> Path {
        let center = rect.midX
        var path = Path()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: center - 57, y: 0))
        // Rounded shoulders lead into a circular U, with space around the button.
        path.addCurve(to: CGPoint(x: center - 41, y: 22), control1: CGPoint(x: center - 45, y: 0), control2: CGPoint(x: center - 41, y: 7))
        path.addCurve(to: CGPoint(x: center, y: 63), control1: CGPoint(x: center - 41, y: 44.64), control2: CGPoint(x: center - 22.64, y: 63))
        path.addCurve(to: CGPoint(x: center + 41, y: 22), control1: CGPoint(x: center + 22.64, y: 63), control2: CGPoint(x: center + 41, y: 44.64))
        path.addCurve(to: CGPoint(x: center + 57, y: 0), control1: CGPoint(x: center + 41, y: 7), control2: CGPoint(x: center + 45, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct LibraryStatsView: View {
    let books: [Book]

    var body: some View {
        let counts = Dictionary(grouping: books, by: \.readingStatus).mapValues(\.count)
        List {
            Section("Your Library") {
                LibraryCountChart(total: books.count, counts: counts)
            }
            .listRowBackground(AppPalette.surface)
            Section("Formats") {
                stat("EPUB", count: books.filter { $0.format == .epub }.count, color: .forest)
                stat("PDF", count: books.filter { $0.format == .pdf }.count, color: .teal)
            }
            .listRowBackground(AppPalette.surface)
        }
        .scrollContentBackground(.hidden)
        .background(AppPalette.background)
        .foregroundStyle(AppPalette.text)
    }

    private func stat(_ title: String, count: Int, color: AppPalette.ChartSeries) -> some View {
        HStack {
            Circle().fill(color.color).frame(width: 9, height: 9).accessibilityHidden(true)
            Text(title)
            Spacer()
            Text(count.formatted()).monospacedDigit().foregroundStyle(AppPalette.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LibraryCountChart: View {
    let total: Int
    let counts: [ReadingStatus: Int]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var countLabelSpace: CGFloat = 28
    @State private var barsVisible = false

    private let maxBarHeight: CGFloat = 120

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            column("Total", count: total, color: .forest)
            column(ReadingStatus.tbr.label, count: counts[.tbr, default: 0], color: .slateBlue)
            column(ReadingStatus.reading.label, count: counts[.reading, default: 0], color: .teal)
            column(ReadingStatus.finished.label, count: counts[.finished, default: 0], color: .olive)
            column(ReadingStatus.dnf.label, count: counts[.dnf, default: 0], color: .terracotta)
        }
        .background(alignment: .top) {
            Rectangle()
                .fill(AppPalette.border)
                .frame(height: 1)
                .offset(y: maxBarHeight + countLabelSpace)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
        .onAppear { barsVisible = true }
        .onDisappear { barsVisible = false }
    }

    private func column(_ title: String, count: Int, color: AppPalette.ChartSeries) -> some View {
        let barHeight = barsVisible || reduceMotion ? maxBarHeight * CGFloat(count) / CGFloat(max(total, 1)) : 0

        return VStack(spacing: 8) {
            VStack(spacing: 4) {
                Text(count.formatted())
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                RoundedRectangle(cornerRadius: 5)
                    .fill(color.color)
                    .frame(maxWidth: 36)
                    .frame(height: barHeight)
            }
            .frame(height: maxBarHeight + countLabelSpace, alignment: .bottom)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.65), value: barHeight)

            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppPalette.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(count.formatted())")
    }
}

struct AppSettingsView: View {
    @State private var settings = ReaderSettingsStore.load()
    @State private var showingPreferences = false
    @State private var activePalette = HighlightPaletteStore.load()
    @State private var paletteExpanded = false

    var body: some View {
        List {
            Section("Reading") {
                Button { showingPreferences = true } label: {
                    Label("Reading Preferences", systemImage: "textformat.size")
                }
            }
            .listRowBackground(AppPalette.surface)
            Section("Highlight Colors") {
                DisclosureGroup(isExpanded: $paletteExpanded) {
                    ForEach(HighlightPalette.all) { palette in
                        Button {
                            activePalette = palette
                            HighlightPaletteStore.save(palette)
                            paletteExpanded = false
                        } label: {
                            HStack(spacing: 12) {
                                HStack(spacing: 5) {
                                    ForEach([palette.colors.0, palette.colors.1, palette.colors.2,
                                             palette.colors.3, palette.colors.4], id: \.self) { hex in
                                        Circle()
                                            .fill(Color(hex: hex))
                                            .frame(width: 20, height: 20)
                                    }
                                }
                                Text(palette.name)
                                    .foregroundStyle(AppPalette.text)
                                Spacer()
                                if activePalette == palette {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(AppPalette.accent)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } label: {
                    HStack(spacing: 10) {
                        HStack(spacing: 5) {
                            ForEach([activePalette.colors.0, activePalette.colors.1, activePalette.colors.2,
                                     activePalette.colors.3, activePalette.colors.4], id: \.self) { hex in
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 20, height: 20)
                            }
                        }
                        Text(activePalette.name)
                            .foregroundStyle(AppPalette.text)
                    }
                }
                .tint(AppPalette.accent)
            }
            .listRowBackground(AppPalette.surface)
            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                Text("Your imported books are stored on this device.")
                    .foregroundStyle(AppPalette.secondaryText)
            }
            .listRowBackground(AppPalette.surface)
        }
        .scrollContentBackground(.hidden)
        .background(AppPalette.background)
        .foregroundStyle(AppPalette.text)
        .onAppear {
            settings = ReaderSettingsStore.load()
            activePalette = HighlightPaletteStore.load()
        }
        .sheet(isPresented: $showingPreferences) {
            ReaderSettingsSheet(settings: $settings, format: .epub)
        }
        .onChange(of: settings) { ReaderSettingsStore.save($0) }
    }
}

#if DEBUG
struct AppNavigationBar_Previews: PreviewProvider {
    static var previews: some View {
        ZStack(alignment: .bottom) {
            AppPalette.background.ignoresSafeArea()
            AppNavigationBar(selection: .constant(.library), addBooks: {})
        }
        .tint(AppPalette.accent)
        .previewDisplayName("Navigation")
    }
}
#endif
