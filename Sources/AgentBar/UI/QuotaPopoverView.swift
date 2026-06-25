import SwiftUI

struct QuotaPopoverView: View {
    @ObservedObject var store: QuotaStore
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            AccountInfoHeader(account: store.currentAccount)
            Divider()

            if let snapshot = store.snapshot {
                VStack(spacing: 14) {
                    QuotaRow(window: snapshot.primary)
                    Divider()
                    QuotaRow(window: snapshot.secondary)
                }
            } else {
                Text(store.statusMessage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(QuotaPopoverColors.mutedText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            Divider()

            HStack {
                footerText

                Spacer()

                Button(I18n.current.quit, action: onQuit)
                    .buttonStyle(.borderless)
                    .foregroundStyle(QuotaPopoverColors.primaryText)
            }
            .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(width: 320)
        .frame(height: 300)
        .background(Color.clear)
    }

    private var footerText: some View {
        Group {
            if let lastUpdated = store.snapshot?.lastUpdated {
                Text("\(I18n.current.lastRefreshPrefix) \(lastUpdated.formatted(.dateTime.hour().minute().locale(Locale(identifier: I18n.current.dateLocaleIdentifier))))")
            } else {
                Text(store.isLoading ? I18n.current.loading : I18n.current.notRefreshed)
            }
        }
        .foregroundStyle(QuotaPopoverColors.mutedText)
    }
}

private struct AccountInfoHeader: View {
    let account: CodexAccount?

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(QuotaPopoverColors.scaleText)

                Text(displayEmail)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(QuotaPopoverColors.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            RoleBadge(role: displayRole)
                .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displayEmail: String {
        displayValue(account?.email)
    }

    private var displayRole: String {
        capitalizedFirstLetter(displayValue(account?.planType))
    }

    private func displayValue(_ value: String?) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return "--"
        }

        return value
    }

    private func capitalizedFirstLetter(_ value: String) -> String {
        guard let first = value.first, first.isLetter else {
            return value
        }

        return first.uppercased() + value.dropFirst().lowercased()
    }
}

private struct RoleBadge: View {
    let role: String

    var body: some View {
        let style = BadgeStyle(role: role)

        Text(role)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(style.text)
            .padding(.horizontal, style.hasContainer ? 8 : 0)
            .padding(.vertical, style.hasContainer ? 3 : 0)
            .background {
                if style.hasContainer {
                    Capsule()
                        .fill(style.background)
                }
            }
            .overlay {
                if style.hasContainer {
                    Capsule()
                        .stroke(style.border, lineWidth: 1)
                }
            }
    }
}

private struct BadgeStyle {
    let role: String

    var hasContainer: Bool {
        switch normalizedRole {
        case "go", "plus", "pro":
            return true
        default:
            return false
        }
    }

    var text: Color {
        switch normalizedRole {
        case "go":
            return Color(nsColor: .systemBlue)
        case "plus":
            return Color(nsColor: .systemGreen)
        case "pro":
            return Color(nsColor: .systemPurple)
        case "free":
            return QuotaPopoverColors.mutedText
        default:
            return QuotaPopoverColors.primaryText
        }
    }

    var background: Color {
        switch normalizedRole {
        case "go":
            return Color(nsColor: .systemBlue).opacity(0.12)
        case "plus":
            return Color(nsColor: .systemGreen).opacity(0.13)
        case "pro":
            return Color(nsColor: .systemPurple).opacity(0.13)
        default:
            return Color.clear
        }
    }

    var border: Color {
        switch normalizedRole {
        case "go":
            return Color(nsColor: .systemBlue).opacity(0.45)
        case "plus":
            return Color(nsColor: .systemGreen).opacity(0.5)
        case "pro":
            return Color(nsColor: .systemPurple).opacity(0.5)
        default:
            return Color.clear
        }
    }

