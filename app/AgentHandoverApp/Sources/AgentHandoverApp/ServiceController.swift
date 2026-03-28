import Foundation
import AppKit

/// Controls AgentHandover services.
///
/// **Daemon**: Launched as an app bundle via `open` / `NSWorkspace`.
/// This keeps the helper in a normal user-session app context on Tahoe,
/// which is more reliable for Accessibility and background lifecycle.
///
/// **Worker**: Managed via launchd (no TCC requirements).
final class ServiceController {

    static let workerLabel = "com.agenthandover.worker"

    /// Path to the daemon app bundle inside the main app.
    static var daemonAppURL: URL {
        let mainApp = Bundle.main.bundleURL
        return mainApp
            .appendingPathComponent("Contents/Helpers/AgentHandoverDaemon.app")
    }

    /// Path to the daemon executable (for PID checking).
    private static var daemonExecPath: String {
        daemonAppURL
            .appendingPathComponent("Contents/MacOS/agenthandover-daemon").path
    }

    private static var uid: uid_t { getuid() }
    private static var guiDomain: String { "gui/\(uid)" }

    private static var launchAgentsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
    }

    // MARK: - Daemon (app-launched)

    /// Start daemon as an app bundle. Returns true if process is running.
    @discardableResult
    static func startDaemon() -> Bool {
        // Check if already running
        if isDaemonRunning() { return true }

        // Launch as an app bundle so the helper runs in a normal
        // user-session context instead of as a raw path-executed binary.
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false  // background, no dock icon
        config.addsToRecentItems = false

        let semaphore = DispatchSemaphore(value: 0)
        var launched = false

        NSWorkspace.shared.openApplication(
            at: daemonAppURL,
            configuration: config
        ) { app, error in
            launched = error == nil
            semaphore.signal()
        }

        // Wait up to 5 seconds for launch
        _ = semaphore.wait(timeout: .now() + 5.0)

        // Give daemon time to initialize
        if launched {
            Thread.sleep(forTimeInterval: 0.5)
        }
        return launched || isDaemonRunning()
    }

    /// Stop daemon by sending SIGTERM to its process.
    static func stopDaemon() {
        guard let pid = daemonPid() else { return }
        kill(pid, SIGTERM)
    }

    /// Check if the daemon process is running.
    static func isDaemonRunning() -> Bool {
        if let pid = daemonPid() {
            return kill(pid, 0) == 0
        }
        // Fallback: check by process name
        let result = shell("/bin/ps", args: ["-ax", "-o", "pid,comm"])
        return result.contains("agenthandover-daemon")
    }

    /// Read the daemon's PID from its PID file.
    private static func daemonPid() -> Int32? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let pidPath = home.appendingPathComponent(
            "Library/Application Support/agenthandover/daemon.pid")
        guard let content = try? String(contentsOf: pidPath, encoding: .utf8),
              let pid = Int32(content.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 0 else { return nil }
        return pid
    }

    /// Block until the daemon process exits (up to timeout).
    static func waitForDaemonExit(timeoutSeconds: Int = 5) {
        let iterations = timeoutSeconds * 5
        for _ in 0..<iterations {
            if !isDaemonRunning() { return }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    // MARK: - Worker (launchd-managed)

    @discardableResult
    static func startWorker() -> Bool {
        bootstrapIfNeeded(label: workerLabel)
        kickstart(label: workerLabel)
        Thread.sleep(forTimeInterval: 0.5)
        return isJobRunning(label: workerLabel)
    }

    static func stopWorker() {
        bootout(label: workerLabel)
    }

    // MARK: - Combined

    @discardableResult
    static func startAll() -> Bool {
        let d = startDaemon()
        let w = startWorker()
        return d && w
    }

    static func stopAll() {
        stopDaemon()
        stopWorker()
    }

    static func restartDaemon() {
        stopDaemon()
        waitForDaemonExit(timeoutSeconds: 3)
        startDaemon()
    }

    static func restartWorker() {
        stopWorker()
        Thread.sleep(forTimeInterval: 0.5)
        startWorker()
    }

    // MARK: - Launchd (worker only)

    private static func bootstrapIfNeeded(label: String) {
        launchctl(["bootstrap", guiDomain, plistPath(label)])
    }

    @discardableResult
    private static func kickstart(label: String) -> Bool {
        let result = launchctl(["kickstart", "\(guiDomain)/\(label)"])
        return result.exitCode == 0
    }

    private static func bootout(label: String) {
        launchctl(["bootout", "\(guiDomain)/\(label)"])
    }

    static func isJobRunning(label: String) -> Bool {
        let result = launchctl(["print", "\(guiDomain)/\(label)"])
        if result.exitCode != 0 { return false }
        let lines = result.output.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("pid =") || trimmed.hasPrefix("pid=") {
                let parts = trimmed.components(separatedBy: "=")
                if let pidStr = parts.last?.trimmingCharacters(in: .whitespaces),
                   let pid = Int(pidStr), pid > 0 {
                    return true
                }
            }
        }
        return false
    }

    static func isServiceHealthy(label: String) -> Bool {
        guard isJobRunning(label: label) else { return false }

        let statusFileName: String
        switch label {
        case workerLabel:
            statusFileName = "worker-status.json"
        default:
            return true
        }

        let statusDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/agenthandover")
        let statusFile = statusDir.appendingPathComponent(statusFileName)

        guard let data = try? Data(contentsOf: statusFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let heartbeatString = json["heartbeat"] as? String else {
            return true
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var heartbeatDate = formatter.date(from: heartbeatString)
        if heartbeatDate == nil {
            formatter.formatOptions = [.withInternetDateTime]
            heartbeatDate = formatter.date(from: heartbeatString)
        }

        guard let date = heartbeatDate else { return true }
        return Date().timeIntervalSince(date) <= 30
    }

    private static func plistPath(_ label: String) -> String {
        launchAgentsDir.appendingPathComponent("\(label).plist").path
    }

    @discardableResult
    private static func launchctl(_ args: [String]) -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return (process.terminationStatus, output)
        } catch {
            return (-1, "Failed to run launchctl: \(error)")
        }
    }

    private static func shell(_ path: String, args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
