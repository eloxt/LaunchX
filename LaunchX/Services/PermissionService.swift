import AVFoundation
import Cocoa
import Combine
import SwiftUI

class PermissionService: ObservableObject {
    static let shared = PermissionService()

    @Published var isAccessibilityGranted: Bool = false
    @Published var isScreenRecordingGranted: Bool = false
    @Published var isFullDiskAccessGranted: Bool = false
    @Published var isAutomationGranted: Bool = false

    private init() {
        checkAllPermissions()
    }

    func checkAllPermissions() {
        checkAccessibility()
        checkScreenRecording()
        checkFullDiskAccess()
        checkAutomation()
    }

    // MARK: - Accessibility

    func checkAccessibility() {
        let trusted = AXIsProcessTrusted()
        DispatchQueue.main.async {
            self.isAccessibilityGranted = trusted
        }
    }

    func requestAccessibility() {
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        let trusted = AXIsProcessTrustedWithOptions(options)
        if trusted {
            DispatchQueue.main.async {
                self.isAccessibilityGranted = true
            }
        } else {
            // Open System Settings if not trusted (and prompt didn't help/already shown)
            openSystemSettings(target: "Privacy_Accessibility")
        }
    }

    // MARK: - Screen Recording

    func checkScreenRecording() {
        if #available(macOS 11.0, *) {
            let granted = CGPreflightScreenCaptureAccess()
            DispatchQueue.main.async {
                self.isScreenRecordingGranted = granted
            }
        } else {
            DispatchQueue.main.async {
                self.isScreenRecordingGranted = true
            }
        }
    }

    func requestScreenRecording() {
        // CGRequestScreenCaptureAccess() doesn't exist as a direct prompt API like Accessibility.
        // We can guide the user to the settings.
        openSystemSettings(target: "Privacy_ScreenCapture")
    }

    // MARK: - Full Disk Access

    func checkFullDiskAccess() {
        // There is no public API to check Full Disk Access directly.
        // The standard workaround is to attempt to read a file that requires FDA.
        // Using user's home directory Library/Safari is a common check, or TimeMachine preferences.

        let status: Bool

        // Method 1: Try to read user's Safari bookmarks (Sandboxed apps can't do this anyway without entitlement,
        // but non-sandboxed tools like LaunchX typically rely on this check)
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let safariPath = homeDir.appendingPathComponent("Library/Safari/CloudTabs.db")

        if FileManager.default.isReadableFile(atPath: safariPath.path) {
            status = true
        } else {
            // Method 2: Try checking TimeMachine plist in global library
            let tmPath = "/Library/Preferences/com.apple.TimeMachine.plist"
            if FileManager.default.isReadableFile(atPath: tmPath) {
                status = true
            } else {
                // Method 3: Try reading contents of a protected directory
                // /Library/Application Support/com.apple.TCC
                do {
                    let _ = try FileManager.default.contentsOfDirectory(
                        atPath: "/Library/Application Support/com.apple.TCC")
                    status = true
                } catch {
                    status = false
                }
            }
        }

        DispatchQueue.main.async {
            self.isFullDiskAccessGranted = status
        }
    }

    func requestFullDiskAccess() {
        openSystemSettings(target: "Privacy_AllFiles")
    }

    // MARK: - Automation

    func checkAutomation() {
        DispatchQueue.global(qos: .background).async {
            // Check if we can control Finder. This may trigger a system prompt.
            let scriptSource = "tell application \"Finder\" to get name"
            var error: NSDictionary?
            if let script = NSAppleScript(source: scriptSource) {
                script.executeAndReturnError(&error)
            }

            let granted = (error == nil)
            DispatchQueue.main.async {
                self.isAutomationGranted = granted
            }
        }
    }

    func requestAutomation() {
        DispatchQueue.global(qos: .userInitiated).async {
            let scriptSource = "tell application \"Finder\" to activate"
            var error: NSDictionary?
            if let script = NSAppleScript(source: scriptSource) {
                script.executeAndReturnError(&error)
            }

            DispatchQueue.main.async {
                if error == nil {
                    self.isAutomationGranted = true
                } else {
                    self.isAutomationGranted = false
                    self.openSystemSettings(target: "Privacy_Automation")
                }
            }
        }
    }

    // MARK: - Helper

    private func openSystemSettings(target: String) {
        // Construct URL for Security & Privacy pane
        // Note: URL schemes vary slightly by macOS version, but this is the standard approach.
        let urlString = "x-apple.systempreferences:com.apple.preference.security?\(target)"

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
