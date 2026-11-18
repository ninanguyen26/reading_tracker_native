import SwiftUI

struct FinishedGenreShare: Identifiable {
    enum Category: Hashable {
        case genre(BookGenre)
        case unclassified
        case others

        var name: String {
            switch self {
            case .genre(let genre): genre.displayName
            case .unclassified: "Unclassified"
            case .others: "Others"
            }
        }
    }

    let category: Category
    let fraction: Double

    var id: Category { category }

    static func distribution(books: [Book], interval: DateInterval?) -> [Self] {
        var finishedCount = 0
        var weights: [Category: Double] = [:]

        for book in books where book.readingStatus == .finished {
            if let interval {
                guard let finishedAt = book.finishedReadingAt,
                      finishedAt >= interval.start, finishedAt < interval.end else { continue }
            }

            finishedCount += 1
            let genres = Set(book.genres)
            if genres.isEmpty {
                weights[.unclassified, default: 0] += 1
            } else {
                let weight = 1 / Double(genres.count)
                for genre in genres { weights[.genre(genre), default: 0] += weight }
            }
        }

        let ranked = weights.map { Self(category: $0.key, fraction: $0.value / Double(finishedCount)) }
            .sorted { first, second in
                if first.fraction != second.fraction { return first.fraction > second.fraction }
                return first.category.name.localizedStandardCompare(second.category.name) == .orderedAscending
            }
        guard ranked.count > 5 else { return ranked }
        let remainingFraction = ranked.dropFirst(5).reduce(0) { $0 + $1.fraction }
        return Array(ranked.prefix(5)) + [Self(category: .others, fraction: remainingFraction)]
    }
}

struct FinishedGenresChart: View {
    let books: [Book]
    let interval: DateInterval?

    var body: some View {
        let shares = FinishedGenreShare.distribution(books: books, interval: interval)
        if shares.isEmpty {
            Text(interval == nil ? "No finished books yet." : "No books finished in this period.")
                .font(.subheadline)
                .foregroundStyle(AppPalette.secondaryText)
        } else {
            VStack(spacing: 16) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay { pie(shares) }
                    .frame(maxWidth: 180)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    ForEach(shares) { share in
                        HStack(spacing: 8) {
                            Circle().fill(color(for: share)).frame(width: 9, height: 9)
                                .accessibilityHidden(true)
                            Text(share.category.name)
                            Spacer(minLength: 8)
                            Text(share.fraction, format: .percent.precision(.fractionLength(0...1)))
                                .monospacedDigit()
                                .fixedSize()
                                .foregroundStyle(AppPalette.secondaryText)
                        }
                        .font(.subheadline)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func pie(_ shares: [FinishedGenreShare]) -> some View {
        var start = 0.0
        let slices = shares.enumerated().map { index, share in
            let end = index == shares.count - 1 ? 1 : start + share.fraction
            defer { start = end }
            return (share, PieSlice(start: start, end: end))
        }

        return ZStack {
            ForEach(slices.indices, id: \.self) { index in
                let (share, slice) = slices[index]
                slice.fill(color(for: share))
            }
        }
    }

    private func color(for share: FinishedGenreShare) -> Color {
        switch share.category {
        case .genre(let genre):
            guard let index = BookGenre.allCases.firstIndex(of: genre) else { return AppPalette.accent }
            let colors = AppPalette.chartColors
            let tier = index / colors.count
            return colors[index % colors.count].opacity(1 - Double(tier) * 0.25)
        case .unclassified:
            return AppPalette.secondaryText
        case .others:
            return AppPalette.secondaryText.opacity(0.55)
        }
    }
}

private struct PieSlice: Shape {
    let start: Double
    let end: Double

    func path(in rect: CGRect) -> Path {
        if start == 0 && end == 1 { return Path(ellipseIn: rect) }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.move(to: center)
        path.addRelativeArc(center: center, radius: min(rect.width, rect.height) / 2,
                            startAngle: .degrees(start * 360 - 90), delta: .degrees((end - start) * 360))
        path.closeSubpath()
        return path
    }
}
