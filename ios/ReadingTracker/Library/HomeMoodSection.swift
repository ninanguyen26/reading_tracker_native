import SwiftUI

struct HomeMoodSection: View {
    let library: [Book]
    let openMood: (BookMood, Bool) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        let moods = HomeRecommendations.orderedMoods(library: library)
        VStack(alignment: .leading, spacing: 12) {
            Text("In the mood for…")
                .font(.system(.title2, design: .serif).weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(moods, id: \.self) { mood in
                    moodChip(mood.rawValue.capitalized, emoji: emoji(for: mood)) {
                        openMood(mood, false)
                    }
                    .accessibilityIdentifier("mood-chip-\(mood.rawValue)")
                }
                moodChip("Surprise me", emoji: "🎲") {
                    if let mood = moods.randomElement() {
                        openMood(mood, true)
                    }
                }
                .accessibilityIdentifier("mood-chip-surprise")
                .accessibilityHint("Picks a mood for you")
            }
        }
    }

    private func moodChip(_ title: String, emoji: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(emoji)
                    .font(.body)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(AppPalette.text)
            .background(AppPalette.secondarySurface, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func emoji(for mood: BookMood) -> String {
        switch mood {
        case .adventurous: "🧭"
        case .challenging: "🧩"
        case .dark: "🖤"
        case .emotional: "❤️"
        case .funny: "😂"
        case .hopeful: "🌈"
        case .informative: "💡"
        case .inspiring: "✨"
        case .lighthearted: "🧸"
        case .mysterious: "🔎"
        case .reflective: "🧠"
        case .relaxing: "🍵"
        case .sad: "😢"
        case .tense: "⚡️"
        }
    }
}

struct MoodBooksScreen: View {
    let mood: BookMood
    let isSurprise: Bool
    let library: [Book]

    @EnvironmentObject private var environment: AppEnvironment
    @AppStorage("home-discover-feedback") private var storedFeedback = Data()
    @State private var wishlist: [DiscoveryBook]?
    @State private var wishlistFailed = false
    @State private var wishlistRetry = 0
    @State private var candidates: [RecommendationCandidate] = []
    @State private var nextOffset: Int?
    @State private var request: Request? = Request(offset: 0)
    @State private var failedRequest: Request?
    @State private var preview: HomeRecommendation?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    private struct Request: Equatable {
        let offset: Int
        var attempt = UUID()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if isSurprise {
                    Text(mood.rawValue.capitalized)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                }
                results
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("mood-books-scroll")
        .background(AppPalette.background)
        .navigationTitle(isSurprise ? "Surprise me" : mood.rawValue.capitalized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(item: $preview) { pick in
            DiscoveryBookPreview(book: pick.book, recommendationReason: pick.reason)
        }
        .task(id: request) {
            guard let work = request else { return }
            await load(work)
        }
        .task(id: wishlistRetry) {
            wishlistFailed = false
            do {
                for try await books in environment.database.observeWishlist() {
                    wishlist = books
                }
            } catch {
                if !Task.isCancelled { wishlistFailed = true }
            }
        }
    }

    @ViewBuilder private var results: some View {
        if wishlistFailed {
            Button("Try again") { wishlistRetry += 1 }
        } else if let wishlist {
            let feedback = (try? JSONDecoder().decode([Int: RecommendationFeedback].self, from: storedFeedback)) ?? [:]
            let picks = HomeRecommendations.ranked(
                candidates: candidates, library: library, wishlist: wishlist, feedback: feedback
            )
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(picks) { pick in
                    Button { preview = pick } label: {
                        DiscoveryCover(book: pick.book)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(pick.book.title)
                    .accessibilityIdentifier("mood-cover-\(pick.id)")
                }
            }
            if request == nil, failedRequest == nil {
                if picks.isEmpty {
                    Text(nextOffset == nil ? "No matching books yet." : "No matches on this page.")
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.secondaryText)
                }
                if let nextOffset {
                    Button("Load more books") { request = Request(offset: nextOffset) }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
            }
        }
        if request != nil || (wishlist == nil && !wishlistFailed && failedRequest == nil) {
            ProgressView().accessibilityLabel("Loading mood picks")
        } else if let failure = failedRequest {
            VStack(spacing: 8) {
                Text("Couldn’t load mood picks.").foregroundStyle(AppPalette.secondaryText)
                Button("Try again") {
                    failedRequest = nil
                    request = Request(offset: failure.offset)
                }
            }
            .font(.subheadline)
        }
    }

    private func load(_ work: Request) async {
        do {
            let page = try await BookDiscoveryClient.books(for: mood, offset: work.offset)
            guard !Task.isCancelled, request == work else { return }
            var seen = Set(candidates.map(\.id))
            candidates += page.candidates.filter {
                $0.moods.contains { $0.lowercased() == mood.rawValue } && seen.insert($0.id).inserted
            }
            nextOffset = page.nextOffset
            request = nil
        } catch {
            guard !Task.isCancelled, request == work else { return }
            failedRequest = work
            request = nil
        }
    }
}
