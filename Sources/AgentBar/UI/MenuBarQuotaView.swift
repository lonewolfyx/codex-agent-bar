import AppKit

final class MenuBarQuotaView: NSControl {
    private let iconView = NSImageView()
    private let fiveHourPrefixLabel = NSTextField(labelWithString: "5h")
    private let fiveHourPercentLabel = NSTextField(labelWithString: "--")
    private let weekPrefixLabel = NSTextField(labelWithString: "1w")
    private let weekPercentLabel = NSTextField(labelWithString: "--")
    private let separatorView = MenuBarSeparatorView()
    private let reasoningModelPrefixLabel = NSTextField(labelWithString: "model")
    private let reasoningModelLabel = NSTextField(labelWithString: "--")
    private let reasoningLevelPrefixLabel = NSTextField(labelWithString: "reason")
    private let reasoningLevelLabel = NSTextField(labelWithString: "--")
    private let reasoningStack = NSStackView()
    private let textStack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func update(snapshot: QuotaSnapshot?, modelReasonSnapshot: ModelReasonSnapshot?, statusMessage: String) {
        toolTip = tooltip(statusMessage: statusMessage, modelReasonSnapshot: modelReasonSnapshot)
        updateModelReason(modelReasonSnapshot)

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
        toolTip = I18n.current.codexQuota

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

        [fiveHourPrefixLabel, fiveHourPercentLabel, weekPrefixLabel, weekPercentLabel].forEach { label in
            label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .bold)
            label.alignment = .left
            label.lineBreakMode = .byClipping
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
            label.translatesAutoresizingMaskIntoConstraints = false
        }

        [reasoningModelPrefixLabel, reasoningLevelPrefixLabel].forEach { label in
            label.font = .systemFont(ofSize: 8.5, weight: .medium)
            label.alignment = .left
            label.lineBreakMode = .byClipping
            label.textColor = .labelColor
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
            label.translatesAutoresizingMaskIntoConstraints = false
        }

        [reasoningModelLabel, reasoningLevelLabel].forEach { label in
            label.font = .systemFont(ofSize: 9.5, weight: .semibold)
            label.alignment = .left
            label.lineBreakMode = .byClipping
            label.textColor = .labelColor
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
            label.translatesAutoresizingMaskIntoConstraints = false
        }

        separatorView.translatesAutoresizingMaskIntoConstraints = false

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

        let modelRow = makeReasoningRow(prefix: reasoningModelPrefixLabel, value: reasoningModelLabel)
        let levelRow = makeReasoningRow(prefix: reasoningLevelPrefixLabel, value: reasoningLevelLabel)

        reasoningStack.orientation = .vertical
        reasoningStack.alignment = .leading
        reasoningStack.distribution = .fillEqually
        reasoningStack.spacing = -1
        reasoningStack.translatesAutoresizingMaskIntoConstraints = false
        reasoningStack.addArrangedSubview(modelRow)
        reasoningStack.addArrangedSubview(levelRow)

        addSubview(iconView)
        addSubview(textStack)
        addSubview(separatorView)
        addSubview(reasoningStack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: NSStatusBar.system.thickness),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 5),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.widthAnchor.constraint(equalToConstant: 50),
            textStack.heightAnchor.constraint(equalToConstant: 24),

            separatorView.leadingAnchor.constraint(equalTo: textStack.trailingAnchor, constant: 5),
            separatorView.centerYAnchor.constraint(equalTo: centerYAnchor),
            separatorView.widthAnchor.constraint(equalToConstant: 1),
            separatorView.heightAnchor.constraint(equalToConstant: 16),

            reasoningStack.leadingAnchor.constraint(equalTo: separatorView.trailingAnchor, constant: 6),
            reasoningStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            reasoningStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            reasoningStack.widthAnchor.constraint(equalToConstant: 70),
            reasoningStack.heightAnchor.constraint(equalToConstant: 24),
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

    private func makeReasoningRow(prefix: NSTextField, value: NSTextField) -> NSStackView {
        let row = NSStackView(views: [prefix, value])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .gravityAreas
        row.spacing = 3
        row.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            prefix.widthAnchor.constraint(equalToConstant: 29),
            value.widthAnchor.constraint(equalToConstant: 38),
        ])

        return row
    }

    private func updateModelReason(_ snapshot: ModelReasonSnapshot?) {
        guard let snapshot else {
            reasoningModelLabel.stringValue = "--"
            reasoningLevelLabel.stringValue = "--"
            reasoningModelLabel.textColor = .secondaryLabelColor
            reasoningLevelLabel.textColor = .secondaryLabelColor
            return
        }

        reasoningModelLabel.stringValue = snapshot.selected.displayModel
        reasoningLevelLabel.stringValue = snapshot.selected.displayReasoningEffort
        reasoningModelLabel.textColor = .labelColor
        reasoningLevelLabel.textColor = .labelColor
    }

    private func tooltip(statusMessage: String, modelReasonSnapshot: ModelReasonSnapshot?) -> String {
        guard let modelReasonSnapshot else {
            return statusMessage
        }

        let selected = modelReasonSnapshot.selected
        return "\(statusMessage)\nmodel reason: \(selected.displayModel) \(selected.displayReasoningEffort) \(selected.score)\nData: codexradar.com"
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

private final class MenuBarSeparatorView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        updateSeparatorColor()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        updateSeparatorColor()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSeparatorColor()
    }

    private func updateSeparatorColor() {
        layer?.backgroundColor = NSColor(calibratedWhite: 0.82, alpha: 1).cgColor
    }
}
