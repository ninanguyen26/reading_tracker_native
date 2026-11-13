import Foundation

enum RecommendationFeedback: String, Codable, CaseIterable {
    case moreLikeThis, notForMe, alreadyRead

    var label: String {
        switch self {
        case .moreLikeThis: "More like this"
        case .notForMe: "Not for me"
        case .alreadyRead: "Already read"
        }
    }

    var symbol: String {
        switch self {
        case .moreLikeThis: "hand.thumbsup"
        case .notForMe: "hand.thumbsdown"
        case .alreadyRead: "book.closed"
        }
    }
}

struct RecommendationCandidate: Decodable, Identifiable {
    let book: DiscoveryBook
    let genres: [String]
    let moods: [String]

    var id: Int { book.id }

    // English editions matched by ISBN through the app's Hardcover metadata service.
    // The starter catalog includes standalones and books that can start a series.
    static let starterCatalog: [Self] = {
        guard let url = Bundle.main.url(forResource: "DiscoverCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Self].self, from: data)) ?? []
    }()
}

struct HomeRecommendation: Identifiable {
    let candidate: RecommendationCandidate
    let reason: String?
    var id: Int { candidate.id }
    var book: DiscoveryBook { candidate.book }
}

struct HomeRecommendations {
    static let count = 5
    // Shared catalog tags that describe something more specific than the app's genres or moods.
    private static let specificConnections: [(tag: String, phrase: String)] = [
        ("greek mythology", "draws on Greek mythology"),
        ("first contact", "explores first contact"),
        ("dark academia", "has dark academia elements"),
        ("amateur sleuths", "features an amateur sleuth"),
        ("amateur sleuth", "features an amateur sleuth"),
        ("gothic", "has Gothic elements"),
        ("dystopian", "has a dystopian setting"),
        ("magical realism", "uses magical realism")
    ]

    private struct Traits {
        let author: String
        let genres: [BookGenre]
        let tags: Set<String>
        let moods: Set<String>

        init(author: String, genres: [BookGenre] = [], tags: [String], moods: [String]) {
            let authorKey = HomeRecommendations.identityPart(author)
            self.author = authorKey == "unknownauthor" ? "" : authorKey
            self.genres = genres.isEmpty ? SubjectGenreMapping.classifyHardcover(tags)?.genres ?? [] : genres
            self.tags = Set(tags.map(SubjectGenreMapping.normalize))
            self.moods = Set(moods.map(SubjectGenreMapping.normalize))
        }

        func similarity(to other: Self) -> Double {
            let sameAuthor = !author.isEmpty && author == other.author
            let genresInCommon = Set(genres).intersection(other.genres).count
            let tagsInCommon = tags.intersection(other.tags).count
            let moodsInCommon = moods.intersection(other.moods).count
            return (sameAuthor ? 3 : 0) + Double(min(genresInCommon, 2)) * 1.5 +
                Double(min(tagsInCommon, 2)) * 0.5 + Double(min(moodsInCommon, 3)) * 0.45
        }
    }

    private struct Signal {
        let title: String
        let traits: Traits
        let weight: Double
        var candidateID: Int?
    }

    private struct Ranked {
        let recommendation: HomeRecommendation
        let traits: Traits
        let score: Double
        let order: Int
    }

