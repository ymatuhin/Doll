import AppKit
import Monitor
import SwiftUI

let defaultIconSize: CGFloat = 20
let defaultIcon = #imageLiteral(resourceName: "DefaultStatusBarIcon")

class StatusBarController {
    private var statusBar: NSStatusBar!
    private var isDark = false
    private var latestBadgeText = ""
    private var latestMessageCount = 0
    private var isHidden = false
    private var positionDefaultsKey: String?
    private var positionBackupKey: String?
    private var savedPosition: Any?

    private var giantBadgeController = GiantBadgeViewController()
    private var giantBadgePanel = NSPanel(contentRect: NSRect(origin: .zero, size: defaultWindowSize),
                              styleMask: [.nonactivatingPanel],
                              backing: .buffered, defer: false)
    private var lastTimeShowingGiantBadge = Date()

    // Not an NSPopover: since macOS 27 a popover anchored to a status item takes the system
    // keyboard focus away from the app the user is typing in, for as long as it is shown.
    private var notificationPanel = NonKeyPanel(contentRect: .zero,
                                                styleMask: [.borderless, .nonactivatingPanel],
                                                backing: .buffered, defer: false)
    private var hideNotificationPanelWork: DispatchWorkItem?

    public var statusItem: NSStatusItem!
    public var monitoredApp: MonitoredApp? {
        didSet {
            refreshIcon()
        }
    }
    private var monitoredAppIcon: NSImage?

    init() {
        setupStatusBar()
    }

    func setupStatusBar(icon: NSImage? = nil) {
        statusBar = .system
        statusItem = statusBar.statusItem(withLength: defaultIconSize)
        if let statusBarButton = statusItem.button {
            statusBarButton.sendAction(on: [.leftMouseUp, .rightMouseUp])
            statusBarButton.image = icon ?? defaultIcon
            statusBarButton.image?.size = NSSize(width: defaultIconSize, height: defaultIconSize)
            statusBarButton.image?.isTemplate = false
            statusBarButton.imagePosition = .imageLeft
            statusBarButton.action = #selector(onIconClicked(sender:))
            statusBarButton.target = self
            statusBarButton.toolTip = NSLocalizedString("Hold option key ⌥ and click to config", comment: "")
        }

        giantBadgePanel.isOpaque = false
        giantBadgePanel.hasShadow = false
        giantBadgePanel.backgroundColor = NSColor.clear
    }

    func refreshIcon() {
        monitoredAppIcon = Storage.appIcon(for: monitoredApp?.bundleId ?? "")

        if(AppSettings.isIconMask(for: monitoredApp?.appName ?? "") && isDark) {
            monitoredAppIcon = monitoredAppIcon?.invert()
        }

        updateBadgeText(latestBadgeText, force: true)
    }

