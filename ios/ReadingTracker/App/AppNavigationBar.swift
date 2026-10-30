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
        List {
            Section("Your Library") {
                stat("Books", count: books.count, color: .forest)
                stat("In Progress", count: books.filter { $0.progression > 0 && $0.progression < 0.995 }.count, color: .teal)
                stat("Finished", count: books.filter { $0.progression >= 0.995 }.count, color: .olive)
                stat("Not Started", count: books.filter { $0.progression == 0 }.count, color: .slateBlue)
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

struct AppSettingsView: View {
    @State private var settings = ReaderSettingsStore.load()
    @State private var showingPreferences = false

    var body: some View {
        List {
            Section("Reading") {
                Button { showingPreferences = true } label: {
                    Label("Reading Preferences", systemImage: "textformat.size")
                }
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
        .onAppear { settings = ReaderSettingsStore.load() }
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
