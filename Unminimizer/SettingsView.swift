import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var accessibilityPermissionGranted = AXIsProcessTrusted()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Unminimizer Settings")
                .font(.title)
                .padding(.bottom, 10)

            // Accessibility Permission Section
            GroupBox(label: Text("Permissions").font(.headline)) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: accessibilityPermissionGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(accessibilityPermissionGranted ? .green : .red)

                        Text("Accessibility Access")
                        Spacer()

                        if !accessibilityPermissionGranted {
                            Button("Grant Permission") {
                                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }

                    Text("Required to monitor and restore minimized windows")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(10)
            }

            // Keyboard Shortcut Section
            GroupBox(label: Text("Keyboard Shortcut").font(.headline)) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Unminimize Window:")
                        Spacer()
                        KeyboardShortcutRecorder()
                    }

                    Text("Press the shortcut to unminimize the most recently minimized window")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(10)
            }

            // Behavior Section
            GroupBox(label: Text("Behavior").font(.headline)) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Unminimize from current app only", isOn: $settings.unminimizeCurrentAppOnly)

                    Text(settings.unminimizeCurrentAppOnly
                         ? "Will only unminimize windows from the currently active application"
                         : "Will unminimize windows from any application")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(10)
            }

            // Startup Section
            GroupBox(label: Text("Startup").font(.headline)) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Launch at login", isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { newValue in
                            settings.launchAtLogin = newValue
                            if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                                appDelegate.updateLaunchAtLogin()
                            }
                        }
                    ))

                    Text("Automatically start Unminimizer when you log in")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(10)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 500, height: 400)
        .onAppear {
            // Check permission status when view appears
            accessibilityPermissionGranted = AXIsProcessTrusted()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            // Check permission status when window becomes active
            accessibilityPermissionGranted = AXIsProcessTrusted()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Check permission status when app becomes active (switching from System Settings)
            accessibilityPermissionGranted = AXIsProcessTrusted()
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings.shared)
}
