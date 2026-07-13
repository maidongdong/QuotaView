import AppKit

final class SegmentedQuotaBar: NSView {
    var percent = 0 {
        didSet {
            needsDisplay = true
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 250, height: 13)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let segmentCount = 16
        let gap: CGFloat = 2
        let segmentWidth = (bounds.width - CGFloat(segmentCount - 1) * gap) / CGFloat(segmentCount)
        let filled = Int(ceil(Double(segmentCount) * Double(percent) / 100.0))
        let activeColor = color(for: percent)

        for index in 0..<segmentCount {
            let rect = NSRect(
                x: CGFloat(index) * (segmentWidth + gap),
                y: 0,
                width: segmentWidth,
                height: bounds.height
            )
            let path = NSBezierPath(
                roundedRect: rect,
                xRadius: 2.5,
                yRadius: 2.5
            )
            (index < filled ? activeColor : NSColor.quaternaryLabelColor).setFill()
            path.fill()
        }
    }

    private func color(for percent: Int) -> NSColor {
        switch percent {
        case 51...:
            return .systemGreen
        case 21...:
            return .systemOrange
        default:
            return .systemRed
        }
    }
}

final class QuotaRowView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let bar = SegmentedQuotaBar()
    private let detailLabel = NSTextField(labelWithString: "")

    init(title: String) {
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        bar.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .right

        detailLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byClipping

        addSubview(titleLabel)
        addSubview(bar)
        addSubview(detailLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 42),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.widthAnchor.constraint(equalToConstant: 48),

            bar.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 10),
            bar.centerYAnchor.constraint(equalTo: centerYAnchor),

            detailLabel.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 10),
            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            detailLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            detailLabel.widthAnchor.constraint(equalToConstant: 160)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(window: RateLimitWindow?, placeholder: String = "等待数据…") {
        guard let window else {
            bar.percent = 0
            detailLabel.stringValue = placeholder
            return
        }

        bar.percent = window.remainingPercent
        detailLabel.stringValue = "\(window.remainingPercent)% · \(QuotaText.resetTime(window.resetsAt, compact: false))"
    }
}

final class SettingsDisclosureView: NSView {
    var onClick: (() -> Void)?

    private let label = NSTextField(labelWithString: "")

    override var intrinsicContentSize: NSSize {
        NSSize(width: 70, height: 22)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        setExpanded(false)

        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 22),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setExpanded(_ expanded: Bool) {
        label.stringValue = expanded ? "设置 ▾" : "设置 ▸"
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

final class QuotaPanelViewController: NSViewController {
    var onRefresh: (() -> Void)?
    var onLoginLaunchChange: ((Bool) -> Void)?
    var onOpenLoginItemsSettings: (() -> Void)?
    var onSettingsExpanded: (() -> Void)?
    var onPreferredContentSizeChange: ((NSSize) -> Void)?
    var onQuit: (() -> Void)?

    private let panelWidth: CGFloat = 506
    private let collapsedHeight: CGFloat = 120
    private let weeklyRow = QuotaRowView(title: "周限额")
    private let updatedLabel = NSTextField(labelWithString: "")
    private let settingsDisclosureView = SettingsDisclosureView()
    private let loginLaunchCheckbox = NSButton()
    private let loginLaunchMessage = NSTextField(wrappingLabelWithString: "")
    private let openSettingsButton = NSButton()
    private let loginLaunchMessageRow = NSStackView()
    private let settingsDetails = NSStackView()
    private var rootHeightConstraint: NSLayoutConstraint?
    private var settingsExpanded = false

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: collapsedHeight))
        root.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Codex 剩余额度")
        title.font = .systemFont(ofSize: 14, weight: .bold)

        updatedLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        updatedLabel.textColor = .tertiaryLabelColor

