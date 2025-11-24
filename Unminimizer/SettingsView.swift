import SwiftUI
import ServiceManagement
import Combine
import Carbon

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var accessibilityPermissionGranted = AXIsProcessTrusted()
    @State private var timerCancellable: AnyCancellable?
    @State private var escapeMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Accessibility Permission Section
            GroupBox(label: Text("Permissions").font(.headline)) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: accessibilityPermissionGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(accessibilityPermissionGranted ? .green : .red)

                            Text("Accessibility Access")
                        }

                        Text("Required to track and restore minimized windows")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button("Grant Permission") {
                        // Request accessibility permission with system dialog
                        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                        _ = AXIsProcessTrustedWithOptions(options)
                    }
                    .opacity(accessibilityPermissionGranted ? 0 : 1)
                    .disabled(accessibilityPermissionGranted)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
            }

            // Preferences Section
            GroupBox(label: Text("Preferences").font(.headline)) {
                VStack(alignment: .leading, spacing: 0) {
                    // Launch at login
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Launch at login", isOn: $settings.launchAtLogin)
                                .toggleStyle(.checkbox)
                                .onChange(of: settings.launchAtLogin) { oldValue, newValue in
                                    print("🔧 Launch at login changed to: \(newValue)")
                                    NotificationCenter.default.post(name: .launchAtLoginDidChange, object: nil)
                                }

                            Text("Automatically start Unminimizer when you log in")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .padding(.bottom, 12)

                    Divider()

                    // Unminimize shortcut
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Unminimize shortcut")

                            Text("Press the shortcut to unminimize the most recently minimized window")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        KeyboardShortcutRecorder()
                            .frame(width: 150, height: 28)
                    }
                    .padding(.vertical, 12)

                    Divider()

                    // Unminimize from
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Unminimize windows from")

                            Text(settings.unminimizeStrategy == .activeApp
                                 ? "Only unminimize windows from the active application"
                                 : "Unminimize windows from any application")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Picker("", selection: $settings.unminimizeStrategy) {
                            ForEach(UnminimizeStrategy.allCases) { strategy in
                                Text(strategy.rawValue).tag(strategy)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                    .padding(.top, 12)
                }
                .padding(8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 32)
        .frame(width: 590)
        .contentShape(Rectangle())
        .onTapGesture {
            // Clear focus when clicking on background
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        .onAppear {
            // Check permission status when view appears
            accessibilityPermissionGranted = AXIsProcessTrusted()
            syncLaunchAtLoginState()

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
            syncLaunchAtLoginState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            // Window lost focus - start polling (user might be in System Settings)
            startTimer()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Check permission status when app becomes active (switching from System Settings)
            accessibilityPermissionGranted = AXIsProcessTrusted()
            syncLaunchAtLoginState()
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

    private func syncLaunchAtLoginState() {
        let status = SMAppService.mainApp.status
        let isEnabled = status == .enabled
        if settings.launchAtLogin != isEnabled {
            print("🔄 Syncing launch at login: \(settings.launchAtLogin) -> \(isEnabled)")
            settings.launchAtLogin = isEnabled
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings.shared)
}
