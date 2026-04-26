import AppKit
import Foundation

enum AppRelauncher {
    /// Launches a fresh copy of the running app and terminates the current process.
    /// Spawns a tiny detached shell that waits for this PID to exit before re-opening
    /// the bundle, so macOS doesn't reuse the existing instance.
    ///
    /// PID and bundle path are passed as `argv` (`$1`, `$2`) instead of being
    /// interpolated into the script body, so paths with quotes or spaces are safe.
    static func relaunch() {
        let bundleURL = Bundle.main.bundleURL
        let pid = String(ProcessInfo.processInfo.processIdentifier)

        let script = #"""
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        /usr/bin/open "$2"
        """#

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script, "relaunch", pid, bundleURL.path]

        do {
            try task.run()
        } catch {
            NSLog("AppRelauncher: failed to spawn relaunch task: \(error.localizedDescription)")
            return
        }

        NSApp.terminate(nil)
    }
}
