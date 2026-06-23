import AppKit

final class MenuBarQuotaView: NSControl {
    private let iconView = NSImageView()
    private let fiveHourPrefixLabel = NSTextField(labelWithString: "5h")
    private let fiveHourPercentLabel = NSTextField(labelWithString: "--")
    private let weekPrefixLabel = NSTextField(labelWithString: "1w")
    private let weekPercentLabel = NSTextField(labelWithString: "--")
    private let textStack = NSStackView()

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
            fiveHourPrefixLabel.stringValue = "5h"
            fiveHourPercentLabel.stringValue = "--"
            fiveHourPercentLabel.textColor = .secondaryLabelColor
            weekPrefixLabel.stringValue = "1w"
            weekPercentLabel.stringValue = "--"
            weekPercentLabel.textColor = .secondaryLabelColor
            return
        }

        fiveHourPrefixLabel.stringValue = snapshot.primary.shortTitle
        fiveHourPercentLabel.stringValue = "\(Int(snapshot.primary.remainingPercent.rounded()))%"
        fiveHourPercentLabel.textColor = quotaColor(forRemainingPercent: snapshot.primary.remainingPercent)

        weekPrefixLabel.stringValue = snapshot.secondary.shortTitle
        weekPercentLabel.stringValue = "\(Int(snapshot.secondary.remainingPercent.rounded()))%"
        weekPercentLabel.textColor = quotaColor(forRemainingPercent: snapshot.secondary.remainingPercent)
    }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }

    private func setup() {
        wantsLayer = true
        toolTip = "Codex quota"

        if let image = AppIcon.menuBarImage() {
            iconView.image = image
            iconView.contentTintColor = nil
        } else {
            iconView.image = NSImage(systemSymbolName: "chart.pie.fill", accessibilityDescription: "Codex quota")
            iconView.contentTintColor = .labelColor
        }
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        [fiveHourPrefixLabel, fiveHourPercentLabel, weekPrefixLabel, weekPercentLabel].forEach { label in
            label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .bold)
            label.alignment = .left
            label.lineBreakMode = .byClipping
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
            label.translatesAutoresizingMaskIntoConstraints = false
        }

        fiveHourPrefixLabel.textColor = .labelColor
        weekPrefixLabel.textColor = .labelColor
        fiveHourPercentLabel.textColor = .secondaryLabelColor
        weekPercentLabel.textColor = .secondaryLabelColor

        let fiveHourRow = makeTextRow(prefix: fiveHourPrefixLabel, percent: fiveHourPercentLabel)
        let weekRow = makeTextRow(prefix: weekPrefixLabel, percent: weekPercentLabel)

        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.distribution = .fillEqually
        textStack.spacing = -1
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.addArrangedSubview(fiveHourRow)
        textStack.addArrangedSubview(weekRow)

        addSubview(iconView)
        addSubview(textStack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: NSStatusBar.system.thickness),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 5),
            textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    private func makeTextRow(prefix: NSTextField, percent: NSTextField) -> NSStackView {
        let row = NSStackView(views: [prefix, percent])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .gravityAreas
        row.spacing = 5
        row.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            prefix.widthAnchor.constraint(equalToConstant: 17),
            percent.widthAnchor.constraint(equalToConstant: 28),
        ])

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
