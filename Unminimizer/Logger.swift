import Foundation

/// Debug logging utility that only prints in DEBUG builds
enum Logger {
    /// Log a debug message. Only outputs in DEBUG builds.
    /// - Parameter message: The message to log
    static func debug(_ message: String) {
        #if DEBUG
        print(message)
        #endif
    }
}
