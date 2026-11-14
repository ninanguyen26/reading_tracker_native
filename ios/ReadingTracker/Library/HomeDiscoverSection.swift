import SwiftUI

struct HomeDiscoverSection: View {
    let library: [Book]
    @EnvironmentObject private var environment: AppEnvironment
    @AppStorage("home-discover-feedback") private var storedFeedback = Data()
    @AppStorage("home-discover-feedback-books") private var storedFeedbackBooks = Data()
    @State private var wishlist: [DiscoveryBook]?
    @State private var wishlistUnavailable = false
    @State private var wishlistRetry = 0
    @State private var selection: HomeRecommendation?
    @State private var visibleIDs: [Int] = []
    @State private var undo: Dismissal?
    @State private var candidates: [RecommendationCandidate] = []
    @State private var seen: [Int: DiscoveryBook] = [:]
    @State private var shownOnPage: [Int: DiscoveryBook] = [:]
    @State private var nextOffset: Int? = 0
    @State private var loading = false
    @State private var loadFailed = false
    @State private var loadAttempt = 0
    @State private var loadedAttempt: Int?
    @State private var catalogTaste: CatalogTaste?

    private struct CatalogTaste {
        let moods: [BookMood]
        let genres: [String]
    }

    private struct Dismissal: Identifiable {
        let id: Int
        let action: RecommendationFeedback
        let previousFeedback: RecommendationFeedback?
        let previousRow: [Int]
    }

    private var feedback: [Int: RecommendationFeedback] {
        (try? JSONDecoder().decode([Int: RecommendationFeedback].self, from: storedFeedback)) ?? [:]
    }

    private var feedbackBooks: [Int: RecommendationCandidate] {
        (try? JSONDecoder().decode([Int: RecommendationCandidate].self, from: storedFeedbackBooks)) ?? [:]
    }

