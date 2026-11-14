import SwiftUI

struct HomeMoodSection: View {
    let library: [Book]

    @EnvironmentObject private var environment: AppEnvironment
    @AppStorage("home-discover-feedback") private var storedFeedback = Data()
    @State private var wishlist: [DiscoveryBook]?
    @State private var wishlistFailed = false
    @State private var wishlistRetry = 0
    @State private var selectedMood: BookMood?
    @State private var showingAllMoods = false
    @State private var pools: [BookMood: Pool] = [:]
    @State private var request: Request?
    @State private var failedRequest: Request?
    @State private var preview: HomeRecommendation?

    private struct Pool {
        var candidates: [RecommendationCandidate]
        var nextOffset: Int?
        var shownIDs: Set<Int> = []
    }

    private struct Request: Equatable {
        let mood: BookMood
        let offset: Int
        var replacing: Set<Int> = []
        var attempt = UUID()
    }

    var body: some View {
        let moods = HomeRecommendations.orderedMoods(library: library)
        VStack(alignment: .leading, spacing: 12) {
            Text("In the mood for…")
                .font(.system(.title2, design: .serif).weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickMoods(moods), id: \.self) { mood in
                        Button { choose(mood) } label: {
                            Text(mood.rawValue.capitalized)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .foregroundStyle(selectedMood == mood ? AppPalette.accent : AppPalette.text)
                                .background(AppPalette.secondarySurface, in: Capsule())
                                .overlay(Capsule().strokeBorder(selectedMood == mood ? AppPalette.accent : .clear))
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedMood == mood ? .isSelected : [])
                        .accessibilityIdentifier("mood-chip-\(mood.rawValue)")
                    }
                    Button("All moods") { showingAllMoods = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppPalette.accent)
                        .frame(minHeight: 44)
                }
            }
            if let mood = selectedMood {
                results(for: mood)
            }
        }
        .sheet(isPresented: $showingAllMoods) {
            NavigationStack {
                List(moods, id: \.self) { mood in
                    Button {
                        choose(mood)
                        showingAllMoods = false
                    } label: {
                        HStack {
                            Text(mood.rawValue.capitalized)
                            Spacer()
                            if mood == selectedMood { Image(systemName: "checkmark") }
                        }
                        .foregroundStyle(AppPalette.text)
                    }
                    .accessibilityAddTraits(mood == selectedMood ? .isSelected : [])
                }
                .navigationTitle("All moods")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingAllMoods = false }
                    }
                }
            }
        }
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

    private func quickMoods(_ moods: [BookMood]) -> [BookMood] {
        let featured = Array(moods.prefix(4))
        guard let selectedMood, !featured.contains(selectedMood) else { return featured }
        return featured + [selectedMood]
    }

    private func choose(_ mood: BookMood) {
        guard mood != selectedMood else { return }
        selectedMood = mood
        failedRequest = nil
        request = pools[mood] == nil ? Request(mood: mood, offset: 0) : nil
    }

    @ViewBuilder private func results(for mood: BookMood) -> some View {
        if wishlistFailed {
            Button("Try again") { wishlistRetry += 1 }
        } else if let pool = pools[mood], let wishlist {
            let feedback = (try? JSONDecoder().decode([Int: RecommendationFeedback].self, from: storedFeedback)) ?? [:]
            let unseen = HomeRecommendations.ranked(
                candidates: pool.candidates, library: library, wishlist: wishlist, feedback: feedback,
                excluding: pool.shownIDs, limit: HomeRecommendations.count * 2
            )
            let picks = Array(unseen.prefix(HomeRecommendations.count))
            if !picks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(picks) { pick in
                            Button { preview = pick } label: {
                                DiscoveryCover(book: pick.book).frame(width: 96)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(pick.book.title)
                            .accessibilityIdentifier("mood-cover-\(pick.id)")
                        }
                    }
                    .padding(.vertical, 2)
                }
                .id(mood)
            } else if request == nil, failedRequest == nil {
                Text("No more matches yet.")
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.secondaryText)
            }
            if request == nil, failedRequest == nil, unseen.count > picks.count || pool.nextOffset != nil {
                Button("More mood picks") {
                    if unseen.count >= picks.count + HomeRecommendations.count || pool.nextOffset == nil {
                        pools[mood]?.shownIDs.formUnion(picks.map(\.id))
                    } else if let offset = pool.nextOffset {
                        request = Request(mood: mood, offset: offset, replacing: Set(picks.map(\.id)))
                    }
                }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
            }
        }
        if request != nil {
            ProgressView().accessibilityLabel("Loading mood picks")
        } else if let failure = failedRequest {
            HStack {
                Text("Couldn’t load mood picks.").foregroundStyle(AppPalette.secondaryText)
                Button("Try again") {
                    failedRequest = nil
                    request = Request(mood: failure.mood, offset: failure.offset, replacing: failure.replacing)
                }
            }
            .font(.subheadline)
        }
    }

    private func load(_ work: Request) async {
        do {
            let page = try await BookDiscoveryClient.books(for: work.mood, offset: work.offset)
            guard !Task.isCancelled, request == work else { return }
            let wanted = work.mood.rawValue
            var pool = pools[work.mood] ?? Pool(candidates: [], nextOffset: nil)
            var seen = Set(pool.candidates.map(\.id))
            pool.candidates += page.candidates.filter {
                $0.moods.contains { $0.lowercased() == wanted } && seen.insert($0.id).inserted
            }
            if !page.candidates.isEmpty { pool.shownIDs.formUnion(work.replacing) }
            pool.nextOffset = page.nextOffset
            pools[work.mood] = pool
            request = nil
        } catch {
            guard !Task.isCancelled, request == work else { return }
            failedRequest = work
            request = nil
        }
    }
}
