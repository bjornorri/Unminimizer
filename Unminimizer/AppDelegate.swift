import Cocoa
import SwiftUI
import Carbon
import ServiceManagement

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var windowTracker = WindowTracker()
    var settingsWindow: NSWindow?
    var unminimizeMenuItem: NSMenuItem?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var cmdQMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create menu bar item
        setupMenuBar()

        // Check accessibility permissions
        checkAccessibilityPermissions()

        // Start window tracking
        windowTracker.startTracking()

        // Register keyboard shortcut
        registerHotKey()

        // Listen for shortcut changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShortcutChange),
            name: .shortcutDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShortcutRecordingStarted),
            name: .shortcutRecordingStarted,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShortcutRecordingStopped),
            name: .shortcutRecordingStopped,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLaunchAtLoginChange),
            name: .launchAtLoginDidChange,
            object: nil
        )


        // Setup Cmd+Q handler
        setupCmdQHandler()
    }

    @objc private func handleShortcutChange() {
        updateHotKey()
        updateUnminimizeMenuItemShortcut()
    }

    @objc private func handleShortcutRecordingStarted() {
        unregisterHotKey()
    }

    @objc private func handleShortcutRecordingStopped() {
        registerHotKey()
    }

    @objc private func handleLaunchAtLoginChange() {
        Logger.debug("📢 Received launch at login change notification")
        updateLaunchAtLogin()
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowTracker.stopTracking()
        unregisterHotKey()
        if let monitor = cmdQMonitor {
            NSEvent.removeMonitor(monitor)
            cmdQMonitor = nil
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            // Use SF Symbol for the icon
            button.image = NSImage(systemSymbolName: "arrow.up.square", accessibilityDescription: "Unminimizer")
        }

        let menu = NSMenu()
        menu.delegate = self

        let unminimizeItem = NSMenuItem(
            title: "Unminimize Window",
            action: #selector(unminimizeWindow),
            keyEquivalent: ""
        )
        unminimizeItem.target = self
        menu.addItem(unminimizeItem)

        // Store reference and update with current shortcut
        self.unminimizeMenuItem = unminimizeItem
        updateUnminimizeMenuItemShortcut()

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit Unminimizer",
            action: #selector(quitApp),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    private func setupCmdQHandler() {
        cmdQMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            // Check if this is Cmd+Q
            if event.modifierFlags.contains(.command) && event.keyCode == 12 { // 12 is 'q'
                // Check if settings window is open and visible
                if let settingsWindow = self.settingsWindow, settingsWindow.isVisible {
                    // Close the settings window instead of quitting
                    settingsWindow.close()
                    return nil // Consume the event
                }
            }

            return event // Let the event through
        }
    }

    @objc private func unminimizeWindow() {
        performUnminimize()
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView()
                .environmentObject(AppSettings.shared)

            let hostingController = NSHostingController(rootView: settingsView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Unminimizer Settings"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 550, height: 420))
            window.delegate = self
            window.center()
            settingsWindow = window
        }

        // Become a regular app (appear in Dock and app switcher)
        NSApp.setActivationPolicy(.regular)

        DispatchQueue.main.async { [weak self] in
            NSApp.activate()
            DispatchQueue.main.async {
                self?.settingsWindow?.makeKeyAndOrderFront(nil)
            }
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func checkAccessibilityPermissions() {
        // Check without prompt
        let trusted = AXIsProcessTrusted()
        Logger.debug("🔐 Accessibility check: \(trusted)")

        if !trusted {
            // Open settings window to guide user to grant permission
            DispatchQueue.main.async {
                self.showSettings()
            }
        } else {
            Logger.debug("✅ Accessibility permissions granted")
        }
    }

    private func registerHotKey() {
        unregisterHotKey()

        let settings = AppSettings.shared
        let keyCode = settings.keyboardShortcutKeyCode
        let modifiers = settings.keyboardShortcutModifiers

        Logger.debug("⌨️ Registering hotkey: keyCode=\(keyCode), modifiers=\(modifiers)")

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType("UNMN".fourCharCodeValue)
        hotKeyID.id = 1

        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)

        // Install event handler
        let handlerResult = InstallEventHandler(
            GetApplicationEventTarget(),
            { (nextHandler, theEvent, userData) -> OSStatus in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()

                Logger.debug("🎹 Hotkey pressed!")

                Task { @MainActor in
                    appDelegate.performUnminimize()
                }

                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        Logger.debug("📝 InstallEventHandler result: \(handlerResult)")

        // Register hot key
        let hotKeyResult = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        Logger.debug("📝 RegisterEventHotKey result: \(hotKeyResult)")
    }

    private func unregisterHotKey() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    func updateHotKey() {
        registerHotKey()
    }

    private func performUnminimize() {
        Logger.debug("🚀 performUnminimize called")

        let settings = AppSettings.shared
        let activeAppOnly = settings.unminimizeStrategy == .activeApp

        Logger.debug("⚙️ Settings: strategy=\(settings.unminimizeStrategy), activeAppOnly=\(activeAppOnly)")

        guard let window = windowTracker.getMostRecentMinimizedWindow(fromActiveAppOnly: activeAppOnly) else {
            // No minimized windows available
            Logger.debug("⚠️ No window found, beeping")
            NSSound.beep()
            return
        }

        let success = windowTracker.unminimizeWindow(window)
        if !success {
            Logger.debug("❌ Unminimize failed, beeping")
            NSSound.beep()
        }
    }

    func updateLaunchAtLogin() {
        let settings = AppSettings.shared
        let status = SMAppService.mainApp.status

        Logger.debug("🚀 Launch at login - Current status: \(status.rawValue), Desired: \(settings.launchAtLogin)")

        do {
            if settings.launchAtLogin {
                // Try to register if not already enabled
                if status != .enabled {
                    Logger.debug("📝 Registering app for launch at login (current status: \(status.rawValue))...")
                    try SMAppService.mainApp.register()
                    let newStatus = SMAppService.mainApp.status
                    Logger.debug("✅ Registration attempted - New status: \(newStatus.rawValue)")

                    if newStatus == .requiresApproval {
                        Logger.debug("⚠️ User approval required in System Settings > General > Login Items")
                    }
                } else {
                    Logger.debug("ℹ️ Already enabled")
                }
            } else {
                // Try to unregister if currently enabled
                if status == .enabled {
                    Logger.debug("📝 Unregistering app from launch at login...")
                    try SMAppService.mainApp.unregister()
                    Logger.debug("✅ Successfully unregistered from launch at login")
                } else {
                    Logger.debug("ℹ️ Already unregistered (status: \(status.rawValue))")
                }
            }
        } catch {
            Logger.debug("❌ Failed to update launch at login: \(error)")
        }
    }

    private func updateUnminimizeMenuItemShortcut() {
        guard let menuItem = unminimizeMenuItem else { return }

        let settings = AppSettings.shared
        let keyCode = settings.keyboardShortcutKeyCode
        let modifiers = settings.keyboardShortcutModifiers

        // Convert key code to character
        if let keyEquivalent = keyCodeToString(keyCode) {
            menuItem.keyEquivalent = keyEquivalent
            menuItem.keyEquivalentModifierMask = carbonModifiersToNSEventModifierFlags(modifiers)
        }
    }

    private func keyCodeToString(_ keyCode: UInt32) -> String? {
        // Map common key codes to their string equivalents
        // These are the most common keys used for shortcuts
        let keyCodeMap: [UInt32: String] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
            8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
            16: "y", 17: "t", 31: "o", 32: "u", 34: "i", 35: "p",
            37: "l", 38: "j", 40: "k", 45: "n", 46: "m",
            // Function keys
            122: String(UnicodeScalar(NSF1FunctionKey)!),
            120: String(UnicodeScalar(NSF2FunctionKey)!),
            99: String(UnicodeScalar(NSF3FunctionKey)!),
            118: String(UnicodeScalar(NSF4FunctionKey)!),
            96: String(UnicodeScalar(NSF5FunctionKey)!),
            97: String(UnicodeScalar(NSF6FunctionKey)!),
            98: String(UnicodeScalar(NSF7FunctionKey)!),
            100: String(UnicodeScalar(NSF8FunctionKey)!),
            101: String(UnicodeScalar(NSF9FunctionKey)!),
            109: String(UnicodeScalar(NSF10FunctionKey)!),
            103: String(UnicodeScalar(NSF11FunctionKey)!),
            111: String(UnicodeScalar(NSF12FunctionKey)!)
        ]

        return keyCodeMap[keyCode]
    }

    private func carbonModifiersToNSEventModifierFlags(_ carbonModifiers: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []

        if carbonModifiers & UInt32(cmdKey) != 0 {
            flags.insert(.command)
        }
        if carbonModifiers & UInt32(shiftKey) != 0 {
            flags.insert(.shift)
        }
        if carbonModifiers & UInt32(optionKey) != 0 {
            flags.insert(.option)
        }
        if carbonModifiers & UInt32(controlKey) != 0 {
            flags.insert(.control)
        }

        return flags
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Return to accessory app (menu bar only, no Dock icon)
        NSApp.setActivationPolicy(.accessory)
        settingsWindow = nil
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        // Force menu item validation
        menu.update()
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem === unminimizeMenuItem {
            let settings = AppSettings.shared
            let activeAppOnly = settings.unminimizeStrategy == .activeApp
            let hasWindow = windowTracker.getMostRecentMinimizedWindow(fromActiveAppOnly: activeAppOnly) != nil
            Logger.debug("🔄 Validating menu item - hasWindow: \(hasWindow)")
            return hasWindow
        }
        return true
    }
}

// Helper extension to convert string to FourCharCode
extension String {
    var fourCharCodeValue: Int {
        var result: Int = 0
        if let data = self.data(using: .macOSRoman) {
            data.withUnsafeBytes { ptr in
                for i in 0..<min(4, data.count) {
                    result = result << 8 + Int(ptr[i])
                }
            }
        }
        return result
    }
}
