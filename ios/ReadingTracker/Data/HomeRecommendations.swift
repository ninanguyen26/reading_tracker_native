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

struct RecommendationCandidate: Codable, Identifiable, Sendable {
    let book: DiscoveryBook
    let genres: [String]
    let moods: [String]

    var id: Int { book.id }

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
        enum Source {
            case rating, feedback, finished, reading, tbr
        }

        let title: String
        let traits: Traits
        let weight: Double
        let source: Source
        var candidateID: Int?

        init(book: Book, weight: Double, source: Source) {
            title = book.title
            traits = Traits(author: book.author, genres: book.genres, tags: book.hardcoverGenres + book.subjects,
                            moods: (book.personalMoods?.map(\.rawValue) ?? []) + (book.hardcoverMoods ?? []))
            self.weight = weight
            self.source = source
        }

        init(candidate: RecommendationCandidate, weight: Double) {
            title = candidate.book.title
            traits = HomeRecommendations.traits(of: candidate)
            self.weight = weight
            source = .feedback
            candidateID = candidate.id
        }
    }

    private struct Ranked {
        let recommendation: HomeRecommendation
        let traits: Traits
        let score: Double
        let order: Int
    }

    static func ranked(
        candidates: [RecommendationCandidate],
        library: [Book],
        wishlist: [DiscoveryBook],
        feedback: [Int: RecommendationFeedback],
        feedbackBooks: [Int: RecommendationCandidate] = [:],
        excluding: Set<Int> = [],
        limit: Int = .max
    ) -> [HomeRecommendation] {
        var signals = library.compactMap { book -> Signal? in
            if let rating = book.personalRatingQuarterStars {
                let difference = Double(rating) / 4 - 3
                guard difference != 0, book.readingStatus != .dnf || difference < 0 else { return nil }
                return Signal(book: book, weight: difference > 0 ? difference : difference * 0.5, source: .rating)
            }
            switch book.readingStatus {
            case .finished: return Signal(book: book, weight: 0.45, source: .finished)
            case .reading where book.progression >= 0.1: return Signal(book: book, weight: 0.15, source: .reading)
            default: return nil
            }
        }
        let feedbackSources = Array(feedbackBooks.values.sorted { $0.id < $1.id }) +
            candidates.filter { feedbackBooks[$0.id] == nil }
        signals += feedbackSources.compactMap { candidate in
            let weight: Double
            switch feedback[candidate.id] {
            case .moreLikeThis: weight = 0.8
            case .notForMe: weight = -0.45
            default: return nil
            }
            return Signal(candidate: candidate, weight: weight)
        }
        if signals.isEmpty {
            signals = library.filter { $0.readingStatus == .tbr && $0.personalRatingQuarterStars == nil }
                .map { Signal(book: $0, weight: 0.05, source: .tbr) }
        }

        let knownIDs = Set(library.compactMap(\.hardcoverBookID) + wishlist.map(\.id))
        let knownISBNs = Set((library.compactMap(\.isbn) + wishlist.flatMap(\.isbns))
            .compactMap(OpenLibraryISBN.equivalenceKey))
        var knownTitles = Set(library.map { identity($0.title, $0.author) } + wishlist.map { identity($0.title, $0.author) })
        var ranked: [Ranked] = []
        for (index, candidate) in candidates.enumerated() {
            let book = candidate.book
            guard !knownIDs.contains(book.id), !excluding.contains(book.id),
                  feedback[book.id] != .notForMe, feedback[book.id] != .alreadyRead,
                  !book.isbns.compactMap(OpenLibraryISBN.equivalenceKey).contains(where: knownISBNs.contains),
                  knownTitles.insert(identity(book.title, book.author)).inserted else { continue }
            let traits = traits(of: candidate)
            let matches = signals.filter { $0.candidateID != book.id }
                .map { ($0, traits.similarity(to: $0.traits) * $0.weight) }
            var finishedAuthors = Set<String>()
            var usedTBR = false
            let positive = matches.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.filter { signal, _ in
                switch signal.source {
                case .finished:
                    // Several books from one author count as one supporting match.
                    return finishedAuthors.insert(signal.traits.author).inserted
                case .tbr:
                    guard !usedTBR else { return false }
                    usedTBR = true
                    return true
                default:
                    return true
                }
            }.prefix(3)
            let strongestNegative = matches.map(\.1).min() ?? 0
            let score = positive.enumerated().reduce(0.0) { $0 + $1.element.1 / Double(1 << $1.offset) } +
                min(0, strongestNegative)
            let explanation = positive.lazy.compactMap { reason(for: traits, comparedTo: $0.0) }.first
            ranked.append(Ranked(recommendation: HomeRecommendation(candidate: candidate, reason: explanation),
                                 traits: traits, score: score, order: index))
        }

        // Mix authors and genres within each row of five.
        var result: [HomeRecommendation] = []
        while !ranked.isEmpty, result.count < limit {
            var authors: [String: Int] = [:]
            var genres: [BookGenre: Int] = [:]
            for _ in 0..<min(count, ranked.count, limit - result.count) {
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

    static func discoveryTaste(library: [Book], feedback: [Int: RecommendationFeedback],
                               feedbackBooks: [Int: RecommendationCandidate]) -> (moods: [BookMood], genres: [String]) {
        var moods: [BookMood: Double] = [:]
        var genres: [String: Double] = [:]
        func add(moodTags: [String], genreTags: [String], weight: Double) {
            for mood in Set(BookDetailsText.hardcoverMoods(moodTags).compactMap({ BookMood(rawValue: $0.lowercased()) })) {
                moods[mood, default: 0] += weight
            }
            for genre in Set(genreTags) where genre.range(of: #"^[a-zA-Z ]{2,32}$"#, options: .regularExpression) != nil {
                genres[genre, default: 0] += weight
            }
        }
        for book in library {
            let weight: Double
            if let rating = book.personalRatingQuarterStars {
                let difference = Double(rating) / 4 - 3
                weight = book.readingStatus == .dnf ? min(0, difference) : difference
            } else {
                switch book.readingStatus {
                case .finished: weight = 0.45
                case .reading where book.progression >= 0.1: weight = 0.15
                default: continue
                }
            }
            let genreTags = book.hardcoverGenres.isEmpty ? book.genres.map { genre in
                switch genre {
                case .scienceFiction: "Science Fiction"
                case .mystery: "Mystery"
                case .selfHelp: "Self Help"
                default: genre.displayName
                }
            } : book.hardcoverGenres
            add(moodTags: book.hardcoverMoods ?? [], genreTags: genreTags, weight: weight)
        }
        for (id, book) in feedbackBooks.sorted(by: { $0.key < $1.key }) {
            switch feedback[id] {
            case .moreLikeThis: add(moodTags: book.moods, genreTags: book.genres, weight: 0.8)
            case .notForMe: add(moodTags: book.moods, genreTags: book.genres, weight: -0.45)
            default: break
            }
        }
        let topMoods = moods.filter { $0.value > 0 }.sorted {
            $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value
        }.prefix(3).map(\.key)
        let topGenres = genres.filter { $0.value > 0 }.sorted {
            $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
        }.prefix(3).map(\.key)
        return (topMoods, topGenres)
    }

    static func orderedMoods(library: [Book]) -> [BookMood] {
        var scores: [BookMood: Double] = [:]
        for book in library {
            let weight: Double
            if let rating = book.personalRatingQuarterStars {
                let difference = Double(rating) / 4 - 3
                weight = book.readingStatus == .dnf ? min(0, difference) : difference
            } else {
                weight = book.readingStatus == .finished ? 0.45 : 0
            }
            let tags = BookDetailsText.hardcoverMoods(book.hardcoverMoods ?? [])
            for mood in Set(tags.compactMap({ BookMood(rawValue: $0.lowercased()) })) {
                scores[mood, default: 0] += weight / Double(tags.count)
            }
        }
        let defaults: [BookMood] = [.mysterious, .funny, .reflective, .adventurous, .relaxing]
        return (defaults + BookMood.allCases.filter { !defaults.contains($0) }).sorted {
            scores[$0, default: 0] > scores[$1, default: 0]
        }
    }

    private static func traits(of candidate: RecommendationCandidate) -> Traits {
        Traits(author: candidate.book.author, tags: candidate.genres, moods: candidate.moods)
    }

    private static func reason(for traits: Traits, comparedTo signal: Signal) -> String? {
        guard signal.source != .tbr else { return nil }
        let title = "“\(signal.title)”"
        let context: String
        switch signal.source {
        case .finished: context = ", which you finished"
        case .reading: context = ", which you’re reading"
        default: context = ""
        }
        if !traits.author.isEmpty, traits.author == signal.traits.author {
            return "By the same author as \(title)\(context)."
        }
        let sharedTags = traits.tags.intersection(signal.traits.tags)
        if let match = specificConnections.first(where: { sharedTags.contains($0.tag) }) {
            if context.isEmpty {
                return "Like \(title), this book \(match.phrase)."
            }
            return "This book \(match.phrase), like \(title)\(context)."
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