    @objc func onIconClicked(sender: AnyObject) {
        hideGiantBadge()

        let noAppSelected = statusItem.button?.image == defaultIcon
        let isOptionKeyHolding = NSEvent.modifierFlags.contains(.option)
        let isRightClick = NSApp.currentEvent?.isRightClick == true

        if noAppSelected || isOptionKeyHolding || isRightClick {
            MonitorEngine.shared.showConfigWindow()
        } else if let monitoredAppName = monitoredApp?.appName,
                  let monitoredAppBundleId = monitoredApp?.bundleId {
            let appRunning = MonitorService.isMonitoredAppRunning(bundleIdentifier: monitoredAppBundleId)
            if !appRunning {
                guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: monitoredAppBundleId) else {
                    return
                }

                NSWorkspace.shared.open(appURL)
            } else {
                if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == monitoredAppBundleId {
                    // Hide the app
                    NSWorkspace.shared.frontmostApplication?.hide()
                } else {
                    // Send the app window to front most
                    MonitorService.openMonitoredApp(appName: monitoredAppName)
                }
            }
        }
    }

    func monitorApp(app: MonitoredApp) {
        monitoredApp = app

        guard let appFullPath = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId)?.absoluteURL.path else {
            return
        }

        guard let targetBundle = Bundle(path: appFullPath) else {
            return
        }

        let appName = app.appName
        let autosaveName = "Doll_\(app.bundleId)"
        positionDefaultsKey = "NSStatusItem Preferred Position \(autosaveName)"
        positionBackupKey = "Doll_SavedPosition_\(app.bundleId)"
        // Re-seed the OS position from our own backup before macOS reads it (it reads when
        // the item is given its autosaveName), so a pinned slot survives a Doll restart or
        // reboot even when the monitored app was closed at the time — macOS discards its own
        // copy whenever the item is hidden.
        if let positionBackupKey, let backup = UserDefaults.standard.object(forKey: positionBackupKey) {
            savedPosition = backup
            if let positionDefaultsKey, UserDefaults.standard.object(forKey: positionDefaultsKey) == nil {
                UserDefaults.standard.set(backup, forKey: positionDefaultsKey)
            }
        }
        statusItem.autosaveName = autosaveName
        updateBadgeText(nil)

        guard let monitoredAppIcon = monitoredAppIcon else {
            return
        }
        updateBadgeIcon(icon: monitoredAppIcon, size: CGSize(width: defaultIconSize, height: defaultIconSize))

        MonitorService.observe(appName: appName) { [weak self] badge in
            let appRunning = MonitorService.isMonitoredAppRunning(bundleIdentifier: targetBundle.bundleIdentifier ?? "")
            let appIsNotRunningAndIconShouldBeHidden = AppSettings.hideWhenAppNotRunning && !appRunning
            let badgeIsEmptyAndIconShouldBeHidden = AppSettings.hideWhenNothingComing && (badge.isNil || badge?.isEmpty == true)

            if appIsNotRunningAndIconShouldBeHidden || badgeIsEmptyAndIconShouldBeHidden {
                self?.hideStatusBar()
            } else {
                self?.showStatusBar()
                let currentIsDark = self?.statusItem.button?.effectiveAppearance.name.rawValue.lowercased().contains("dark") ?? false
                if(self?.isDark != currentIsDark) {
                    self?.isDark = currentIsDark
                    self?.refreshIcon()
                }

                self?.updateBadgeText(badge)
            }

            self?.repositionGiantBadge()
        }
    }

    func hideStatusBar() {
        guard !isHidden else { return }
        isHidden = true
        // Remember the OS-managed menu-bar slot before hiding. Setting isVisible = false
        // makes macOS discard the saved position (FB9052637), so we snapshot it — in memory
        // and in our own default, so it also survives a Doll restart / reboot — and write it
        // back in showStatusBar() / monitorApp() before the item reappears.
        // https://github.com/feedback-assistant/reports/issues/200
        if let positionDefaultsKey, let pos = UserDefaults.standard.object(forKey: positionDefaultsKey) {
            savedPosition = pos
            if let positionBackupKey {
                UserDefaults.standard.set(pos, forKey: positionBackupKey)
            }
        }
        statusItem.isVisible = false
    }

    func showStatusBar() {
        guard isHidden else { return }
        isHidden = false
        if let positionDefaultsKey, let savedPosition {
            UserDefaults.standard.set(savedPosition, forKey: positionDefaultsKey)
        }
        statusItem.isVisible = true
        refreshIcon()
    }

    func updateBadgeText(_ text: String?, force: Bool = false) {
        guard !isHidden else { return }
        statusItem.isVisible = true

        guard !AppSettings.showOnlyAppIcon else {
            latestBadgeText = text ?? ""
            refreshAppIcon()
            return
        }

        guard force || statusItem.button?.title != text else {
            return
        }

        // New notification comes in
        let newText = text ?? ""

        if newText.isEmpty {
            hideGiantBadge()
        }

        guard let monitoredAppIcon = monitoredAppIcon else {
            return
        }

        if AppSettings.showAsRedBadge {
            let defaultIcon = monitoredAppIcon.addBadgeToImage(drawText: newText)
            let adjustedIcon = (newText.isEmpty && AppSettings.grayoutIconWhenNothingComing) ? (defaultIcon.grayOut() ?? defaultIcon) : defaultIcon
            updateBadgeIcon(icon: adjustedIcon)
            statusItem.length = defaultIconSize
            statusItem.button?.title = ""
        } else {
            let defaultIcon = monitoredAppIcon
            let adjustedIcon = (newText.isEmpty && AppSettings.grayoutIconWhenNothingComing) ? (defaultIcon.grayOut() ?? defaultIcon) : defaultIcon
            updateBadgeIcon(icon: adjustedIcon, size: CGSize(width: defaultIconSize, height: defaultIconSize))

            // Set title first
            statusItem.button?.title = newText

            // Calculate text width
            let textWidth = (newText)
                .width(withConstrainedHeight: defaultIconSize, font: .systemFont(ofSize: 14))

            // Account for NSStatusBarButton's internal spacing between image and title (typically 4-6pt)
            // macOS 15.2 enforces this spacing more strictly
            let interElementSpacing: CGFloat = 4
            statusItem.length = defaultIconSize + interElementSpacing + textWidth

            // Force layout update
            statusItem.button?.needsLayout = true
            statusItem.button?.layoutSubtreeIfNeeded()
        }

        let newMessageCount = Int(newText) ?? 0
        if latestBadgeText != newText {
            if AppSettings.showAlertInFullScreenMode {
                tryShowTheNewNotificationPopover(newText: newText)
            }

            let frontmostAppIsMonitoredApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == monitoredApp?.bundleId
            if !frontmostAppIsMonitoredApp, AppSettings.isGiantBadgeEnabled(for: monitoredApp?.appName ?? "") {
                // Don't show giant badge when message count is decreasing
                if newMessageCount >= latestMessageCount {
                    tryShowGiantBadge(text)
                } else {
                    hideGiantBadge()
                }
            } else {
                hideGiantBadge()
            }
        }

        latestBadgeText = newText
        latestMessageCount = newMessageCount
    }

    func refreshDisplayMode() {
        if AppSettings.showOnlyAppIcon {
            refreshAppIcon()
        } else {
            updateBadgeText(latestBadgeText, force: true)
        }
    }

    func refreshAppIcon() {
        guard let monitoredAppIcon else { return }
        let adjustedIcon = (latestBadgeText.isEmpty && AppSettings.grayoutIconWhenNothingComing) ? (monitoredAppIcon.grayOut() ?? monitoredAppIcon) : monitoredAppIcon
        statusItem.length = defaultIconSize
        statusItem.button?.title = ""
        updateBadgeIcon(icon: adjustedIcon, size: CGSize(width: defaultIconSize, height: defaultIconSize))
    }

    func updateBadgeIcon(icon: NSImage?, size: CGSize? = nil) {
        statusItem.button?.image = icon
        if let iconSize = size ?? icon?.size {
            statusItem.button?.image?.size = iconSize
        }
    }

    func tryShowGiantBadge(_ text: String?) {
        let now = Date()
        if !giantBadgePanel.isVisible || now.timeIntervalSince(lastTimeShowingGiantBadge) >= 3 {
            lastTimeShowingGiantBadge = now
            let currentActiveWindowIsFullScreen = Utils.currentActiveWindowIsFullScreen

            if giantBadgePanel.contentViewController != nil {
                giantBadgeController.animationFlag.toggle()
            } else {
                let giantBadgeView = GiantBadgeView(controller: giantBadgeController) { [weak self] in
                    guard let self = self else { return }
                    self.onIconClicked(sender: self)
                }
                giantBadgePanel.contentViewController = NSHostingController(rootView: giantBadgeView)
                giantBadgePanel.setContentSize(giantBadgeSize)
            }

            repositionGiantBadge()
            giantBadgePanel.level = .popUpMenu
            giantBadgePanel.setIsVisible(true)
            giantBadgePanel.orderFrontRegardless()
        }
    }

    func repositionGiantBadge() {
        guard let activeScreen = NSScreen.screenWithMouse,
           let iconFrame = statusItem.button?.window?.frame else {
            return
        }

        var menubarOffset: CGFloat = 0
        if Utils.currentActiveWindowIsFullScreen {
            // In mac with notch, the menubar didn't affect window's size
            menubarOffset = activeScreen.hasTopNotchDesign ? 0 : Utils.menubarHeight
        }

        giantBadgePanel.setFrameOrigin(NSPoint(x: iconFrame.midX - giantBadgeSize.width / 2, y: activeScreen.visibleFrame.maxY - giantBadgeSize.height + menubarOffset + giantBadgeYOffset))
    }

    func hideGiantBadge() {
        giantBadgePanel.setIsVisible(false)
    }

    func tryShowTheNewNotificationPopover(newText: String) {
        if Utils.currentActiveWindowIsFullScreen {
            showNotificationPanel(newText: newText)

            hideNotificationPanelWork?.cancel()
            let hideWork = DispatchWorkItem { [weak self] in
                self?.hideNotificationPanel()
            }
            hideNotificationPanelWork = hideWork
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: hideWork)
        }
    }

    func hideNotificationPanel() {
        hideNotificationPanelWork?.cancel()
        hideNotificationPanelWork = nil
        notificationPanel.orderOut(nil)
    }

    func destroy() {
        hideNotificationPanel()
        if let monitoredApp = monitoredApp {
            MonitorService.unObserve(appName: monitoredApp.appName)
            MonitorEngine.shared.unMonitor(app: monitoredApp)
            statusBar.removeStatusItem(statusItem)
            AppSettings.toggleGiantBadge(for: monitoredApp.appName, value: false)
        }
    }

    private func showNotificationPanel(newText: String) {
        guard let iconWindow = statusItem.button?.window,
              let screen = iconWindow.screen ?? NSScreen.screenWithMouse else {
            return
        }

        let textWidth = newText
                .width(withConstrainedHeight: defaultIconSize, font: .systemFont(ofSize: 14))
        let horizonPadding: CGFloat = 32
        let verticalPadding: CGFloat = 16
        let panelSize = NSSize(width: defaultIconSize + textWidth + horizonPadding, height: defaultIconSize + verticalPadding)

        let targetApp = monitoredApp
        let view = NotificationView(icon: monitoredAppIcon ?? defaultIcon, badgeText: newText) { [weak self] in
            self?.hideNotificationPanel()
            if let monitoredAppName = targetApp?.appName {
                MonitorService.openMonitoredApp(appName: monitoredAppName)
            }
        }

        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: panelSize)
        hostingView.autoresizingMask = [.width, .height]
        background.addSubview(hostingView)

        notificationPanel.isOpaque = false
        notificationPanel.backgroundColor = .clear
        notificationPanel.hasShadow = true
        notificationPanel.level = .popUpMenu
        notificationPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        notificationPanel.contentView = background

        // Right below the status item, where the popover used to point from.
        let iconFrame = iconWindow.frame
        let gap: CGFloat = 4
        var origin = NSPoint(x: iconFrame.midX - panelSize.width / 2,
                             y: min(iconFrame.minY, screen.frame.maxY) - panelSize.height - gap)
        origin.x = min(max(origin.x, screen.frame.minX + gap), screen.frame.maxX - panelSize.width - gap)
        notificationPanel.setFrame(NSRect(origin: origin, size: panelSize), display: true)
        notificationPanel.orderFrontRegardless()
    }
}

/// A panel that never becomes key or main, so showing it never moves keyboard focus
/// away from the app the user is currently typing in.
private class NonKeyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

extension String {
    func width(withConstrainedHeight height: CGFloat, font: NSFont) -> CGFloat {
        let constraintRect = CGSize(width: .greatestFiniteMagnitude, height: height)
        let boundingBox = self.boundingRect(with: constraintRect, options: .usesLineFragmentOrigin, attributes: [NSAttributedString.Key.font: font], context: nil)

        return ceil(boundingBox.width)
    }
}

extension NSScreen {
    static var screenWithMouse: NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let screenWithMouse = (screens.first {
            NSMouseInRect(mouseLocation, $0.frame, false)
        })

        return screenWithMouse
    }
    var hasTopNotchDesign: Bool {
        guard #available(macOS 12, *) else { return false }
        return safeAreaInsets.top != 0
    }
}
