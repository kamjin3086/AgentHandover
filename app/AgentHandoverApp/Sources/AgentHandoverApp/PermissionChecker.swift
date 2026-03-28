import Cocoa
import CoreGraphics
import ScreenCaptureKit

/// Checks macOS system permissions required by AgentHandover.
enum PermissionChecker {

    // MARK: - Accessibility

    /// Check if Accessibility permission is granted (needed for window info).
    static func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the user to grant Accessibility permission.
    /// Opens System Settings to the correct pane.
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Screen Recording

    /// Check if Screen Recording permission is granted (needed for screenshots).
    /// Uses CGPreflightScreenCaptureAccess which checks the current state
    /// without triggering the system permission prompt or capturing anything.
    /// The old CGDisplayCreateImage probe triggered the prompt on first call
    /// and returned non-nil on macOS 15+ even without permission.
    static func isScreenRecordingGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Request Screen Recording permission from the main app bundle.
    /// This uses the same capture service the daemon depends on so the
    /// permission is exercised by the exact runtime principal users see.
    @discardableResult
    static func requestScreenRecording() async -> Bool {
        await ScreenCaptureService().requestPermission()
    }

    /// Kick off the full Screen Recording grant flow from the main app.
    ///
    /// We first exercise the permission from the app principal, then only
    /// fall back to opening System Settings if the permission is still absent.
    @MainActor
    @discardableResult
    static func requestScreenRecordingAndOpenSettingsIfNeeded() async -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let granted = await requestScreenRecording()
        if !granted {
            openScreenRecordingSettings()
        }
        return granted
    }

    /// Open System Settings to the Screen Recording privacy pane.
    static func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Composite

    /// Check all required permissions.
    static func allPermissionsGranted() -> Bool {
        isAccessibilityGranted() && isScreenRecordingGranted()
    }
}