    static func ranked(
        candidates: [RecommendationCandidate] = RecommendationCandidate.starterCatalog,
        library: [Book],
        wishlist: [DiscoveryBook],
        feedback: [Int: RecommendationFeedback]
    ) -> [HomeRecommendation] {
        var signals = library.compactMap { book -> Signal? in
            guard let rating = book.personalRatingQuarterStars else { return nil }
            let difference = Double(rating) / 4 - 3
            guard difference != 0 else { return nil }
            let traits = Traits(author: book.author, genres: book.genres, tags: book.hardcoverGenres + book.subjects,
                                moods: (book.personalMoods?.map(\.rawValue) ?? []) + (book.hardcoverMoods ?? []))
            return Signal(title: book.title, traits: traits, weight: difference > 0 ? difference : difference * 0.5)
        }
        signals += candidates.compactMap { candidate in
            let weight: Double
            switch feedback[candidate.id] {
            case .moreLikeThis: weight = 0.8
            case .notForMe: weight = -0.45
            default: return nil
            }
            return Signal(title: candidate.book.title, traits: traits(of: candidate), weight: weight, candidateID: candidate.id)
        }

        let knownIDs = Set(library.compactMap(\.hardcoverBookID) + wishlist.map(\.id))
        let knownISBNs = Set((library.compactMap(\.isbn) + wishlist.flatMap(\.isbns))
            .compactMap(OpenLibraryISBN.equivalenceKey))
        var knownTitles = Set(library.map { identity($0.title, $0.author) } + wishlist.map { identity($0.title, $0.author) })
        var ranked: [Ranked] = []
        for (index, candidate) in candidates.enumerated() {
            let book = candidate.book
            guard !knownIDs.contains(book.id), feedback[book.id] != .notForMe, feedback[book.id] != .alreadyRead,
                  !book.isbns.compactMap(OpenLibraryISBN.equivalenceKey).contains(where: knownISBNs.contains),
                  knownTitles.insert(identity(book.title, book.author)).inserted else { continue }
            let traits = traits(of: candidate)
            let matches = signals.filter { $0.candidateID != book.id }
                .map { ($0, traits.similarity(to: $0.traits) * $0.weight) }
            let positive = matches.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(3)
            let strongestNegative = matches.map(\.1).min() ?? 0
            let score = positive.enumerated().reduce(0.0) { $0 + $1.element.1 / Double(1 << $1.offset) } +
                min(0, strongestNegative)
            let explanation = positive.lazy.compactMap { reason(for: traits, comparedTo: $0.0) }.first
            ranked.append(Ranked(recommendation: HomeRecommendation(candidate: candidate, reason: explanation),
                                 traits: traits, score: score, order: index))
        }

        // Mix authors and genres within each row of five.
        var result: [HomeRecommendation] = []
        while !ranked.isEmpty {
            var authors: [String: Int] = [:]
            var genres: [BookGenre: Int] = [:]
            for _ in 0..<min(count, ranked.count) {
                func adjusted(_ item: Ranked) -> Double {
                    let repeatGenre = item.traits.genres.map { genres[$0, default: 0] }.max() ?? 0
                    return item.score - Double(authors[item.traits.author, default: 0]) * 8 - Double(repeatGenre) * 2
                }
                guard let index = ranked.indices.max(by: {
                    let left = adjusted(ranked[$0])
                    let right = adjusted(ranked[$1])
                    return left == right ? ranked[$0].order > ranked[$1].order : left < right
                }) else { break }
                let pick = ranked.remove(at: index)
                authors[pick.traits.author, default: 0] += 1
                for genre in pick.traits.genres { genres[genre, default: 0] += 1 }
                result.append(pick.recommendation)
            }
        }
        return result
    }

    private static func traits(of candidate: RecommendationCandidate) -> Traits {
        Traits(author: candidate.book.author, tags: candidate.genres, moods: candidate.moods)
    }

    private static func reason(for traits: Traits, comparedTo signal: Signal) -> String? {
        let title = "“\(signal.title)”"
        if !traits.author.isEmpty, traits.author == signal.traits.author {
            return "By the same author as \(title)."
        }
        let sharedTags = traits.tags.intersection(signal.traits.tags)
        if let match = specificConnections.first(where: { sharedTags.contains($0.tag) }) {
            return "Like \(title), this book \(match.phrase)."
        }
        return nil
    }

    private static func identity(_ title: String, _ author: String) -> String {
        identityPart(title) + "|" + identityPart(author)
    }

    private static func identityPart(_ value: String) -> String {
        SubjectGenreMapping.normalize(value).replacingOccurrences(of: " ", with: "")
    }
}