    var body: some View {
        let ranked = wishlist.map {
            rank(candidates, wishlist: $0)
        } ?? []
        let picks = visiblePicks(in: ranked)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Discover")
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if nextOffset != nil && !loadFailed && !picks.isEmpty {
                    Button("More picks") { loadAttempt += 1 }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppPalette.accent)
                        .frame(minHeight: 44)
                        .disabled(loading)
                }
            }
            if let undo {
                HStack {
                    Text(undo.action == .alreadyRead ? "Marked as already read" : "Book hidden")
                        .foregroundStyle(AppPalette.secondaryText)
                    Spacer()
                    Button("Undo") { undoDismissal(undo) }
                        .foregroundStyle(AppPalette.accent)
                        .frame(minHeight: 44)
                }
                .font(.subheadline)
                .task(id: undo.id) {
                    do {
                        try await Task.sleep(for: .seconds(8))
                        self.undo = nil
                    } catch {}
                }
            }
            if !picks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(picks) { pick in
                            Button { selection = pick } label: {
                                DiscoveryCover(book: pick.book)
                                    .frame(width: 96)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(pick.book.title)
                            .accessibilityIdentifier("discover-cover-\(pick.id)")
                        }
                    }
                    .padding(.vertical, 2)
                }
                .accessibilityIdentifier("discover-covers")
            }
            if wishlistUnavailable {
                Button("Retry Discover") { wishlistRetry += 1 }
                    .foregroundStyle(AppPalette.accent)
            } else if loadFailed {
                Button("Retry picks") { loadAttempt += 1 }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppPalette.accent)
            } else if loading || wishlist == nil {
                ProgressView().accessibilityLabel("Loading Discover")
            } else if picks.isEmpty, nextOffset != nil {
                Button("More picks") { loadAttempt += 1 }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppPalette.accent)
            } else if picks.isEmpty {
                Text("No more picks right now.")
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.secondaryText)
            }
        }
        .accessibilityIdentifier("home-discover")
        .onChange(of: picks.map(\.id)) { _ in
            for pick in picks { shownOnPage[pick.id] = pick.book }
        }
        .task(id: loadAttempt) {
            guard loadedAttempt != loadAttempt else { return }
            await loadPage(wishlist: wishlist ?? [], attempt: loadAttempt)
        }
        .task(id: wishlistRetry) {
            wishlistUnavailable = false
            do {
                for try await books in environment.database.observeWishlist() {
                    wishlist = books
                }
            } catch {
                if !Task.isCancelled { wishlistUnavailable = true }
            }
        }
        .sheet(item: $selection) { pick in
            DiscoveryBookPreview(
                book: pick.book,
                recommendationReason: pick.reason,
                likedRecommendation: feedback[pick.id] == .moreLikeThis
            ) { action in
                apply(action, to: pick, currentRow: picks.map(\.id))
            }
        }
    }

    private func visiblePicks(in ranked: [HomeRecommendation]) -> [HomeRecommendation] {
        let byID = Dictionary(ranked.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let kept = visibleIDs.compactMap { byID[$0] }
        let replacements = ranked.filter { !visibleIDs.contains($0.id) }
        return Array((kept + replacements).prefix(HomeRecommendations.count))
    }

    private func rank(_ page: [RecommendationCandidate], wishlist: [DiscoveryBook],
                      excluding prior: [DiscoveryBook] = []) -> [HomeRecommendation] {
        HomeRecommendations.ranked(candidates: page, library: library, wishlist: wishlist + Array(seen.values) + prior,
                                   feedback: feedback, feedbackBooks: feedbackBooks, limit: HomeRecommendations.count * 2)
    }

    private func loadPage(wishlist initialWishlist: [DiscoveryBook], attempt: Int) async {
        guard nextOffset != nil else { return }
        loading = true
        loadFailed = false
        defer { if attempt == loadAttempt { loading = false } }
        let current = visiblePicks(in: rank(candidates, wishlist: initialWishlist))
        let prior = Array(shownOnPage.values) + current.map(\.book)
        let taste = catalogTaste ?? {
            let profile = HomeRecommendations.discoveryTaste(library: library, feedback: feedback, feedbackBooks: feedbackBooks)
            return CatalogTaste(moods: profile.moods, genres: profile.genres)
        }()
        catalogTaste = taste

        var fresh: [RecommendationCandidate] = []
        var offset = nextOffset
        do {
            for _ in 0..<3 {
                guard let pageOffset = offset else { break }
                let page = try await BookDiscoveryClient.discoverPicks(moods: taste.moods, genres: taste.genres, offset: pageOffset)
                try Task.checkCancellation()
                var ids = Set(fresh.map(\.id))
                fresh += page.candidates.filter { ids.insert($0.id).inserted }
                offset = page.nextOffset
                if rank(fresh, wishlist: self.wishlist ?? initialWishlist, excluding: prior).count >= HomeRecommendations.count { break }
            }
            let replacements = rank(fresh, wishlist: self.wishlist ?? initialWishlist, excluding: prior)
            if !replacements.isEmpty || current.isEmpty {
                for book in prior { seen[book.id] = book }
                shownOnPage = [:]
                candidates = fresh
                visibleIDs = []
                undo = nil
            }
            nextOffset = offset
            loadedAttempt = attempt
        } catch {
            if !Task.isCancelled {
                loadFailed = true
                loadedAttempt = attempt
            }
        }
    }

    private func apply(_ action: RecommendationFeedback, to pick: HomeRecommendation, currentRow: [Int]) {
        let id = pick.id
        var updated = feedback
        var books = feedbackBooks
        books[id] = pick.candidate
        if action == .moreLikeThis {
            updated[id] = updated[id] == .moreLikeThis ? nil : action
        } else {
            undo = Dismissal(id: id, action: action, previousFeedback: updated[id], previousRow: currentRow)
            updated[id] = action
            selection = nil
        }
        visibleIDs = currentRow
        storedFeedback = (try? JSONEncoder().encode(updated)) ?? Data()
        storedFeedbackBooks = (try? JSONEncoder().encode(books)) ?? Data()
    }

    private func undoDismissal(_ dismissal: Dismissal) {
        var updated = feedback
        updated[dismissal.id] = dismissal.previousFeedback
        visibleIDs = dismissal.previousRow
        storedFeedback = (try? JSONEncoder().encode(updated)) ?? Data()
        undo = nil
    }
}
