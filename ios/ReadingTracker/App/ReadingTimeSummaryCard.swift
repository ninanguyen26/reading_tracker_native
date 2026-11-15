import SwiftUI

struct ReadingTimeSummaryCard: View {
    let title: String
    let value: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppPalette.secondaryText)
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
            Text(detail ?? " ")
                .font(.caption)
                .foregroundStyle(AppPalette.secondaryText)
                .accessibilityHidden(detail == nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(AppPalette.secondarySurface.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

func readingDurationLabel(_ seconds: TimeInterval) -> String {
    let units: Set<Duration.UnitsFormatStyle.Unit> = seconds > 0 && seconds < 60 ? [.seconds] : [.hours, .minutes]
    return Duration.seconds(seconds.rounded()).formatted(.units(allowed: units, width: .abbreviated))
}
