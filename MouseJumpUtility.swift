import Cocoa
import ApplicationServices
import ServiceManagement
import OSLog

// MARK: - Preferences
private enum PreferenceKey {
    static let showMenuBarIcon = "showMenuBarIcon"
    static let launchAtLogin = "launchAtLogin"
}

// MARK: - Window Information Helper
class WindowHelper {
    static func getActiveWindow() -> (CGPoint, CGSize)? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let frontPID = frontApp.processIdentifier

        for window in windows {
            if let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
               ownerPID == frontPID,
               let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
               let x = bounds["X"], let y = bounds["Y"],
               let width = bounds["Width"], let height = bounds["Height"],
               width > 50, height > 50 {

                let origin = CGPoint(x: x, y: y)
                let size = CGSize(width: width, height: height)
                return (origin, size)
            }
        }

        return nil
    }

    static func moveCursor(to point: CGPoint) {
        CGWarpMouseCursorPosition(point)
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}

// MARK: - Notification Helper
class NotificationHelper {
    private static let logger = Logger(subsystem: "com.fruitjuice088.MouseJumpUtility", category: "MouseJumpUtility")

    static func deliver(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}

// MARK: - Key Combination Handler
class KeyCombinationHandler {
    private var optionPressed = false
    private var optionPressTime: TimeInterval = 0
    private var otherKeyPressed = false
    private let optionOnlyDelay: TimeInterval = 0.3

    func handleKeyEvent(event: CGEvent) -> CGEvent? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let isKeyDown = event.type == .keyDown
        let isFlagsChanged = event.type == .flagsChanged

        let optionKeyPressed = flags.contains(.maskAlternate)

        if isFlagsChanged {
            if optionKeyPressed && !optionPressed {
                optionPressed = true
                optionPressTime = Date().timeIntervalSince1970
                otherKeyPressed = false

                DispatchQueue.main.asyncAfter(deadline: .now() + optionOnlyDelay) { [weak self] in
                    guard let self = self else { return }
                    if self.optionPressed && !self.otherKeyPressed {
                        self.executeOptionOnly()
                    }
                }

            } else if !optionKeyPressed && optionPressed {
                let pressDuration = Date().timeIntervalSince1970 - optionPressTime

                if !otherKeyPressed && pressDuration < optionOnlyDelay {
                    executeOptionOnly()
                }

                optionPressed = false
                otherKeyPressed = false
            }

            return event
        }

        if isKeyDown && optionKeyPressed {
            otherKeyPressed = true
            let handled = handleOptionCombination(keyCode: keyCode)

            if handled {
                return nil
            }
        }

        return event
    }

    private func handleOptionCombination(keyCode: Int64) -> Bool {
        guard let windowInfo = WindowHelper.getActiveWindow() else {
            return false
        }

        let (origin, size) = windowInfo
        let resizeMargin: CGFloat = 5
        let titleBarHeight: CGFloat = 28

        var targetPoint: CGPoint?

        switch keyCode {
        case 13: // option + w
            targetPoint = CGPoint(x: origin.x + resizeMargin, y: origin.y + resizeMargin)

        case 15: // option + r
            targetPoint = CGPoint(x: origin.x + size.width - resizeMargin, y: origin.y + resizeMargin)

        case 14: // option + e
            targetPoint = CGPoint(x: origin.x + size.width / 2, y: origin.y + titleBarHeight / 2)

        case 1: // option + s
            targetPoint = CGPoint(x: origin.x + resizeMargin, y: origin.y + size.height - resizeMargin)

        case 2: // option + d
            targetPoint = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)

        case 3: // option + f
            targetPoint = CGPoint(x: origin.x + size.width - resizeMargin, y: origin.y + size.height - resizeMargin)

        default:
            return false
        }

        if let point = targetPoint {
            WindowHelper.moveCursor(to: point)
            return true
        }

