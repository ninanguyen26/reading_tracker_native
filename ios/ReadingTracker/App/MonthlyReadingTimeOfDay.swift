import SwiftUI

struct MonthlyReadingTimeOfDay: View {
    let month: DateInterval
    let database: AppDatabase

    @Environment(\.calendar) private var calendar
    @ScaledMetric(relativeTo: .caption) private var durationLabelSpace: CGFloat = 22
    @State private var stats: ReadingTimeOfDayStats?
    @State private var loadingFailed = false

    private let maxBarHeight: CGFloat = 100

    var body: some View {
        if loadingFailed {
            Text("Couldn’t load reading time.")
                .font(.subheadline)
                .foregroundStyle(AppPalette.secondaryText)
        } else {
            VStack(spacing: 12) {
                if let stats {
                    let maximum = stats.readingSeconds.values.max() ?? 0
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(ReadingTimeOfDay.allCases, id: \.self) { time in
                            chartColumn(time, seconds: stats.readingSeconds[time, default: 0], maximum: maximum)
                        }
                    }
                    .background(alignment: .top) {
                        Rectangle()
                            .fill(AppPalette.border)
                            .frame(height: 1)
                            .offset(y: maxBarHeight + durationLabelSpace)
                            .accessibilityHidden(true)
                    }

                    summaryCards(stats)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: maxBarHeight)
                        .accessibilityLabel("Loading reading time")
                }
            }
            .task {
                do {
                    for try await reading in database.observeReadingTimeOfDay(in: month, calendar: calendar) {
                        stats = reading
                    }
                } catch {
                    if !Task.isCancelled { loadingFailed = true }
                }
            }
        }
    }

    private func chartColumn(_ time: ReadingTimeOfDay, seconds: TimeInterval, maximum: TimeInterval) -> some View {
        let height = maximum > 0 ? maxBarHeight * CGFloat(seconds / maximum) : 0
        let duration = readingDurationLabel(seconds)

        return VStack(spacing: 8) {
            VStack(spacing: 4) {
                Text(duration)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                RoundedRectangle(cornerRadius: 5)
                    .fill(AppPalette.ChartSeries.forest.color)
                    .frame(maxWidth: 36)
                    .frame(height: height)
            }
            .frame(height: maxBarHeight + durationLabelSpace, alignment: .bottom)

            Text(time.title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppPalette.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(time.title)
        .accessibilityValue(duration)
    }

    private func summaryCards(_ stats: ReadingTimeOfDayStats) -> some View {
        let maxStarts = stats.sessionStarts.values.max()
        let busiestTimes = ReadingTimeOfDay.allCases.filter { stats.sessionStarts[$0] == maxStarts && maxStarts != nil }
        let preferredTime = busiestTimes.isEmpty ? "—" : busiestTimes.map(\.title).formatted(.list(type: .and))
        let longestStart = stats.longestSession.map { ReadingTimeOfDay(hour: calendar.component(.hour, from: $0.start)) }

        return HStack(alignment: .top, spacing: 10) {
            ReadingTimeSummaryCard(title: "Most Session Starts", value: preferredTime,
                                   detail: maxStarts.map { $0 == 1 ? "1 start" : "\($0.formatted()) starts" })
            ReadingTimeSummaryCard(title: "Longest Session", value: longestStart?.title ?? "—",
                                   detail: stats.longestSession.map { readingDurationLabel($0.seconds) })
        }
    }
}
