import AppKit

@main
@MainActor
struct HAScSApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Keep the delegate alive for the entire AppKit run loop.
        withExtendedLifetime(delegate) { app.run() }
    }
}