        return false
    }

    private func executeOptionOnly() {
        _ = handleOptionCombination(keyCode: 14)
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private let handler = KeyCombinationHandler()
    private let defaults = UserDefaults.standard
    private var permissionMonitorTimer: Timer?
    private var accessibilityPermissionGranted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerDefaults()
        applyLaunchAtLoginSetting()

        accessibilityPermissionGranted = checkAccessibilityPermission(promptIfNeeded: true)
        updateStatusItem()

        if accessibilityPermissionGranted {
            startEventTap()
        }

        startPermissionMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanupEventTap()
        stopPermissionMonitoring()

        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            PreferenceKey.showMenuBarIcon: true,
            PreferenceKey.launchAtLogin: false
        ])
    }

    @discardableResult
    private func checkAccessibilityPermission(promptIfNeeded: Bool = false) -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        if promptIfNeeded {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }

        NotificationHelper.deliver("Please allow MouseJumpUtility in Accessibility settings.")
        return false
    }

    private func updateStatusItem() {
        let shouldShowIcon = defaults.bool(forKey: PreferenceKey.showMenuBarIcon)

        guard shouldShowIcon else {
            if let statusItem = statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
                self.statusItem = nil
            }
            return
        }

        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }

        statusItem?.button?.title = "⌖"
        statusItem?.button?.font = NSFont.systemFont(ofSize: 13)
        statusItem?.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let launchItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = defaults.bool(forKey: PreferenceKey.launchAtLogin) ? .on : .off
        menu.addItem(launchItem)

        let iconItem = NSMenuItem(
            title: "Show Menu Bar Icon",
            action: #selector(toggleShowMenuBarIcon),
            keyEquivalent: ""
        )
        iconItem.target = self
        iconItem.state = defaults.bool(forKey: PreferenceKey.showMenuBarIcon) ? .on : .off
        menu.addItem(iconItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit MouseJumpUtility",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func toggleLaunchAtLogin() {
        let newValue = !defaults.bool(forKey: PreferenceKey.launchAtLogin)
        defaults.set(newValue, forKey: PreferenceKey.launchAtLogin)
        applyLaunchAtLoginSetting()
        statusItem?.menu = buildMenu()
    }

    @objc private func toggleShowMenuBarIcon() {
        let currentlyShowing = defaults.bool(forKey: PreferenceKey.showMenuBarIcon)
        defaults.set(!currentlyShowing, forKey: PreferenceKey.showMenuBarIcon)
        updateStatusItem()
    }

    private func applyLaunchAtLoginSetting() {
        guard #available(macOS 13.0, *) else { return }

        if defaults.bool(forKey: PreferenceKey.launchAtLogin) {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }

    private func cleanupEventTap() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }

        if let source = eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            eventTapRunLoopSource = nil
        }
    }

    private func startEventTap() {
        guard accessibilityPermissionGranted else {
            return
        }

        cleanupEventTap()

        let eventMask = (1 << CGEventType.keyDown.rawValue) |
                        (1 << CGEventType.keyUp.rawValue) |
                        (1 << CGEventType.flagsChanged.rawValue)

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (_, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }

                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()

                if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
                    appDelegate.handleTapDisabledEvent()
                    return Unmanaged.passUnretained(event)
                }

                let handler = appDelegate.handler

                if let modifiedEvent = handler.handleKeyEvent(event: event) {
                    return Unmanaged.passUnretained(modifiedEvent)
                } else {
                    return nil
                }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NotificationHelper.deliver("Failed to create event tap.")
            NSApplication.shared.terminate(nil)
            return
        }

        self.eventTap = eventTap

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        eventTapRunLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func handleTapDisabledEvent() {
        cleanupEventTap()
        refreshAccessibilityPermission()
    }

    private func startPermissionMonitoring() {
        stopPermissionMonitoring()

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshAccessibilityPermission()
        }

        RunLoop.main.add(timer, forMode: .common)
        permissionMonitorTimer = timer
    }

    private func stopPermissionMonitoring() {
        permissionMonitorTimer?.invalidate()
        permissionMonitorTimer = nil
    }

    private func refreshAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()

        guard trusted != accessibilityPermissionGranted else { return }

        accessibilityPermissionGranted = trusted

        if trusted {
            NotificationHelper.deliver("Accessibility permission restored.")
            startEventTap()
        } else {
            cleanupEventTap()
            NotificationHelper.deliver("Accessibility permission lost. MouseJumpUtility is paused.")
        }
    }
}

// MARK: - Entry Point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
