import Foundation
import CryptoKit
import GRDB

/// Stable, closed taxonomy. An empty selection represents an unclassified book.
enum BookGenre: String, Codable, CaseIterable, Identifiable, Hashable, Sendable, DatabaseValueConvertible {
    case romance = "Romance"
    case fantasy = "Fantasy"
    case scienceFiction = "Science Fiction (Sci-Fi)"
    case mystery = "Mystery & Crime"
    case thriller = "Thriller & Suspense"
    case horror = "Horror"
    case historicalFiction = "Historical Fiction"
    case literaryFiction = "Literary Fiction"
    case adventure = "Action & Adventure"
    case biography = "Biography & Autobiography"
    case memoir = "Memoir"
    case selfHelp = "Self-Help & Personal Development"
    case history = "History"
    case business = "Business, Finance & Economics"
    case science = "Science & Technology"
    case trueCrime = "True Crime"
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .scienceFiction: "Sci-Fi"
        case .selfHelp: "Self-Help"
        case .business: "Business & Finance"
        case .biography: "Biography"
        case .science: "Science & Tech"
        case .thriller: "Thriller"
        default: rawValue
        }
    }

    var definition: String {
        switch self {
        case .romance: "Central romantic relationship and emotional arc, usually with an optimistic ending."
        case .fantasy: "Imaginary or mythic worlds, magic, supernatural creatures, or magical quests."
        case .scienceFiction: "Fiction about futuristic technology, space, alternate timelines, or dystopian societies."
        case .mystery: "Fiction focused on solving a crime, detectives, or police investigations."
        case .thriller: "Fiction driven by danger, high stakes, suspense, or a race against time."
        case .horror: "Fiction primarily intended to evoke fear, dread, terror, or the macabre."
        case .historicalFiction: "Fictional characters or plots in a recognized historical period."
        case .literaryFiction: "Fiction emphasizing stylistic prose, character depth, and thematic exploration. Never a default for other fiction."
        case .adventure: "Fiction driven by physical journeys, action, exploration, or physical obstacles."
        case .biography: "Factual life story of a real person, written by themselves or another person."
        case .memoir: "First-person factual account of a focused period, theme, or set of life experiences."
        case .selfHelp: "Practical guidance for habits, productivity, mental health, relationships, or personal development."
        case .history: "Factual accounts or analysis of past events, eras, or civilizations."
        case .business: "Business, entrepreneurship, corporate strategy, finance, investing, or economics."
        case .science: "Nonfiction explaining science, nature, scientific discoveries, or technology."
        case .trueCrime: "Factual investigation or recounting of real crimes, trials, or criminal investigations."
        }
    }
}

struct GenreInput: Codable, Sendable, Equatable {
    var title: String
    var author: String
    var subjects: [String]
    var hardcoverTags: [String]
    var synopsis: String

    init(book: Book) {
        title = String(book.title.prefix(250))
        author = String(book.author.prefix(200))
        subjects = BookDetailsText.nonempty(book.subjects + book.hardcoverGenres).prefix(50).map { String($0.prefix(100)) }
        hardcoverTags = book.hardcoverGenres
        synopsis = String((BookDetailsText.description(book.description) ?? "").prefix(5000))
    }
    var evidence: String { (subjects + [synopsis]).joined(separator: "\n") }
    var signature: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return SHA256.hash(data: (try? encoder.encode(self)) ?? Data()).map { String(format: "%02x", $0) }.joined()
    }
    var hasModelEvidence: Bool {
        if subjects.count >= 2 { return true }
        var words = 0
        synopsis.enumerateSubstrings(in: synopsis.startIndex..<synopsis.endIndex, options: .byWords) { _, _, _, stop in
            words += 1
            if words >= 20 { stop = true }
        }
        return words >= 20
    }
}

struct GenreDecision: Sendable, Equatable {
    var genres: [BookGenre]
    var source: String
}

/// Map subject phrases and BISAC-style subdivisions, never loose words in a synopsis.
enum SubjectGenreMapping {
    static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    private static let aliases: [BookGenre: [String]] = [
        .romance: ["romance", "romance fiction", "romantic fiction", "love stories", "romance novels"],
        .fantasy: ["fantasy", "fantasy fiction", "epic fantasy", "high fantasy", "urban fantasy", "dark fantasy", "sword and sorcery"],
        .scienceFiction: ["science fiction", "sci fi", "scifi", "space opera", "cyberpunk", "dystopian fiction", "dystopias"],
        .mystery: ["mystery", "mystery fiction", "mystery and detective stories", "detective fiction", "detective and mystery stories", "police procedurals", "crime fiction", "cozy mysteries", "mystery detective"],
        .thriller: ["thriller", "thrillers", "thriller fiction", "suspense", "suspense fiction", "psychological thrillers", "legal thrillers", "political thrillers", "spy fiction"],
        .horror: ["horror", "horror fiction", "horror tales", "ghost stories", "psychological horror"],
        .historicalFiction: ["historical fiction", "historical novels"],
        .literaryFiction: ["literary fiction"],
        .adventure: ["action adventure", "action and adventure", "adventure fiction", "adventure stories", "action fiction"],
        .biography: ["biography", "biographies", "autobiography", "autobiographies", "biography autobiography", "biography and autobiography"],
        .memoir: ["memoir", "memoirs", "personal memoirs"],
        .selfHelp: ["self help", "self improvement", "personal development", "personal growth", "self actualization psychology"],
        .history: ["history", "world history", "military history", "social history"],
        .business: ["business", "finance", "economics", "business economics", "business and economics", "entrepreneurship", "personal finance", "investing", "investments", "management"],
        .science: ["science", "technology", "science technology", "science and technology", "natural history", "nature", "popular science", "physics", "biology", "computer science"],
        .trueCrime: ["true crime", "true crime stories"]
    ]