        let refreshButton = NSButton(title: "立即刷新", target: self, action: #selector(refresh))
        refreshButton.bezelStyle = .rounded
        refreshButton.controlSize = .small

        let quitButton = NSButton(title: "退出", target: self, action: #selector(quit))
        quitButton.bezelStyle = .rounded
        quitButton.controlSize = .small

        let header = NSStackView(views: [title, NSView(), refreshButton, quitButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8

        settingsDisclosureView.onClick = { [weak self] in
            self?.toggleSettings()
        }

        let footer = NSStackView(views: [settingsDisclosureView, NSView(), updatedLabel])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8

        loginLaunchCheckbox.setButtonType(.switch)
        loginLaunchCheckbox.title = "开机自动启动"
        loginLaunchCheckbox.target = self
        loginLaunchCheckbox.action = #selector(loginLaunchChanged)
        loginLaunchCheckbox.font = .systemFont(ofSize: 11)

        loginLaunchMessage.font = .systemFont(ofSize: 10)
        loginLaunchMessage.textColor = .secondaryLabelColor
        loginLaunchMessage.maximumNumberOfLines = 2
        loginLaunchMessage.isHidden = true

        openSettingsButton.title = "打开系统设置"
        openSettingsButton.target = self
        openSettingsButton.action = #selector(openLoginItemsSettings)
        openSettingsButton.bezelStyle = .rounded
        openSettingsButton.controlSize = .small
        openSettingsButton.isHidden = true

        loginLaunchMessageRow.orientation = .horizontal
        loginLaunchMessageRow.alignment = .centerY
        loginLaunchMessageRow.spacing = 8
        loginLaunchMessageRow.addArrangedSubview(loginLaunchMessage)
        loginLaunchMessageRow.addArrangedSubview(NSView())
        loginLaunchMessageRow.addArrangedSubview(openSettingsButton)
        loginLaunchMessageRow.isHidden = true

        settingsDetails.orientation = .vertical
        settingsDetails.alignment = .leading
        settingsDetails.spacing = 4
        settingsDetails.addArrangedSubview(loginLaunchCheckbox)
        settingsDetails.addArrangedSubview(loginLaunchMessageRow)
        settingsDetails.isHidden = true

        let stack = NSStackView(
            views: [header, weeklyRow, footer, settingsDetails]
        )
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        root.addSubview(stack)

        let rootHeightConstraint = root.heightAnchor.constraint(equalToConstant: collapsedHeight)
        self.rootHeightConstraint = rootHeightConstraint
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: panelWidth),
            rootHeightConstraint,
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            weeklyRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            settingsDetails.widthAnchor.constraint(equalTo: stack.widthAnchor),
            loginLaunchMessageRow.widthAnchor.constraint(equalTo: settingsDetails.widthAnchor)
        ])

        preferredContentSize = NSSize(width: panelWidth, height: collapsedHeight)
        view = root
    }

    func update(state: QuotaDisplayState) {
        _ = view
        let placeholder = state.status.isEmpty ? "等待数据…" : state.status
        weeklyRow.update(window: state.weekly, placeholder: placeholder)
        updatedLabel.stringValue = QuotaText.updatedTime(state.updatedAt)
    }

    func refreshClock(state: QuotaDisplayState) {
        update(state: state)
    }

    func update(loginLaunchState: LoginLaunchState) {
        _ = view

        loginLaunchCheckbox.state = loginLaunchState.desiredEnabled ? .on : .off
        loginLaunchCheckbox.isEnabled = true
        loginLaunchMessage.isHidden = true
        openSettingsButton.isHidden = true
        loginLaunchMessageRow.isHidden = true

        switch loginLaunchState.systemState {
        case .disabled, .enabled:
            break
        case .requiresApproval:
            loginLaunchMessage.stringValue = "需要在系统设置的“登录项”中允许此应用。"
            loginLaunchMessage.isHidden = false
            openSettingsButton.isHidden = false
            loginLaunchMessageRow.isHidden = false
        case .installRequired:
            loginLaunchCheckbox.isEnabled = false
            loginLaunchMessage.stringValue = "请先将应用拖入“应用程序”文件夹后重新打开。"
            loginLaunchMessage.isHidden = false
            loginLaunchMessageRow.isHidden = false
        case let .failed(message):
            loginLaunchMessage.stringValue = message
            loginLaunchMessage.isHidden = false
            loginLaunchMessageRow.isHidden = false
        }

        if settingsExpanded {
            performWithoutAnimation {
                applyPreferredPanelSize()
            }
        }
    }

    func collapseSettings() {
        _ = view
        guard settingsExpanded else {
            return
        }
        setSettingsExpanded(false)
    }

    @objc private func refresh() {
        onRefresh?()
    }

    private func toggleSettings() {
        setSettingsExpanded(!settingsExpanded)
    }

    @objc private func loginLaunchChanged() {
        onLoginLaunchChange?(loginLaunchCheckbox.state == .on)
    }

    @objc private func openLoginItemsSettings() {
        onOpenLoginItemsSettings?()
    }

    @objc private func quit() {
        onQuit?()
    }

    private func setSettingsExpanded(_ expanded: Bool) {
        performWithoutAnimation {
            settingsExpanded = expanded
            settingsDisclosureView.setExpanded(expanded)
            settingsDetails.isHidden = !expanded
            if expanded {
                onSettingsExpanded?()
            }
            applyPreferredPanelSize()
        }
    }

    private func applyPreferredPanelSize() {
        let size = preferredPanelSize()
        rootHeightConstraint?.constant = size.height
        preferredContentSize = size
        onPreferredContentSizeChange?(size)
        view.layoutSubtreeIfNeeded()
    }

    private func preferredPanelSize() -> NSSize {
        guard settingsExpanded else {
            return NSSize(width: panelWidth, height: collapsedHeight)
        }

        settingsDetails.layoutSubtreeIfNeeded()
        let detailsHeight = ceil(settingsDetails.fittingSize.height)
        return NSSize(
            width: panelWidth,
            height: max(collapsedHeight, collapsedHeight + detailsHeight + 6)
        )
    }

    private func performWithoutAnimation(_ changes: () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            changes()
        }
    }
}
