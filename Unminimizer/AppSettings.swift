import Foundation
import SwiftUI
import Carbon
import Combine

enum UnminimizeStrategy: String, CaseIterable, Identifiable {
    case activeApp = "Active app only"
    case allApps = "All apps"

    var id: String { rawValue }
}

class AppSettings: ObservableObject {
    @AppStorage("unminimizeStrategy") var unminimizeStrategy: UnminimizeStrategy = .activeApp
    @AppStorage("launchAtLogin") var launchAtLogin = true

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

    static let shared = AppSettings()

    private init() {
        // Load saved values or use defaults
        let savedKeyCode = UserDefaults.standard.integer(forKey: "keyboardShortcutKeyCode")
        self.keyboardShortcutKeyCode = savedKeyCode != 0 ? UInt32(savedKeyCode) : 46 // M key

        let savedModifiers = UserDefaults.standard.integer(forKey: "keyboardShortcutModifiers")
        self.keyboardShortcutModifiers = savedModifiers != 0 ? UInt32(savedModifiers) : UInt32(cmdKey | shiftKey)
    }
}
