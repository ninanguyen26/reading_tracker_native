import ReadiumShared
import SwiftUI
import UIKit

private let readerToolbarIconSize: CGFloat = 15

struct ReaderScreen: View {
    @StateObject private var model: ReaderModel
    @Binding private var reactionJump: BookReaction?
    private let initialReaction: BookReaction?
    private let onShowDetails: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var sheet: Sheet?
    /// While dragging the slider, the position it would jump to.
    @State private var scrubbing: Double?
    @State private var scrubCommit: Task<Void, Never>?
    @State private var showingReactionConfirmation = false
    @State private var reactionJumpFailed = false
    @State private var reactionSaveFailed = false
    @State private var compactToolbar = false

    enum Sheet: Identifiable, Hashable {
        case settings, navigation, search
        case reactions(Locator)
        var id: Self { self }
    }

    init(book: Book, environment: AppEnvironment, initialReaction: BookReaction?, reactionJump: Binding<BookReaction?>,
         onShowDetails: @escaping () -> Void) {
        _model = StateObject(wrappedValue: ReaderModel(book: book, environment: environment))
        _reactionJump = reactionJump
        self.initialReaction = initialReaction
        self.onShowDetails = onShowDetails
    }

    private var palette: ReaderSettings.Palette { model.palette }

    var body: some View {
        ZStack {
            (model.book.format == .pdf ? palette.surround : palette.background).ignoresSafeArea()
            switch model.state {
            case .loading:
                ProgressView()
            case .failed(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text(message)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(palette.secondaryText)
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
        .overlay(alignment: .top) {
            // After opening a search result, a chip leads back to the results.
            if model.search.selected != nil && sheet == nil {
                searchChip
                    .padding(.top, model.chromeVisible ? 8 : 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                if showingReactionConfirmation, sheet == nil {
                    Label("Reaction saved", systemImage: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .environment(\.colorScheme, palette.isDark ? .dark : .light)
                        .allowsHitTesting(false)
                }
                if model.chromeVisible, case .ready = model.state {
                    bottomBar.transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    footer
                }
            }
        }
        .onGeometryChange(for: Bool.self) { geometry in
            geometry.size.width < 390
        } action: { compactToolbar = $0 }
        .navigationTitle(model.book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if compactToolbar {
                    Menu {
                        detailsButton
                        settingsButton
                    } label: {
                        toolbarLabel("Reader Options", systemImage: "ellipsis")
                    }
                } else {
                    detailsButton
                }
                Button { sheet = .search } label: {
                    toolbarLabel("Search", systemImage: "magnifyingglass")
                }
                .disabled(!model.isSearchable)
                Button { sheet = .navigation } label: {
                    toolbarLabel("Contents and Bookmarks", systemImage: "list.bullet")
                }
                if !compactToolbar {
                    settingsButton
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 0) {
                    bookmarkButton
                    ReactionToolbarButton(
                        isEnabled: model.locator != nil,
                        onOpen: openReactionPicker,
                        onQuickPick: saveQuickReaction
                    )
                    .frame(width: 44, height: 44)
                }
                .fixedSize()
            }
        }
        .toolbar(model.chromeVisible ? .visible : .hidden, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(palette.isDark ? .dark : .light, for: .navigationBar)
        .statusBarHidden(!model.chromeVisible)
        .animation(.easeInOut(duration: 0.2), value: model.chromeVisible)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .settings:
                ReaderSettingsSheet(settings: $model.settings, format: model.book.format)
            case .navigation:
                NavigationSheet(model: model)
            case .search:
                SearchSheet(model: model)
            case .reactions(let location):
                ReactionPicker { kinds in
                    try await saveReactions(kinds, at: location)
                }
            }
        }
        .sheet(isPresented: Binding(get: { model.editing != nil && sheet == nil }, set: { if !$0 { model.editing = nil } })) {
            if let highlight = model.editingHighlight {
                HighlightSheet(model: model, highlight: highlight, focusNote: model.editing?.focusNote ?? false)
                    .id(highlight.id)
            }
        }
        .task {
            model.setSystemDark(colorScheme == .dark)
            await model.load(startingAt: initialReaction)
        }
        .task(id: model.navigator == nil ? nil : reactionJump?.id) {
            guard model.navigator != nil, let reaction = reactionJump else { return }
            let jumped = await model.go(to: reaction)
            if !Task.isCancelled, reactionJump?.id == reaction.id {
                reactionJumpFailed = !jumped
                reactionJump = nil
            }
        }
        .task(id: showingReactionConfirmation && sheet == nil) {
            guard showingReactionConfirmation, sheet == nil else { return }
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { showingReactionConfirmation = false }
        }
        .alert("Couldn’t open this spot", isPresented: $reactionJumpFailed) {
            Button("OK", role: .cancel) {}
        }
        .alert("Couldn’t save your reaction", isPresented: $reactionSaveFailed) {
            Button("OK", role: .cancel) {}
        }
        .onChange(of: colorScheme) { model.setSystemDark($0 == .dark) }
    }

    private var detailsButton: some View {
        Button(action: onShowDetails) {
            toolbarLabel("Book Details", systemImage: "info.circle")
        }
    }

    private var settingsButton: some View {
        Button { sheet = .settings } label: {
            toolbarLabel("Reading Settings", systemImage: "textformat.size")
        }
    }

    private func toolbarLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: readerToolbarIconSize))
        }
    }

    private var bookmarkButton: some View {
        let bookmarked = model.currentBookmark != nil
        return Button { model.toggleBookmark() } label: {
            Image(systemName: bookmarked ? "bookmark.fill" : "bookmark")
                .font(.system(size: readerToolbarIconSize))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.locator == nil)
        .accessibilityLabel(bookmarked ? "Remove Bookmark" : "Add Bookmark")
    }

    private func openReactionPicker() {
        guard let location = model.locator else { return }
        showingReactionConfirmation = false
        sheet = .reactions(location)
    }

    private func saveQuickReaction(_ kind: ReactionKind) {
        guard let location = model.locator else { return }
        Task {
            do {
                try await saveReactions([kind], at: location)
            } catch {
                reactionSaveFailed = true
            }
        }
    }

    private func saveReactions(_ kinds: Set<ReactionKind>, at location: Locator) async throws {
        showingReactionConfirmation = false
        try await model.saveReactions(kinds, at: location)
        showingReactionConfirmation = true
    }

    private var searchChip: some View {
        HStack(spacing: 0) {
            Button { sheet = .search } label: {
                Label("Results for “\(model.search.query)”", systemImage: "magnifyingglass")
                    .font(.footnote.weight(.medium))
                    .padding(.leading, 12)
                    .padding(.vertical, 8)
            }
            Button { model.clearSearch() } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .padding(10)
            }
            .accessibilityLabel("Clear Search")
        }
        .foregroundStyle(.primary)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .environment(\.colorScheme, palette.isDark ? .dark : .light)
    }

    /// Shown with the toolbar: a slider to move through the book.
    private var bottomBar: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(get: { scrubbing ?? model.progression }, set: { scrub(to: $0) }),
                in: 0...1
            ) { editing in
                if !editing { commitScrub() }
            }
            .accessibilityLabel("Position in book")
            .accessibilityIdentifier("position-slider")
            HStack {
                Text(model.chapterTitle ?? "").lineLimit(1)
                Spacer(minLength: 8)
                Text(scrubbing.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? model.progressLabel)
                    .monospacedDigit()
                    .accessibilityIdentifier("reader-progress")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background(.bar, ignoresSafeAreaEdges: .bottom)
        .environment(\.colorScheme, palette.isDark ? .dark : .light)
    }

    /// Jumps once the slider settles. Not every way of moving a slider ends with
    /// an editing callback (VoiceOver adjustments, for one), so a short pause counts too.
    private func scrub(to value: Double) {
        scrubbing = value
        scrubCommit?.cancel()
        scrubCommit = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            if !Task.isCancelled { commitScrub() }
        }
    }

    private func commitScrub() {
        scrubCommit?.cancel()
        guard let target = scrubbing else { return }
        model.go(toProgression: target)
        scrubbing = nil
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
        .foregroundStyle(palette.secondaryText)
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
        .allowsHitTesting(false)
    }
}

