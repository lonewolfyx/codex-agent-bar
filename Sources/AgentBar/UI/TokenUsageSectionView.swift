import SwiftUI

struct TokenUsageSectionView: View {
    let snapshot: TokenUsageSnapshot?
    let errorMessage: String?
    let isLoading: Bool

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let snapshot {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    TokenUsageMetricTile(title: I18n.current.todayTokenUsage, value: formatted(dailyValue(snapshot.todayTokens, snapshot: snapshot)))
                    TokenUsageMetricTile(title: I18n.current.yesterdayTokenUsage, value: formatted(dailyValue(snapshot.yesterdayTokens, snapshot: snapshot)))
                    TokenUsageMetricTile(title: I18n.current.totalTokenUsage, value: formatted(snapshot.totalTokens))
                    TokenUsageMetricTile(title: I18n.current.averageWeeklyTokenUsage, value: formatted(dailyValue(snapshot.averageWeeklyTokens, snapshot: snapshot)))
                }

                TokenUsageChartView(snapshot: snapshot)
            } else {
                TokenUsagePlaceholderView(text: placeholderText)
            }
        }
    }

    private var placeholderText: String {
        if let errorMessage {
            return errorMessage
        }

        return isLoading ? I18n.current.loading : I18n.current.tokenUsageUnavailable
    }

    private func formatted(_ value: Int?) -> String {
        guard let value else {
            return "--"
        }

        return TokenUsageValueFormatter.decimal(value)
    }

    private func dailyValue(_ value: Int, snapshot: TokenUsageSnapshot) -> Int? {
        snapshot.hasDailyUsageBuckets ? value : nil
    }

}

private struct TokenUsageMetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(QuotaPopoverColors.mutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(QuotaPopoverColors.primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, 2)
    }
}

private struct TokenUsageChartView: View {
    let snapshot: TokenUsageSnapshot

    @State private var hoveredDay: TokenUsageDay?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(I18n.current.tokenUsageChartTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(QuotaPopoverColors.mutedText)

                Spacer()

                Text(statusText)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(QuotaPopoverColors.scaleText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }

            if snapshot.hasDailyUsageBuckets {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(snapshot.dailyUsage) { day in
                        TokenUsageBar(
                            day: day,
                            maxTokens: maxTokens,
                            isHighlighted: hoveredDay?.id == day.id
                        ) { isHovering in
                            hoveredDay = isHovering ? day : nil
                        }
                    }
                }
                .frame(height: 56)
                .padding(.horizontal, 2)
            } else {
                TokenUsagePlaceholderView(text: I18n.current.tokenUsageUnavailable)
                    .frame(height: 56)
            }
        }
        .padding(.top, 2)
    }

    private var maxTokens: Int {
        max(snapshot.dailyUsage.map(\.tokens).max() ?? 0, 1)
    }

    private var statusText: String {
        guard let hoveredDay else {
            return TokenUsageValueFormatter.compact(maxTokens)
        }

        return I18n.current.tokenUsageTooltip(
            dateText: TokenUsageDateFormatter.tooltipDate(hoveredDay.date),
            tokenText: TokenUsageValueFormatter.compact(hoveredDay.tokens)
        )
    }
}

private struct TokenUsageBar: View {
    let day: TokenUsageDay
    let maxTokens: Int
    let isHighlighted: Bool
    let onHoverChange: (Bool) -> Void

    var body: some View {
        GeometryReader { proxy in
            let height = barHeight(in: proxy.size.height)

            VStack {
                Spacer(minLength: 0)

                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor)
                    .frame(height: height)
            }
        }
        .contentShape(Rectangle())
        .onHover(perform: onHoverChange)
        .help(I18n.current.tokenUsageTooltip(
            dateText: TokenUsageDateFormatter.tooltipDate(day.date),
            tokenText: TokenUsageValueFormatter.compact(day.tokens)
        ))
    }

    private var barColor: Color {
        guard day.tokens > 0 else {
            return QuotaPopoverColors.track
        }

        return isHighlighted ? Color(nsColor: .systemBlue) : QuotaPopoverColors.track
    }

    private func barHeight(in totalHeight: CGFloat) -> CGFloat {
        guard day.tokens > 0 else {
            return 3
        }

        let ratio = CGFloat(day.tokens) / CGFloat(max(maxTokens, 1))
        return max(4, totalHeight * ratio)
    }

}

private enum TokenUsageValueFormatter {
    static func compact(_ value: Int) -> String {
        switch I18n.language {
        case .simplifiedChinese:
            return compactChinese(value)
        case .english:
            return compactEnglish(value)
        }
    }

    private static func compactChinese(_ value: Int) -> String {
        let absoluteValue = abs(value)

        if absoluteValue >= 100_000_000 {
            return "\(formatted(Double(value) / 100_000_000.0))亿"
        }

        if absoluteValue >= 10_000 {
            return "\(formatted(Double(value) / 10_000.0))万"
        }

        return decimal(value)
    }

    private static func compactEnglish(_ value: Int) -> String {
        let absoluteValue = abs(value)

        if absoluteValue >= 1_000_000_000 {
            return "\(formatted(Double(value) / 1_000_000_000.0))B"
        }

        if absoluteValue >= 1_000_000 {
            return "\(formatted(Double(value) / 1_000_000.0))M"
        }

        if absoluteValue >= 1_000 {
            return "\(formatted(Double(value) / 1_000.0))K"
        }

        return decimal(value)
    }

    private static func formatted(_ value: Double) -> String {
        compactNumberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func decimal(_ value: Int) -> String {
        decimalNumberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static let compactNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    private static let decimalNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}

private enum TokenUsageDateFormatter {
    static func tooltipDate(_ date: Date) -> String {
        tooltipDateFormatter.string(from: date)
    }

    private static let tooltipDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        switch I18n.language {
        case .simplifiedChinese:
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "M月d日"
        case .english:
            formatter.locale = Locale(identifier: "en_US")
            formatter.dateFormat = "MMM d"
        }
        return formatter
    }()
}

private struct TokenUsagePlaceholderView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(QuotaPopoverColors.mutedText)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.82)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .center)
    }
}
