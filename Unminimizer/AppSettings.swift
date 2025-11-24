import Foundation
import SwiftUI
import Carbon
import Combine
import ServiceManagement

enum UnminimizeStrategy: String, CaseIterable, Identifiable {
    case activeApp = "Active app only"
    case allApps = "All apps"

    var id: String { rawValue }
}

class AppSettings: ObservableObject {
    @AppStorage("unminimizeStrategy") var unminimizeStrategy: UnminimizeStrategy = .activeApp
    @AppStorage("lastRunVersion") private var storedVersion: String?

    @Published var launchAtLogin: Bool

    @Published var keyboardShortcutKeyCode: UInt32 {
        didSet {
            UserDefaults.standard.set(Int(keyboardShortcutKeyCode), forKey: "keyboardShortcutKeyCode")
        }
    }

    @Published var keyboardShortcutModifiers: UInt32 {
        didSet {
            UserDefaults.standard.set(Int(keyboardShortcutModifiers), forKey: "keyboardShortcutModifiers")
        }
    }

    /// The current app version from the bundle
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    static let shared = AppSettings()

    private init() {
        // Load saved values or use defaults
        let savedKeyCode = UserDefaults.standard.integer(forKey: "keyboardShortcutKeyCode")
        self.keyboardShortcutKeyCode = savedKeyCode != 0 ? UInt32(savedKeyCode) : 46 // M key

        let savedModifiers = UserDefaults.standard.integer(forKey: "keyboardShortcutModifiers")
        self.keyboardShortcutModifiers = savedModifiers != 0 ? UInt32(savedModifiers) : UInt32(cmdKey | shiftKey)

        // Initialize launch at login from system state
        self.launchAtLogin = SMAppService.mainApp.status == .enabled

        // Store current version
        storedVersion = currentVersion
    }
}