    private var normalizedRole: String {
        role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct QuotaRow: View {
    let window: QuotaWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center) {
                Text(displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(QuotaPopoverColors.titleText)

                Spacer(minLength: 12)

                Label(resetText, systemImage: "clock")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(QuotaPopoverColors.mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(displayPercent)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(QuotaPopoverColors.primaryText)
                    .monospacedDigit()
                Text("%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(QuotaPopoverColors.titleText)
            }

            QuotaScaleLabels()

            QuotaScaleTrack(value: window.usedPercent, color: progressColor)
        }
    }

    private var displayTitle: String {
        switch window.windowDurationMins {
        case 300:
            return I18n.current.currentSession
        case 10080:
            return I18n.current.recentWeek
        case let duration?:
            return I18n.current.durationTitle(minutes: duration)
        default:
            return window.title
        }
    }

    private var displayPercent: Int {
        Int(window.usedPercent.rounded())
    }

    private var progressColor: Color {
        switch window.remainingPercent {
        case ...20:
            return Color(nsColor: .systemRed)
        case ...50:
            return QuotaPalette.warningColor
        default:
            return Color(nsColor: .systemGreen)
        }
    }

    private var resetText: String {
        guard let resetsAt = window.resetsAt else {
            return I18n.current.resetTimeUnavailable
        }

        if window.windowDurationMins == 10080 {
            return I18n.current.refreshAt(Self.dateFormatter().string(from: resetsAt))
        }

        let minutesUntilReset = Int(ceil(max(0, resetsAt.timeIntervalSinceNow) / 60))
        guard minutesUntilReset > 0 else {
            return I18n.current.resetSoon
        }

        let days = minutesUntilReset / 1_440
        let hours = (minutesUntilReset % 1_440) / 60
        let minutes = minutesUntilReset % 60

        if days > 0 {
            return I18n.current.resetIn(days: days, hours: Self.twoDigit(hours), minutes: Self.twoDigit(minutes))
        }

        return I18n.current.resetIn(days: days, hours: Self.twoDigit(hours), minutes: Self.twoDigit(minutes))
    }

    private static func twoDigit(_ value: Int) -> String {
        String(format: "%02d", value)
    }

    private static func dateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: I18n.current.dateLocaleIdentifier)
        formatter.dateFormat = I18n.current.dateFormat
        return formatter
    }
}

private struct QuotaScaleLabels: View {
    private let ticks: [ScaleTick] = [
        ScaleTick(value: 0, label: "0%"),
        ScaleTick(value: 0.5, label: "50%"),
        ScaleTick(value: 0.9, label: "90%"),
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(ticks) { tick in
                    Text(tick.label)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(tick.value == 0.9 ? QuotaPopoverColors.mutedText : QuotaPopoverColors.scaleText)
                        .monospacedDigit()
                        .position(x: xPosition(for: tick.value, in: proxy.size.width), y: 8)
                }
            }
        }
        .frame(height: 16)
    }

    private func xPosition(for value: Double, in width: CGFloat) -> CGFloat {
        let edgeInset: CGFloat = 16
        return min(max(width * CGFloat(value), edgeInset), max(edgeInset, width - edgeInset))
    }
}

private struct QuotaScaleTrack: View {
    let value: Double
    let color: Color

    private let markerValue = 0.9

    var body: some View {
        Canvas { context, size in
            let centerY = size.height / 2
            let tickWidth: CGFloat = 2
            let tickHeight: CGFloat = 7
            let tickSpacing: CGFloat = 5
            let corner = CGSize(width: 1, height: 1)
            let clampedValue = min(max(value, 0), 100)
            let activeWidth = size.width * CGFloat(clampedValue / 100)

            var x: CGFloat = 0
            while x <= size.width {
                let tickRect = CGRect(
                    x: x,
                    y: centerY - tickHeight / 2,
                    width: tickWidth,
                    height: tickHeight
                )
                context.fill(
                    Path(roundedRect: tickRect, cornerSize: corner),
                    with: .color(QuotaPopoverColors.track)
                )
                x += tickSpacing
            }

            if activeWidth > 0 {
                let activeRect = CGRect(
                    x: 0,
                    y: centerY - tickHeight / 2,
                    width: activeWidth,
                    height: tickHeight
                )
                context.fill(
                    Path(roundedRect: activeRect, cornerSize: CGSize(width: tickHeight / 2, height: tickHeight / 2)),
                    with: .color(color)
                )
            }

            let markerX = size.width * CGFloat(markerValue)
            let markerRect = CGRect(x: markerX - 1.5, y: centerY - 8, width: 3, height: 16)
            context.fill(
                Path(roundedRect: markerRect, cornerSize: CGSize(width: 1.5, height: 1.5)),
                with: .color(QuotaPopoverColors.marker)
            )
        }
        .frame(height: 18)
    }
}

private struct ScaleTick: Identifiable {
    let value: Double
    let label: String

    var id: Double {
        value
    }
}

private enum QuotaPopoverColors {
    static let primaryText = Color(nsColor: .labelColor)
    static let titleText = Color(nsColor: .labelColor)
    static let mutedText = Color(nsColor: .secondaryLabelColor)
    static let scaleText = Color(nsColor: .tertiaryLabelColor)
    static let track = Color(nsColor: .tertiaryLabelColor).opacity(0.26)
    static let marker = Color(nsColor: .secondaryLabelColor)
}
