import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let panelController = QuotaPanelViewController()
    private let popover = NSPopover()
    private let loginLaunchManager = LoginLaunchManager()

    private var statusItem: NSStatusItem!
    private var client: CodexAppServerClient!
    private var state = QuotaDisplayState.loading
    private var clockTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePopover()
        configureCallbacks()
        configureLoginLaunch()

        client = CodexAppServerClient { [weak self] state in
            self?.apply(state)
        }
        client.start()

        clockTimer = Timer.scheduledTimer(
            timeInterval: 1,
            target: self,
            selector: #selector(clockTick),
            userInfo: nil,
            repeats: true
        )

        apply(state)
    }

    func applicationWillTerminate(_ notification: Notification) {
        clockTimer?.invalidate()
        client?.stop()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else {
            return
        }

        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.target = self
        button.action = #selector(togglePopover)
        button.toolTip = "Codex 剩余额度"
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = panelController
    }

    private func configureCallbacks() {
        panelController.onRefresh = { [weak self] in
            self?.client?.refresh()
        }
        panelController.onLoginLaunchChange = { [weak self] enabled in
            self?.loginLaunchManager.setEnabled(enabled)
        }
        panelController.onOpenLoginItemsSettings = {
            SMAppService.openSystemSettingsLoginItems()
        }
        panelController.onSettingsExpanded = { [weak self] in
            self?.loginLaunchManager.refresh()
        }
        panelController.onPreferredContentSizeChange = { [weak self] size in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                self?.popover.contentSize = size
            }
        }
        panelController.onQuit = {
            NSApp.terminate(nil)
        }
    }

    private func configureLoginLaunch() {
        loginLaunchManager.onStateChange = { [weak self] state in
            self?.panelController.update(loginLaunchState: state)
        }
        panelController.update(loginLaunchState: loginLaunchManager.state)
        loginLaunchManager.synchronizeOnLaunch()
    }

    private func apply(_ newState: QuotaDisplayState) {
        state = newState
        panelController.update(state: newState)
        updateStatusTitle()
    }

    private func updateStatusTitle() {
        let fiveHour = state.fiveHour.map { "\($0.remainingPercent)%" } ?? "--"
        let weekly = state.weekly.map { "\($0.remainingPercent)%" } ?? "--"
        statusItem.button?.title = "5h \(fiveHour)  周 \(weekly)"
    }

    @objc private func clockTick() {
        panelController.refreshClock(state: state)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            panelController.collapseSettings()
            loginLaunchManager.refresh()
            client.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
