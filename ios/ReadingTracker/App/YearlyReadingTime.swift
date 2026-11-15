import SwiftUI

struct YearlyReadingTime: View {
    let year: DateInterval
    let database: AppDatabase

    @Environment(\.calendar) private var calendar
    @State private var dailySeconds: [Date: TimeInterval] = [:]
    @State private var loadingFailed = false

    private let plotHeight: CGFloat = 132

    private func dates(for component: Calendar.Component) -> [Date] {
        var dates: [Date] = []
        var start = year.start
        while start < year.end, let interval = calendar.dateInterval(of: component, for: start) {
            dates.append(interval.start)
            start = interval.end
        }
        return dates
    }

    var body: some View {
        let today = calendar.startOfDay(for: Date())
        let elapsedDays = dates(for: .day).prefix(while: { $0 <= today })
        let total = elapsedDays.reduce(0.0) { $0 + dailySeconds[$1, default: 0] }
        let average = elapsedDays.isEmpty ? nil : total / Double(elapsedDays.count)
        let mostRead = elapsedDays.max { dailySeconds[$0, default: 0] < dailySeconds[$1, default: 0] }
        let peak = mostRead.map { dailySeconds[$0, default: 0] } ?? 0
        let monthlySeconds = elapsedDays.reduce(into: [Date: TimeInterval]()) { totals, day in
            if let month = calendar.dateInterval(of: .month, for: day) {
                totals[month.start, default: 0] += dailySeconds[day, default: 0]
            }
        }

        VStack(spacing: 12) {
            if loadingFailed {
                Text("Couldn’t load reading time.")
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                monthlyChart(monthlySeconds)

                HStack(spacing: 10) {
                    ReadingTimeSummaryCard(title: "Daily Average", value: average.map(readingDurationLabel) ?? "—")
                    ReadingTimeSummaryCard(title: "Most in a Day", value: peak > 0 ? readingDurationLabel(peak) : "—",
                                           detail: peak > 0 ? mostRead?.formatted(.dateTime.month(.abbreviated).day()) : nil)
                }
            }
        }
        .padding(16)
        .modifier(BookCardSurface())
        .task {
            do {
                for try await seconds in database.observeDailyReadingTime(in: year, calendar: calendar) {
                    dailySeconds = seconds
                }
            } catch {
                if !Task.isCancelled { loadingFailed = true }
            }
        }
    }

    private func monthlyChart(_ monthlySeconds: [Date: TimeInterval]) -> some View {
        let peak = monthlySeconds.values.max() ?? 0
        let step = [300.0, 900, 1_800, 3_600].first { peak <= 2 * $0 }
            ?? (peak / 7_200).rounded(.up) * 3_600
        let upperBound = 2 * step

        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(readingDurationLabel(upperBound))
                Spacer(minLength: 0)
                Text(readingDurationLabel(step))
                Spacer(minLength: 0)
                Text(readingDurationLabel(0))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(AppPalette.secondaryText)
            .frame(height: plotHeight)
            .accessibilityHidden(true)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 4) {
                    ForEach(dates(for: .month), id: \.self) { date in
                        let seconds = monthlySeconds[date, default: 0]
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(AppPalette.ChartSeries.forest.color)
                                .frame(width: 14, height: plotHeight * CGFloat(seconds / upperBound))
                                .frame(height: plotHeight, alignment: .bottom)

                            Text(date, format: .dateTime.month(.abbreviated))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(AppPalette.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(width: 36)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(date.formatted(.dateTime.month(.wide).year()))
                        .accessibilityValue(readingDurationLabel(seconds))
                    }
                }
                .background(alignment: .top) {
                    VStack(spacing: 0) {
                        Divider()
                        Spacer(minLength: 0)
                        Divider()
                        Spacer(minLength: 0)
                        Divider()
                    }
                    .frame(height: plotHeight)
                    .accessibilityHidden(true)
                }
                .padding(.bottom, 4)
            }
        }
    }

}
