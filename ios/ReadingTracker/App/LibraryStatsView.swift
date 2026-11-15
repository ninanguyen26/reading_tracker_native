import SwiftUI

struct LibraryStatsView: View {
    let books: [Book]
    let coverURL: (Book) -> URL?
    let database: AppDatabase

    @Environment(\.calendar) private var calendar
    @State private var period: StatsPeriod = .yearly
    @State private var date = Date()

    var body: some View {
        let counts = Dictionary(grouping: books, by: \.readingStatus).mapValues(\.count)
        let ratedBooks = ratedBooksInPeriod
        ScrollView {
            VStack(spacing: 28) {
                statsSection("Your Library") {
                    LibraryCountChart(total: books.count, counts: counts)
                }

                VStack(spacing: 16) {
                    StatsPeriodNavigator(period: $period, date: $date)
                        .accessibilityElement(children: .contain)

                    if period == .monthly, let month = calendar.dateInterval(of: .month, for: date) {
                        statsSection("Reading Calendar") {
                            MonthlyReadingCalendar(month: month, books: books, coverURL: coverURL, database: database)
                                .id(month)
                        }
                    } else if period == .yearly, let year = calendar.dateInterval(of: .year, for: date) {
                        statsSection("Reading Heat Map") {
                            YearlyReadingHeatMap(year: year, database: database)
                                .id(year)
                        }
                    }

                    statsSection("Top 3 Best Books") {
                        bestBooks(ratedBooks)
                    }
                }
            }
            .padding(20)
        }
        .background(AppPalette.background)
        .foregroundStyle(AppPalette.text)
    }

    private func statsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 16)
                .accessibilityAddTraits(.isHeader)

            content()
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(BookCardSurface())
        }
    }

    private struct RatedBook: Identifiable {
        let book: Book
        let quarterStars: Int
        var ratedAt: Date { book.personalRatingUpdatedAt ?? .distantPast }
        var id: String { book.id }
    }

    private var ratedBooksInPeriod: [RatedBook] {
        let interval = period.component.flatMap { calendar.dateInterval(of: $0, for: date) }
        return books.compactMap { book in
            guard let rating = book.personalRatingQuarterStars else { return nil }
            if period != .allTime {
                guard let interval, let ratedAt = book.personalRatingUpdatedAt,
                      ratedAt >= interval.start, ratedAt < interval.end else { return nil }
            }
            return RatedBook(book: book, quarterStars: rating)
        }
    }

    @ViewBuilder private func bestBooks(_ books: [RatedBook]) -> some View {
        let ranked = books.sorted { first, second in
            if first.quarterStars != second.quarterStars {
                return first.quarterStars > second.quarterStars
            }
            if first.ratedAt != second.ratedAt { return first.ratedAt > second.ratedAt }
            return first.id < second.id
        }
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12), count: 3)

        if ranked.isEmpty {
            Text(period == .allTime ? "No rated books yet." : "No books rated in this period.")
                .font(.subheadline)
                .foregroundStyle(AppPalette.secondaryText)
        } else {
            LazyVGrid(columns: columns, alignment: .leading) {
                ForEach(ranked.prefix(3)) { rated in
                    VStack(spacing: 8) {
                        BookCoverView(book: rated.book, coverURL: coverURL(rated.book))
                        PersonalRatingStars(quarterStars: rated.quarterStars)
                            .font(.system(size: 11))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(rated.book.title)
                    .accessibilityValue("\(personalRatingNumber(rated.quarterStars)) out of 5 stars")
                }
            }
        }
    }
}

private enum StatsPeriod {
    case allTime, yearly, monthly

    var component: Calendar.Component? {
        switch self {
        case .allTime: nil
        case .yearly: .year
        case .monthly: .month
        }
    }
}

private struct StatsPeriodNavigator: View {
    @Binding var period: StatsPeriod
    @Binding var date: Date

    @Environment(\.calendar) private var calendar

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(AppPalette.border)
                .accessibilityHidden(true)

            HStack(spacing: 0) {
                periodTab("All time", for: .allTime)
                periodTab("Yearly", for: .yearly)
                periodTab("Monthly", for: .monthly)
            }

            if let component = period.component {
                let unit = component == .year ? "year" : "month"
                HStack(spacing: 12) {
                    periodButton("Previous \(unit)", symbol: "chevron.left", component: component, offset: -1)

                    Text(date, format: component == .year ? .dateTime.year() : .dateTime.month(.wide).year())
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    periodButton("Next \(unit)", symbol: "chevron.right", component: component, offset: 1)
                }
                .frame(maxWidth: 248)
            }
        }
    }

    private func periodTab(_ title: String, for option: StatsPeriod) -> some View {
        let selected = period == option

        return Button {
            period = option
        } label: {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .medium))
                .foregroundStyle(selected ? AppPalette.text : AppPalette.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.vertical, 8)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 44)
                .overlay(alignment: .bottom) {
                    if selected {
                        Capsule()
                            .fill(AppPalette.accent)
                            .frame(width: 24, height: 2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func periodButton(_ label: String, symbol: String, component: Calendar.Component, offset: Int) -> some View {
        Button {
            if let nextDate = calendar.date(byAdding: component, value: offset, to: date) {
                date = nextDate
            }
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }
}

private struct LibraryCountChart: View {
    let total: Int
    let counts: [ReadingStatus: Int]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var countLabelSpace: CGFloat = 28
    @State private var barsVisible = false

    private let maxBarHeight: CGFloat = 120

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            column("Total", count: total, color: .forest)
            column(ReadingStatus.tbr.label, count: counts[.tbr, default: 0], color: .slateBlue)
            column(ReadingStatus.reading.label, count: counts[.reading, default: 0], color: .teal)
            column(ReadingStatus.finished.label, count: counts[.finished, default: 0], color: .olive)
            column(ReadingStatus.dnf.label, count: counts[.dnf, default: 0], color: .terracotta)
        }
        .background(alignment: .top) {
            Rectangle()
                .fill(AppPalette.border)
                .frame(height: 1)
                .offset(y: maxBarHeight + countLabelSpace)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .onAppear { barsVisible = true }
        .onDisappear { barsVisible = false }
    }

    private func column(_ title: String, count: Int, color: AppPalette.ChartSeries) -> some View {
        let barHeight = barsVisible || reduceMotion ? maxBarHeight * CGFloat(count) / CGFloat(max(total, 1)) : 0

        return VStack(spacing: 8) {
            VStack(spacing: 4) {
                Text(count.formatted())
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                RoundedRectangle(cornerRadius: 5)
                    .fill(color.color)
                    .frame(maxWidth: 36)
                    .frame(height: barHeight)
            }
            .frame(height: maxBarHeight + countLabelSpace, alignment: .bottom)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.65), value: barHeight)

            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppPalette.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(count.formatted())")
    }
}
