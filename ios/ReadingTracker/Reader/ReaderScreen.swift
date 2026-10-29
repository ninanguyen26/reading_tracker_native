import SwiftUI

struct ReaderScreen: View {
    @StateObject private var model: ReaderModel
    @Environment(\.colorScheme) private var colorScheme

    init(book: Book, environment: AppEnvironment) {
        _model = StateObject(wrappedValue: ReaderModel(book: book, environment: environment))
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            switch model.state {
            case .loading:
                ProgressView()
            case .failed(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(message)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding(32)
            case .ready(let viewController):
                // The book fills the screen; the toolbars float over it, so
                // showing or hiding them never reflows the page.
                ReaderContainer(viewController: viewController)
                    .ignoresSafeArea()
                    .accessibilityIdentifier("reader-content")
            }
        }
        .overlay(alignment: .top) {
            // The navigation bar is translucent; a frosted band behind it keeps
            // the title readable over the page.
            if model.chromeVisible {
                Color.clear
                    .frame(height: 0)
                    .background(.bar, ignoresSafeAreaEdges: .top)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) { footer }
        .navigationTitle(model.book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(model.chromeVisible ? .visible : .hidden, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .statusBarHidden(!model.chromeVisible)
        .animation(.easeInOut(duration: 0.2), value: model.chromeVisible)
        .task {
            model.setDarkMode(colorScheme == .dark)
            await model.load()
        }
        .onChange(of: colorScheme) { model.setDarkMode($0 == .dark) }
    }

    /// Always-visible position line, like a Kindle's footer.
    private var footer: some View {
        HStack(spacing: 12) {
            Text(model.chapterTitle ?? "")
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(model.progressLabel)
                .monospacedDigit()
                .accessibilityIdentifier("reader-progress")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
        .allowsHitTesting(false)
    }
}
