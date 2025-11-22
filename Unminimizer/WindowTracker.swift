import Cocoa
import ApplicationServices
import Combine

struct MinimizedWindow {
    let windowElement: AXUIElement
    let appBundleIdentifier: String
    let appName: String
    let timestamp: Date
    let windowTitle: String?
}

class WindowTracker: ObservableObject {
    @Published private(set) var minimizedWindows: [MinimizedWindow] = []

    private var observers: [pid_t: AXObserver] = [:]
    private var observedWindows: Set<String> = []
    private var isTracking = false

    func startTracking() {
        guard !isTracking else { return }
        isTracking = true

        print("🔍 WindowTracker: Starting tracking...")

        // Observe running applications
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationLaunched),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationTerminated),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationActivated),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        // Start observing all currently running applications
        for app in NSWorkspace.shared.runningApplications {
            observeApplication(app)
        }
    }

    func stopTracking() {
        guard isTracking else { return }
        isTracking = false

        NSWorkspace.shared.notificationCenter.removeObserver(self)

        // Remove all observers
        for (_, observer) in observers {
            CFRunLoopRemoveSource(
                CFRunLoopGetCurrent(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }
        observers.removeAll()
        minimizedWindows.removeAll()
    }

    @objc private func applicationLaunched(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        print("🚀 App launched: \(app.localizedName ?? "unknown")")
        observeApplication(app)
    }

    @objc private func applicationActivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        // Re-observe to catch any new windows
        observeApplication(app)
    }

    @objc private func applicationTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }

        print("💀 App terminated: \(app.localizedName ?? "unknown")")

        if let bundleID = app.bundleIdentifier {
            minimizedWindows.removeAll { $0.appBundleIdentifier == bundleID }
        }

        if let observer = observers[app.processIdentifier] {
            CFRunLoopRemoveSource(
                CFRunLoopGetCurrent(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
            observers.removeValue(forKey: app.processIdentifier)
        }
    }

    private func observeApplication(_ app: NSRunningApplication) {
        let pid = app.processIdentifier

        // Skip system processes and non-regular applications
        guard app.activationPolicy == .regular else {
            return
        }

        // Create observer if it doesn't exist
        if observers[pid] == nil {
            var observer: AXObserver?
            let result = AXObserverCreate(pid, axObserverCallback, &observer)

            guard result == .success, let observer = observer else {
                if app.localizedName != nil {
                    print("⚠️ Failed to create observer for \(app.localizedName ?? "unknown"): \(result.rawValue)")
                }
                return
            }

            // Add observer to run loop
            CFRunLoopAddSource(
                CFRunLoopGetCurrent(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )

            observers[pid] = observer
        }

        guard let observer = observers[pid] else { return }

        // Store reference to self for the callback
        let context = Unmanaged.passUnretained(self).toOpaque()

        let appElement = AXUIElementCreateApplication(pid)

        // Get all windows for this application
        var windowsValue: AnyObject?
        let windowsResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsValue
        )

        if windowsResult != .success {
            if app.localizedName != nil {
                print("⚠️ Failed to get windows for \(app.localizedName ?? "unknown") - error: \(windowsResult.rawValue)")

                // Check if accessibility is actually enabled
                if !AXIsProcessTrusted() {
                    print("❌ ACCESSIBILITY NOT TRUSTED! Please enable in System Settings and restart the app.")
                }
            }
            return
        }

        guard let windows = windowsValue as? [AXUIElement] else {
            return
        }

        if windows.count > 0 {
            print("👀 Observing \(windows.count) windows for \(app.localizedName ?? "unknown")")
        }

        // Observe each window
        for window in windows {
            let windowHash = getWindowHash(window)

            // Skip if already observing this window
            guard !observedWindows.contains(windowHash) else { continue }

            // Observe window minimized notifications
            let miniResult = AXObserverAddNotification(
                observer,
                window,
                kAXWindowMiniaturizedNotification as CFString,
                context
            )

            // Observe window deminiaturized notifications
            let deminiResult = AXObserverAddNotification(
                observer,
                window,
                kAXWindowDeminiaturizedNotification as CFString,
                context
            )

            if miniResult == .success && deminiResult == .success {
                observedWindows.insert(windowHash)

                // Check if window is already minimized
                var isMinimizedValue: AnyObject?
                let isMinimizedResult = AXUIElementCopyAttributeValue(
                    window,
                    kAXMinimizedAttribute as CFString,
                    &isMinimizedValue
                )

                if isMinimizedResult == .success,
                   let isMinimized = isMinimizedValue as? Bool,
                   isMinimized {
                    // Add to minimized windows
                    handleWindowMinimized(window, pid: app.processIdentifier)
                }
            } else {
                print("⚠️ Failed to observe window in \(app.localizedName ?? "unknown"): mini=\(miniResult.rawValue) demini=\(deminiResult.rawValue)")
            }
        }

        // Also observe the application for new window creation
        AXObserverAddNotification(
            observer,
            appElement,
            kAXCreatedNotification as CFString,
            context
        )
    }

    private func getWindowHash(_ window: AXUIElement) -> String {
        return String(describing: Unmanaged.passUnretained(window).toOpaque())
    }

    fileprivate func handleWindowMinimized(_ windowElement: AXUIElement, pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid),
              let bundleID = app.bundleIdentifier else {
            return
        }

        // Get window title if available
        var titleValue: AnyObject?
        let titleResult = AXUIElementCopyAttributeValue(
            windowElement,
            kAXTitleAttribute as CFString,
            &titleValue
        )
        let windowTitle = titleResult == .success ? (titleValue as? String) : nil

        let minimizedWindow = MinimizedWindow(
            windowElement: windowElement,
            appBundleIdentifier: bundleID,
            appName: app.localizedName ?? bundleID,
            timestamp: Date(),
            windowTitle: windowTitle
        )

        minimizedWindows.append(minimizedWindow)
        print("➖ Window minimized: \(windowTitle ?? "untitled") from \(app.localizedName ?? bundleID). Total: \(minimizedWindows.count)")
    }

    fileprivate func handleWindowUnminimized(_ windowElement: AXUIElement, pid: pid_t) {
        // Remove this window from our tracking list
        let countBefore = minimizedWindows.count
        minimizedWindows.removeAll { window in
            CFEqual(window.windowElement, windowElement)
        }
        let removed = countBefore - minimizedWindows.count
        if removed > 0 {
            print("➕ Window unminimized. Removed \(removed) window(s). Total: \(minimizedWindows.count)")
        }
    }

    fileprivate func handleWindowCreated(_ windowElement: AXUIElement, pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            return
        }
        // When a new window is created, observe it
        print("🆕 New window created for \(app.localizedName ?? "unknown")")
        observeApplication(app)
    }

    func getMostRecentMinimizedWindow(fromActiveAppOnly: Bool = false) -> MinimizedWindow? {
        print("🔍 Getting most recent window. Active app only: \(fromActiveAppOnly). Total minimized: \(minimizedWindows.count)")

        if fromActiveAppOnly {
            guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
                  let bundleID = frontmostApp.bundleIdentifier else {
                print("⚠️ No frontmost app found")
                return nil
            }

            print("🎯 Frontmost app: \(frontmostApp.localizedName ?? bundleID)")

            // Find most recent window from frontmost app
            let filtered = minimizedWindows.filter { $0.appBundleIdentifier == bundleID }
            print("📋 Found \(filtered.count) minimized windows for active app")
            return filtered.max(by: { $0.timestamp < $1.timestamp })
        } else {
            // Return most recent window globally
            let result = minimizedWindows.max(by: { $0.timestamp < $1.timestamp })
            if let window = result {
                print("✅ Found most recent window: \(window.windowTitle ?? "untitled") from \(window.appName)")
            } else {
                print("❌ No minimized windows found")
            }
            return result
        }
    }

    func unminimizeWindow(_ window: MinimizedWindow) -> Bool {
        print("🔓 Attempting to unminimize: \(window.windowTitle ?? "untitled") from \(window.appName)")

        // Set the minimized attribute to false
        let falseValue = false as CFBoolean
        let result = AXUIElementSetAttributeValue(
            window.windowElement,
            kAXMinimizedAttribute as CFString,
            falseValue
        )

        print("📝 AXUIElementSetAttributeValue result: \(result.rawValue)")

        if result == .success {
            // Activate the application
            if let app = NSRunningApplication.runningApplications(
                withBundleIdentifier: window.appBundleIdentifier
            ).first {
                app.activate()
                print("✅ Successfully unminimized and activated app")
            }

            // Remove from our list
            minimizedWindows.removeAll { CFEqual($0.windowElement, window.windowElement) }
            return true
        }

        print("❌ Failed to unminimize window")
        return false
    }
}

// C callback function for AX notifications
private func axObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon = refcon else { return }

    let tracker = Unmanaged<WindowTracker>.fromOpaque(refcon).takeUnretainedValue()

    // Get the process ID from the element
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)

    if notification == kAXWindowMiniaturizedNotification as CFString {
        tracker.handleWindowMinimized(element, pid: pid)
    } else if notification == kAXWindowDeminiaturizedNotification as CFString {
        tracker.handleWindowUnminimized(element, pid: pid)
    } else if notification == kAXCreatedNotification as CFString {
        tracker.handleWindowCreated(element, pid: pid)
    }
}
