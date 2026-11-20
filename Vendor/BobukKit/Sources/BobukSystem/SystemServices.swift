// Small system services every menu-bar app needs: launch at login, the Accessibility permission
// and making an accessory app frontmost. Use these instead of calling the frameworks directly.
import AppKit
import ApplicationServices
import ServiceManagement

@MainActor
public enum LoginItem {
    public static var status: SMAppService.Status { SMAppService.mainApp.status }
    public static var isEnabled: Bool { status == .enabled }
    /// The user must allow the item in System Settings › General › Login Items.
    public static var needsApproval: Bool { status == .requiresApproval }

    /// Registers or unregisters the app; opens Login Items settings when macOS asks for approval.
    public static func set(_ enabled: Bool, openSettingsIfNeeded: Bool = true) throws {
        guard enabled != isEnabled else { return }
        if enabled {
            try SMAppService.mainApp.register()
            if openSettingsIfNeeded && needsApproval { SMAppService.openSystemSettingsLoginItems() }
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// `set` with the error as a short message for the UI, or nil on success.
    public static func setReportingError(_ enabled: Bool, openSettingsIfNeeded: Bool = true) -> String? {
        do {
            try set(enabled, openSettingsIfNeeded: openSettingsIfNeeded)
            return nil
        } catch {
            return "Launch at login: \(error.localizedDescription)"
        }
    }
}

public enum AccessibilityPermission {
    /// True when the app may read other apps' UI and post events (pasting into the front app).
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt once; returns the current state.
    @discardableResult
    public static func requestIfNeeded() -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    @MainActor public static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

@MainActor
public enum AppActivation {
    /// Brings the app (usually an `LSUIElement` accessory) to the front before showing a window.
    /// Uses `NSApp.activate()`, never the deprecated `activate(ignoringOtherApps:)`.
    public static func activate() { NSApp.activate() }

    /// `.accessory`: no Dock icon and no menu bar while a window is open.
    public static func becomeAccessory() { NSApp.setActivationPolicy(.accessory) }
}
