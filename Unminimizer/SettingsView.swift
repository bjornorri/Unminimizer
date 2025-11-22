import SwiftUI
import ServiceManagement
import Combine

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var accessibilityPermissionGranted = AXIsProcessTrusted()
    @State private var timerCancellable: AnyCancellable?
    @State private var escapeMonitor: Any?

    enum UnminimizeScope: String, CaseIterable, Identifiable {
        case activeApp = "Active app only"
        case allApps = "All apps"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Accessibility Permission Section
            GroupBox(label: Text("Permissions").font(.headline)) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center) {
                        Image(systemName: accessibilityPermissionGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(accessibilityPermissionGranted ? .green : .red)

                        Text("Accessibility Access")
                        Spacer()

                        Button("Grant Permission") {
                            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                            NSWorkspace.shared.open(url)
                        }
                        .opacity(accessibilityPermissionGranted ? 0 : 1)
                        .disabled(accessibilityPermissionGranted)
                    }
                    .frame(height: 20)

                    Text("Required to monitor and restore minimized windows")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(10)
            }

            // Preferences Section
            GroupBox(label: Text("Preferences").font(.headline)) {
                VStack(alignment: .leading, spacing: 15) {
                    // Launch at login
                    VStack(alignment: .leading, spacing: 5) {
                        Toggle("Launch at login", isOn: Binding(
                            get: { settings.launchAtLogin },
                            set: { newValue in
                                settings.launchAtLogin = newValue
                                if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                                    appDelegate.updateLaunchAtLogin()
                                }
                            }
                        ))
                        .toggleStyle(.checkbox)

                        Text("Automatically start Unminimizer when you log in")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 18)
                    }

                    Divider()

                    // Unminimize shortcut
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("Unminimize shortcut")
                            Spacer()
                            KeyboardShortcutRecorder()
                        }

                        Text("Press the shortcut to unminimize the most recently minimized window")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Unminimize from
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .top) {
                            Text("Unminimize windows from")
                            Spacer()
                            Picker("", selection: Binding(
                                get: { settings.unminimizeActiveAppOnly ? UnminimizeScope.activeApp : UnminimizeScope.allApps },
                                set: { settings.unminimizeActiveAppOnly = ($0 == .activeApp) }
                            )) {
                                ForEach(UnminimizeScope.allCases) { scope in
                                    Text(scope.rawValue).tag(scope)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 150)
                        }

                        HStack {
                            Text(settings.unminimizeActiveAppOnly
                                 ? "Only unminimize windows from the active application"
                                 : "Unminimize windows from any application")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Color.clear.frame(width: 150)
                        }
                    }
                }
                .padding(10)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 550, height: 400)
        .contentShape(Rectangle())
        .onTapGesture {
            // Clear focus when clicking on background
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        .onAppear {
            // Check permission status when view appears
            accessibilityPermissionGranted = AXIsProcessTrusted()

            // Add escape key handler
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 { // Escape key
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    return nil // Consume the event
                }
                return event
            }
        }
        .onDisappear {
            // Stop timer when view disappears
            stopTimer()

            // Remove escape key monitor
            if let monitor = escapeMonitor {
                NSEvent.removeMonitor(monitor)
                escapeMonitor = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            // Window became frontmost - check permission and stop polling
            stopTimer()
            accessibilityPermissionGranted = AXIsProcessTrusted()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            // Window lost focus - start polling (user might be in System Settings)
            startTimer()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Check permission status when app becomes active (switching from System Settings)
            accessibilityPermissionGranted = AXIsProcessTrusted()
        }
    }

    private func startTimer() {
        // Only start if not already running
        guard timerCancellable == nil else { return }

        timerCancellable = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                accessibilityPermissionGranted = AXIsProcessTrusted()
            }
    }

    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings.shared)
}
