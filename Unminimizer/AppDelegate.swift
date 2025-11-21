import Cocoa
import SwiftUI
import Carbon
import ServiceManagement

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var windowTracker = WindowTracker()
    var settingsWindow: NSWindow?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

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

        // Setup launch at login
        updateLaunchAtLogin()
    }

    @objc private func handleShortcutChange() {
        updateHotKey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowTracker.stopTracking()
        unregisterHotKey()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            // Use SF Symbol for the icon
            button.image = NSImage(systemSymbolName: "arrow.up.square", accessibilityDescription: "Unminimizer")
        }

        let menu = NSMenu()

        let unminimizeItem = NSMenuItem(
            title: "Unminimize Window",
            action: #selector(unminimizeWindow),
            keyEquivalent: ""
        )
        unminimizeItem.target = self
        menu.addItem(unminimizeItem)

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
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
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
            window.setContentSize(NSSize(width: 500, height: 400))
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
        // First check without prompt
        var trusted = AXIsProcessTrusted()
        print("🔐 Initial accessibility check: \(trusted)")

        if !trusted {
            // Request with prompt option
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            trusted = AXIsProcessTrustedWithOptions(options)
            print("🔐 After prompt request: \(trusted)")

            if !trusted {
                // Show additional alert
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    let alert = NSAlert()
                    alert.messageText = "Accessibility Permission Required"
                    alert.informativeText = "Unminimizer needs accessibility access to monitor and restore minimized windows.\n\nPlease:\n1. Grant permission in the System Settings prompt\n2. Restart Unminimizer after granting permission"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        } else {
            print("✅ Accessibility permissions granted")
        }
    }

    private func registerHotKey() {
        unregisterHotKey()

        let settings = AppSettings.shared
        let keyCode = settings.keyboardShortcutKeyCode
        let modifiers = settings.keyboardShortcutModifiers

        print("⌨️ Registering hotkey: keyCode=\(keyCode), modifiers=\(modifiers)")

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

                print("🎹 Hotkey pressed!")

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

        print("📝 InstallEventHandler result: \(handlerResult)")

        // Register hot key
        let hotKeyResult = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        print("📝 RegisterEventHotKey result: \(hotKeyResult)")
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
        print("🚀 performUnminimize called")

        let settings = AppSettings.shared
        let currentAppOnly = settings.unminimizeCurrentAppOnly

        print("⚙️ Settings: currentAppOnly=\(currentAppOnly)")

        guard let window = windowTracker.getMostRecentMinimizedWindow(fromCurrentAppOnly: currentAppOnly) else {
            // No minimized windows available
            print("⚠️ No window found, beeping")
            NSSound.beep()
            return
        }

        let success = windowTracker.unminimizeWindow(window)
        if !success {
            print("❌ Unminimize failed, beeping")
            NSSound.beep()
        }
    }

    func updateLaunchAtLogin() {
        let settings = AppSettings.shared

        do {
            if settings.launchAtLogin {
                if SMAppService.mainApp.status == .notRegistered {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            print("Failed to update launch at login: \(error)")
        }
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Return to accessory app (menu bar only, no Dock icon)
        NSApp.setActivationPolicy(.accessory)
        settingsWindow = nil
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
