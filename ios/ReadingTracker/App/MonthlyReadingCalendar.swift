import SwiftUI

struct MonthlyReadingCalendar: View {
    let month: DateInterval
    let books: [Book]
    let coverURL: (Book) -> URL?
    let database: AppDatabase

    @Environment(\.calendar) private var calendar
    @State private var mostReadBooks: [Date: String] = [:]
    @State private var loadingFailed = false

    private var days: [Date] {
        var dates: [Date] = []
        var date = month.start
        while date < month.end, let day = calendar.dateInterval(of: .day, for: date) {
            dates.append(day.start)
            date = day.end
        }
        return dates
    }

    var body: some View {
        let weekdays = calendar.veryShortStandaloneWeekdaySymbols
        let columnCount = weekdays.count
        let firstWeekday = calendar.firstWeekday - 1
        let leadingSpaces = (calendar.component(.weekday, from: month.start) - calendar.firstWeekday
                             + columnCount) % columnCount
        let monthDays = days
        let weekCount = (leadingSpaces + monthDays.count + columnCount - 1) / columnCount
        let booksByID = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) })

        VStack(spacing: 8) {
            Grid(horizontalSpacing: 6, verticalSpacing: 10) {
                GridRow {
                    ForEach(weekdays.indices, id: \.self) { index in
                        Text(weekdays[(firstWeekday + index) % columnCount])
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppPalette.secondaryText)
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                    }
                }

                ForEach(0..<weekCount, id: \.self) { week in
                    GridRow(alignment: .top) {
                        ForEach(0..<columnCount, id: \.self) { column in
                            let index = week * columnCount + column - leadingSpaces
                            if monthDays.indices.contains(index) {
                                let day = monthDays[index]
                                let book = mostReadBooks[day].flatMap { booksByID[$0] }
                                dayCell(day, book: book)
                            } else {
                                Color.clear
                                    .gridCellUnsizedAxes([.horizontal, .vertical])
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
            }

            if loadingFailed {
                Text("Couldn’t load reading activity.")
                    .font(.caption)
                    .foregroundStyle(AppPalette.secondaryText)
            }
        }
        .task {
            do {
                for try await books in database.observeDailyMostReadBooks(in: month, calendar: calendar) {
                    mostReadBooks = books
                }
            } catch {
                if !Task.isCancelled { loadingFailed = true }
            }
        }
    }

    private func dayCell(_ date: Date, book: Book?) -> some View {
        VStack(spacing: 4) {
            Text(calendar.component(.day, from: date).formatted())
                .font(.caption2.monospacedDigit().weight(book == nil ? .regular : .semibold))
                .foregroundStyle(book == nil ? AppPalette.secondaryText : AppPalette.text)

            Color.clear
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay {
                    if let book {
                        BookCoverView(book: book, coverURL: coverURL(book), showsPlaceholderTitle: false)
                    }
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .accessibilityValue(book?.title ?? "No recorded reading")
    }
}
