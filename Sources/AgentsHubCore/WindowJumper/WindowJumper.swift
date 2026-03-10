#if canImport(AppKit)
import AppKit
import ApplicationServices

public final class WindowJumper {
    public init() {}

    /// Attempt to focus the window for a given session
    public func jumpTo(session: Session) -> Bool {
        guard let appName = session.app else { return false }

        // Find the running application
        let apps = NSWorkspace.shared.runningApplications
        let app = apps.first { runningApp in
            let name = runningApp.localizedName?.lowercased() ?? ""
            return name.contains(appName) ||
                   ProcessScanner.appNameMap.values.contains(where: { $0 == appName && name.contains($0) })
        }

        // Fallback: match by PID's parent app
        let targetApp = app ?? findAppByPid(session.pid)

        guard let targetApp else { return false }

        // Activate the app
        targetApp.activate()

        // Try to raise the specific window via Accessibility API
        if let pid = session.pid {
            raiseWindowForPid(pid, in: targetApp)
        }

        return true
    }

    private func findAppByPid(_ pid: Int?) -> NSRunningApplication? {
        guard let pid else { return nil }

        // Walk up the process tree to find an app
        var currentPid = pid
        for _ in 0..<10 { // max depth
            if let app = NSRunningApplication(processIdentifier: pid_t(currentPid)),
               app.activationPolicy == .regular {
                return app
            }
            // Get parent PID
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.size
            var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, Int32(currentPid)]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { break }
            let ppid = Int(info.kp_eproc.e_ppid)
            if ppid <= 1 { break }
            currentPid = ppid
        }
        return nil
    }

    private func raiseWindowForPid(_ pid: Int, in app: NSRunningApplication) {
        let appRef = AXUIElementCreateApplication(app.processIdentifier)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { return }

        // Raise the first window (best effort)
        if let window = windows.first {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, true as CFTypeRef)
        }
    }
}
#endif