    private static func matches(in subjects: [String]) -> Set<BookGenre> {
        var candidates = Set<BookGenre>()
        for subject in subjects {
            let full = normalize(subject)
            let parts = subject.components(separatedBy: "/").map(normalize)
            for (genre, phrases) in aliases where normalize(genre.rawValue) == full || phrases.contains(full) || parts.contains(where: phrases.contains) {
                candidates.insert(genre)
            }
            if parts.first == "fiction" {
                if parts.contains("historical") { candidates.insert(.historicalFiction) }
                if parts.contains("literary") { candidates.insert(.literaryFiction) }
            }
        }
        return candidates
    }

    private static func hasRomantasy(_ tags: [String]) -> Bool {
        tags.map(normalize).contains { $0 == "romantasy" || $0 == "fantasy romance" }
    }

    static func classifyHardcover(_ tags: [String]) -> GenreDecision? {
        let subjects = tags.flatMap { $0.components(separatedBy: ":") }
        var candidates = matches(in: subjects)
        if hasRomantasy(subjects) { candidates.formUnion([.romance, .fantasy]) }
        guard !candidates.isEmpty else { return nil }
        return GenreDecision(genres: BookGenre.allCases.filter(candidates.contains), source: "hardcover")
    }

    static func classify(_ subjects: [String]) -> GenreDecision? {
        var candidates = matches(in: subjects)
        if candidates.contains(.memoir) { candidates.remove(.biography) }
        if candidates.contains(.historicalFiction) { candidates.remove(.history) }
        if hasRomantasy(subjects) && candidates.isSubset(of: [.fantasy, .romance]) {
            return GenreDecision(genres: [.romance, .fantasy], source: "subjects")
        }
        guard candidates.count == 1, let genre = candidates.first else { return nil }
        return GenreDecision(genres: [genre], source: "subjects")
    }
}

struct GenreModelChoice: Sendable {
    var label: String
    var quote: String
}
struct GenreModelAnswer: Sendable {
    var certain: Bool
    var choices: [GenreModelChoice]
}
protocol GenreModelPredicting: Sendable {
    func predict(_ input: GenreInput) async -> GenreModelAnswer?
}

actor BookGenreClassifier {
    static let shared = BookGenreClassifier()
    private let model: any GenreModelPredicting
    private var pending: Task<GenreModelAnswer?, Never>?
    private var lastJob: UUID?

    init(model: any GenreModelPredicting = AppleGenreModel()) { self.model = model }

    func classify(_ input: GenreInput) async -> GenreDecision? {
        if let mapped = SubjectGenreMapping.classifyHardcover(input.hardcoverTags) { return mapped }
        if let mapped = SubjectGenreMapping.classify(input.subjects) { return mapped }
        guard input.hasModelEvidence else { return nil }
        let preceding = pending
        let predictor = model
        let job = UUID()
        lastJob = job
        // Serialize inference across multi-file imports; each book gets a fresh session.
        let task = Task {
            _ = await preceding?.value
            guard !Task.isCancelled else { return nil as GenreModelAnswer? }
            return await predictor.predict(input)
        }
        pending = task
        let answer = await task.value
        if lastJob == job { pending = nil }
        return Self.validated(answer, input: input)
    }

    static func validated(_ answer: GenreModelAnswer?, input: GenreInput) -> GenreDecision? {
        guard let answer, answer.certain, (1...3).contains(answer.choices.count) else { return nil }
        var genres: [BookGenre] = []
        for choice in answer.choices {
            let quote = choice.quote.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let genre = BookGenre(rawValue: choice.label), !genres.contains(genre),
                  quote.count >= 12, input.evidence.contains(quote) else { return nil }
            genres.append(genre)
        }
        return GenreDecision(genres: BookGenre.allCases.filter(genres.contains), source: "onDevice")
    }

    func classifyBook(id: String, database: AppDatabase) async {
        guard let book = try? await database.book(id: id), book.genreSource != "manual" else { return }
        let input = GenreInput(book: book)
        let decision = await classify(input)
        guard !Task.isCancelled else { return }
        try? await database.saveAutomaticGenre(id: id, decision: decision, inputSignature: input.signature)
    }
}

extension AppDatabase {
    func saveManualGenres(id: String, genres: Set<BookGenre>) async throws -> Book {
        try await writer.write { db in
            guard var book = try Book.fetchOne(db, key: id) else { throw OpenLibraryError.missingBook }
            book.genres = BookGenre.allCases.filter(genres.contains)
            book.genreSource = "manual" // Includes an explicit manual Unclassified selection.
            try book.update(db)
            return book
        }
    }

    func saveAutomaticGenre(id: String, decision: GenreDecision?, inputSignature: String,
                            onlyIfUnclassified: Bool = false) async throws {
        try await writer.write { db in
            guard var book = try Book.fetchOne(db, key: id), book.genreSource != "manual",
                  !onlyIfUnclassified || book.genres.isEmpty,
                  GenreInput(book: book).signature == inputSignature else { return }
            book.genres = decision?.genres ?? []
            book.genreSource = decision?.source
            try book.update(db)
        }
    }

    func resetManualGenre(id: String) async throws {
        try await writer.write { db in
            try db.execute(sql: "UPDATE book SET genres = '[]', genreSource = NULL WHERE id = ?", arguments: [id])
        }
    }
}
