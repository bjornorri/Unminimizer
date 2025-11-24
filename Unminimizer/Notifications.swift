import Foundation

extension Notification.Name {
    // Keyboard shortcut notifications
    static let shortcutDidChange = Notification.Name("shortcutDidChange")
    static let shortcutRecordingStarted = Notification.Name("shortcutRecordingStarted")
    static let shortcutRecordingStopped = Notification.Name("shortcutRecordingStopped")

    // Launch at login notifications
    static let launchAtLoginDidChange = Notification.Name("launchAtLoginDidChange")
}
