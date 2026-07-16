import AppKit

final class MenuBarQuotaView: NSControl {
    private enum Metrics {
        static let horizontalPadding: CGFloat = 6
        static let iconSize: CGFloat = 18
        static let iconSpacing: CGFloat = 5
        static let textSpacing: CGFloat = 5
    }

    private let iconView = NSImageView()
    private let weekPrefixLabel = NSTextField(labelWithString: I18n.current.shortWeek)
    private let weekPercentLabel = NSTextField(labelWithString: "--")

    var preferredWidth: CGFloat {
        ceil(
            Metrics.horizontalPadding * 2
                + Metrics.iconSize
                + Metrics.iconSpacing
                + weekPrefixLabel.intrinsicContentSize.width
                + Metrics.textSpacing
                + weekPercentLabel.intrinsicContentSize.width
        )
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: preferredWidth, height: NSStatusBar.system.thickness)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func update(snapshot: QuotaSnapshot?, statusMessage: String) {
        toolTip = statusMessage

        if let snapshot {
            weekPrefixLabel.stringValue = snapshot.weekly.shortTitle
            weekPercentLabel.stringValue = "\(Int(snapshot.weekly.remainingPercent.rounded()))%"
            weekPercentLabel.textColor = quotaColor(forRemainingPercent: snapshot.weekly.remainingPercent)
        } else {
            weekPrefixLabel.stringValue = I18n.current.shortWeek
            weekPercentLabel.stringValue = "--"
            weekPercentLabel.textColor = .secondaryLabelColor
        }

        invalidateIntrinsicContentSize()
    }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }

    private func setup() {
        wantsLayer = true
        toolTip = I18n.current.codexQuota
        let defaultMenuBarFont = NSFont.menuBarFont(ofSize: 0)

        if let image = AppIcon.menuBarImage() {
            iconView.image = image
            iconView.contentTintColor = nil
        } else {
            iconView.image = NSImage(systemSymbolName: "chart.pie.fill", accessibilityDescription: I18n.current.codexQuota)
            iconView.contentTintColor = .labelColor
        }
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        [weekPrefixLabel, weekPercentLabel].forEach { label in
            label.font = defaultMenuBarFont
            label.alignment = .left
            label.lineBreakMode = .byClipping
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
            label.translatesAutoresizingMaskIntoConstraints = false
        }

        weekPrefixLabel.textColor = .labelColor
        weekPercentLabel.textColor = .secondaryLabelColor

        let weekRow = makeTextRow(prefix: weekPrefixLabel, percent: weekPercentLabel)

        addSubview(iconView)
        addSubview(weekRow)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: NSStatusBar.system.thickness),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalPadding),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Metrics.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Metrics.iconSize),

            weekRow.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: Metrics.iconSpacing),
            weekRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.horizontalPadding),
            weekRow.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func makeTextRow(prefix: NSTextField, percent: NSTextField) -> NSStackView {
        let row = NSStackView(views: [prefix, percent])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .gravityAreas
        row.spacing = Metrics.textSpacing
        row.translatesAutoresizingMaskIntoConstraints = false

        return row
    }

    private func quotaColor(forRemainingPercent percent: Double) -> NSColor {
        switch percent {
        case ...20:
            return .systemRed
        case ...50:
            return QuotaPalette.warningNSColor
        default:
            return .systemGreen
        }
    }
}
