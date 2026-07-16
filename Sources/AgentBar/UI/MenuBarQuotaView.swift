import AppKit

final class MenuBarQuotaView: NSControl {
    private let iconView = NSImageView()
    private let weekPrefixLabel = NSTextField(labelWithString: I18n.current.shortWeek)
    private let weekPercentLabel = NSTextField(labelWithString: "--")

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

        guard let snapshot else {
            weekPrefixLabel.stringValue = I18n.current.shortWeek
            weekPercentLabel.stringValue = "--"
            weekPercentLabel.textColor = .secondaryLabelColor
            return
        }

        weekPrefixLabel.stringValue = snapshot.weekly.shortTitle
        weekPercentLabel.stringValue = "\(Int(snapshot.weekly.remainingPercent.rounded()))%"
        weekPercentLabel.textColor = quotaColor(forRemainingPercent: snapshot.weekly.remainingPercent)
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

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            weekRow.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 5),
            weekRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            weekRow.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func makeTextRow(prefix: NSTextField, percent: NSTextField) -> NSStackView {
        let row = NSStackView(views: [prefix, percent])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .gravityAreas
        row.spacing = 5
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
