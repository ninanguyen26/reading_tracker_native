import SwiftUI

struct YearlyReadingHeatMap: View {
    let year: DateInterval
    let database: AppDatabase

    @Environment(\.calendar) private var calendar
    @State private var dailySeconds: [Date: TimeInterval] = [:]
    @State private var loadingFailed = false

    var body: some View {
        let months = intervals(of: .month, in: year)
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12, alignment: .top), count: 3)

        VStack(spacing: 14) {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(months, id: \.start) { month in
                    monthGrid(month)
                }
            }

            if loadingFailed {
                Text("Couldn’t load reading activity.")
                    .font(.caption)
                    .foregroundStyle(AppPalette.secondaryText)
            }

            legend
        }
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

    private func monthGrid(_ month: DateInterval) -> some View {
        let days = intervals(of: .day, in: month)
        let columnCount = calendar.veryShortStandaloneWeekdaySymbols.count
        let leadingSpaces = (calendar.component(.weekday, from: month.start) - calendar.firstWeekday
                             + columnCount) % columnCount
        let cellCount = max(6 * columnCount, leadingSpaces + days.count)
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 2), count: columnCount)

        return VStack(alignment: .leading, spacing: 5) {
            Text(month.start, format: .dateTime.month(.abbreviated))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<cellCount, id: \.self) { cell in
                    let index = cell - leadingSpaces
                    if days.indices.contains(index) {
                        dayTile(days[index].start)
                    } else {
                        Color.clear.aspectRatio(1, contentMode: .fit)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }

    private func dayTile(_ date: Date) -> some View {
        let seconds = dailySeconds[date, default: 0]
        let duration = seconds == 0 ? "No recorded reading" : Duration.seconds(seconds).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .wide, maximumUnitCount: 2)
        )
        return RoundedRectangle(cornerRadius: 2)
            .fill(AppPalette.heatmapColors[Self.intensity(seconds)])
            .aspectRatio(1, contentMode: .fit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
            .accessibilityValue(duration)
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text("Less")
            ForEach(AppPalette.heatmapColors.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppPalette.heatmapColors[index])
                    .frame(width: 10, height: 10)
            }
            Text("More")
        }
        .font(.caption2)
        .foregroundStyle(AppPalette.secondaryText)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Darker squares indicate more reading time")
    }

    private func intervals(of component: Calendar.Component, in period: DateInterval) -> [DateInterval] {
        var intervals: [DateInterval] = []
        var start = period.start
        while start < period.end, let interval = calendar.dateInterval(of: component, for: start) {
            intervals.append(interval)
            start = interval.end
        }
        return intervals
    }

    private static func intensity(_ seconds: TimeInterval) -> Int {
        switch seconds {
        case ...0: 0
        case ..<300: 1
        case ..<900: 2
        case ..<1_800: 3
        case ..<3_600: 4
        default: 5
        }
    }
}
