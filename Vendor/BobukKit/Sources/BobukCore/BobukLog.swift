// One Logger per category with the app's bundle identifier as subsystem. Use it instead of NSLog.
import Foundation
import OSLog

public enum BobukLog {
    /// `Logger(subsystem: <bundle id or process name>, category: category)`.
    public static func logger(_ category: String, subsystem: String? = nil) -> Logger {
        Logger(subsystem: subsystem ?? Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName,
               category: category)
    }
}
