import Foundation

/// Reads and writes the system appearance (light ↔ dark).
///
/// Reading is native and free (no subprocess); only writing goes through
/// `osascript`, because macOS exposes no public API to change the appearance.
enum AppleScriptManager {

    /// Current appearance, read directly from the global preferences.
    static var isSystemDark: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    /// Toggles the system appearance. Returns `true` on success.
    @discardableResult
    static func setDarkMode(_ enabled: Bool) async -> Bool {
        let script = """
            tell application "System Events"
                tell appearance preferences
                    set dark mode to \(enabled)
                end tell
            end tell
            """
        return await runOsascript(script)
    }

    /// Runs a script via `osascript` on a background queue, bridging
    /// `Process` → `async` with a checked continuation.
    private static func runOsascript(_ source: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", source]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: false)
                    return
                }
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus == 0)
            }
        }
    }
}
