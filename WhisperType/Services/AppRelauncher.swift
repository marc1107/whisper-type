import AppKit
import Foundation

enum AppRelauncher {
    /// Launches a fresh copy of the running app and terminates the current process.
    /// Spawns a tiny detached shell that waits for this PID to exit before re-opening
    /// the bundle, so macOS doesn't reuse the existing instance.
    static func relaunch() {
        let bundleURL = Bundle.main.bundleURL
        let pid = ProcessInfo.processInfo.processIdentifier

        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = [
            "-c",
            "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"\(bundleURL.path)\""
        ]
        do {
            try task.run()
        } catch {
            NSLog("AppRelauncher: failed to spawn relaunch task: \(error.localizedDescription)")
            return
        }

        NSApp.terminate(nil)
    }
}
