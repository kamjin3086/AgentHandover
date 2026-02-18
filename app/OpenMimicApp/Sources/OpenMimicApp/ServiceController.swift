import Foundation

/// Controls OpenMimic services via launchctl.
final class ServiceController {

    static let daemonLabel = "com.openmimic.daemon"
    static let workerLabel = "com.openmimic.worker"

    private static var launchAgentsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
    }

    // MARK: - Start

    static func startDaemon() {
        launchctl(["load", "-w", plistPath(daemonLabel)])
    }

    static func startWorker() {
        launchctl(["load", "-w", plistPath(workerLabel)])
    }

    static func startAll() {
        startDaemon()
        startWorker()
    }

    // MARK: - Stop

    static func stopDaemon() {
        launchctl(["unload", plistPath(daemonLabel)])
    }

    static func stopWorker() {
        launchctl(["unload", plistPath(workerLabel)])
    }

    static func stopAll() {
        stopDaemon()
        stopWorker()
    }

    // MARK: - Restart

    static func restartDaemon() {
        stopDaemon()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            startDaemon()
        }
    }

    static func restartWorker() {
        stopWorker()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            startWorker()
        }
    }

    static func restartAll() {
        stopAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            startAll()
        }
    }

    // MARK: - Helpers

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
}
