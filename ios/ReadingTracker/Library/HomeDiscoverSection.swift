import SwiftUI

struct HomeDiscoverSection: View {
    let library: [Book]
    @EnvironmentObject private var environment: AppEnvironment
    @AppStorage("home-discover-feedback") private var storedFeedback = Data()
    @State private var wishlist: [DiscoveryBook]?
    @State private var wishlistUnavailable = false
    @State private var wishlistRetry = 0
    @State private var selection: HomeRecommendation?
    @State private var visibleIDs: [Int] = []
    @State private var undo: Dismissal?
    @State private var feedbackChanged = false

    private struct Dismissal: Identifiable {
        let id: Int
        let action: RecommendationFeedback
        let previousFeedback: RecommendationFeedback?
        let previousRow: [Int]
    }

    private var feedback: [Int: RecommendationFeedback] {
        (try? JSONDecoder().decode([Int: RecommendationFeedback].self, from: storedFeedback)) ?? [:]
    }

    var body: some View {
        let ranked = wishlist.map {
            HomeRecommendations.ranked(library: library, wishlist: $0, feedback: feedback)
        } ?? []
        let picks = visiblePicks(in: ranked)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Discover")
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if ranked.count > picks.count {
                    Button("More picks") { morePicks(from: ranked, after: picks) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppPalette.accent)
                        .frame(minHeight: 44)
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
            } else if wishlistUnavailable {
                Button("Retry Discover") { wishlistRetry += 1 }
                    .foregroundStyle(AppPalette.accent)
            } else if wishlist != nil {
                Text("You’ve seen all of these picks.")
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.secondaryText)
            } else {
                ProgressView()
                    .accessibilityLabel("Loading Discover")
            }
        }
        .accessibilityIdentifier("home-discover")
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
                apply(action, to: pick.id, currentRow: picks.map(\.id))
            }
        }
    }

    private func visiblePicks(in ranked: [HomeRecommendation]) -> [HomeRecommendation] {
        let byID = Dictionary(ranked.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let kept = visibleIDs.compactMap { byID[$0] }
        let replacements = ranked.filter { !visibleIDs.contains($0.id) }
        return Array((kept + replacements).prefix(HomeRecommendations.count))
    }

    private func morePicks(from ranked: [HomeRecommendation], after picks: [HomeRecommendation]) {
        let current = Set(picks.map(\.id))
        let lastIndex = ranked.lastIndex { current.contains($0.id) } ?? 0
        let nextIndex = feedbackChanged ? ranked.startIndex : ranked.index(after: lastIndex)
        let rotated = ranked[nextIndex...] + ranked[..<nextIndex]
        visibleIDs = Array(rotated.filter { !current.contains($0.id) }.prefix(HomeRecommendations.count)).map(\.id)
        feedbackChanged = false
    }

    private func apply(_ action: RecommendationFeedback, to id: Int, currentRow: [Int]) {
        var updated = feedback
        if action != .alreadyRead { feedbackChanged = true }
        if action == .moreLikeThis {
            updated[id] = updated[id] == .moreLikeThis ? nil : action
        } else {
            undo = Dismissal(id: id, action: action, previousFeedback: updated[id], previousRow: currentRow)
            updated[id] = action
            selection = nil
        }
        visibleIDs = currentRow
        storedFeedback = (try? JSONEncoder().encode(updated)) ?? Data()
    }

    private func undoDismissal(_ dismissal: Dismissal) {
        var updated = feedback
        updated[dismissal.id] = dismissal.previousFeedback
        visibleIDs = dismissal.previousRow
        storedFeedback = (try? JSONEncoder().encode(updated)) ?? Data()
        undo = nil
    }
}