/// UIKit handles the menu gesture alongside the button's regular tap.
private struct ReactionToolbarButton: UIViewRepresentable {
    let isEnabled: Bool
    let onOpen: () -> Void
    let onQuickPick: (ReactionKind) -> Void

    final class Coordinator {
        var onOpen: () -> Void
        var onQuickPick: (ReactionKind) -> Void

        init(button: ReactionToolbarButton) {
            onOpen = button.onOpen
            onQuickPick = button.onQuickPick
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(button: self) }

    func makeUIView(context: Context) -> UIButton {
        let coordinator = context.coordinator
        let button = UIButton(type: .system, primaryAction: UIAction { [weak coordinator] _ in
            coordinator?.onOpen()
        })
        let symbolSize = UIImage.SymbolConfiguration(pointSize: readerToolbarIconSize)
        button.setImage(UIImage(systemName: "face.smiling", withConfiguration: symbolSize), for: .normal)
        button.accessibilityLabel = "Log Reactions"
        button.accessibilityHint = "Touch and hold to save one reaction."
        button.menu = UIMenu(children: ReactionKind.allCases.map { kind in
            UIAction(title: "\(kind.emoji) \(kind.label)") { [weak coordinator] _ in
                coordinator?.onQuickPick(kind)
            }
        })
        button.showsMenuAsPrimaryAction = false
        button.preferredMenuElementOrder = .fixed
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        button.isEnabled = isEnabled
        context.coordinator.onOpen = onOpen
        context.coordinator.onQuickPick = onQuickPick
    }
}
