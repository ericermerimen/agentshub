#if canImport(AppKit)
import AppKit
import ApplicationServices

public final class WindowJumper {
    public init() {}

    /// Bundle identifiers for common terminal apps
    private static let terminalBundleIds: [String] = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty",
        "io.alacritty",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
    ]

    /// Editor app names -- use `open -a` to focus correct window by folder
    private static let editorAppNames: Set<String> = [
        "vscode", "cursor", "windsurf", "trae", "zed", "sublime",
        "nova", "emacs", "intellij", "webstorm", "pycharm", "goland",
        "clion", "rider", "phpstorm", "rubymine", "datagrip", "fleet",
    ]

    /// Map normalized app names (from ProcessScanner) to bundle identifiers
    private static let appBundleIds: [String: [String]] = [
        // VSCode family
        "vscode": ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium.VSCodium"],
        // Electron-based editors
        "cursor": ["com.todesktop.230313mzl4w4u92"],
        "windsurf": ["com.codeium.windsurf"],
        "trae": ["com.trae.app"],
        // Native editors
        "zed": ["dev.zed.Zed"],
        "sublime": ["com.sublimetext.4", "com.sublimetext.3"],
        "nova": ["com.panic.Nova"],
        "emacs": ["org.gnu.Emacs"],
        // JetBrains IDEs
        "intellij": ["com.jetbrains.intellij", "com.jetbrains.intellij.ce"],
        "webstorm": ["com.jetbrains.WebStorm"],
        "pycharm": ["com.jetbrains.pycharm", "com.jetbrains.pycharm.ce"],
        "goland": ["com.jetbrains.goland"],
        "clion": ["com.jetbrains.CLion"],
        "rider": ["com.jetbrains.rider"],
        "phpstorm": ["com.jetbrains.PhpStorm"],
        "rubymine": ["com.jetbrains.rubymine"],
        "datagrip": ["com.jetbrains.datagrip"],
        "fleet": ["fleet.app"],
        // Terminals
        "ghostty": ["com.mitchellh.ghostty"],
        "terminal": ["com.apple.Terminal"],
        "iterm": ["com.googlecode.iterm2"],
        "alacritty": ["io.alacritty"],
        "kitty": ["net.kovidgoyal.kitty"],
        "wezterm": ["com.github.wez.wezterm"],
    ]

    /// Attempt to focus the window for a given session.
    /// Returns false if the app isn't running or the window doesn't exist.
    public func jumpTo(session: Session) -> Bool {
        // Ghostty: activate + best-effort tab switching via AppleScript
        if let appName = session.app, appName.lowercased() == "ghostty" {
            if let app = findRunningApp(named: appName) {
                return jumpToGhosttyTab(session: session, app: app)
            }
            return false
        }

        // Find the app
        guard let appName = session.app,
              let app = findRunningApp(named: appName) ?? findAppByPid(session.pid) else {
            // Last resort: find any terminal window matching cwd
            if let cwd = session.cwd {
                if let (termApp, window) = findTerminalWindowByCwd(cwd) {
                    let appRef = AXUIElementCreateApplication(termApp.processIdentifier)
                    raiseAndFocus(window, appRef: appRef)
                    termApp.activate()
                    return true
                }
            }
            return false
        }

        // Activate and focus the correct window
        app.activate()
        if let cwd = session.cwd {
            cycleToWindow(matching: cwd, in: app)
        }
        return true
    }

    // MARK: - Private helpers

    private func findRunningApp(named appName: String) -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications
        let loweredName = appName.lowercased()

        // First try matching by bundle identifier (most reliable)
        if let bundleIds = Self.appBundleIds[loweredName] {
            if let app = apps.first(where: { app in
                guard let bundleId = app.bundleIdentifier else { return false }
                return bundleIds.contains(bundleId)
            }) {
                return app
            }
        }

        // Fall back to name matching
        return apps.first { runningApp in
            let name = runningApp.localizedName?.lowercased() ?? ""
            return name.contains(loweredName) ||
                   ProcessScanner.appNameMap.values.contains(where: { $0 == loweredName && name.contains($0) })
        }
    }

    private func findAppByPid(_ pid: Int?) -> NSRunningApplication? {
        guard let pid else { return nil }

        var currentPid = pid
        for _ in 0..<10 {
            if let app = NSRunningApplication(processIdentifier: pid_t(currentPid)),
               app.activationPolicy == .regular {
                return app
            }
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

    /// Find a terminal window whose title contains the cwd (or its last path component)
    private func findTerminalWindowByCwd(_ cwd: String) -> (NSRunningApplication, AXUIElement)? {
        let dirName = URL(fileURLWithPath: cwd).lastPathComponent
        let terminalApps = runningTerminalApps()

        for app in terminalApps {
            let appRef = AXUIElementCreateApplication(app.processIdentifier)

            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let windows = windowsRef as? [AXUIElement] else { continue }

            for window in windows {
                guard let title = windowTitle(window) else { continue }

                // Match full path first, then directory name
                if title.contains(cwd) || title.contains(dirName) {
                    return (app, window)
                }
            }
        }

        return nil
    }

    /// Get all running terminal apps
    private func runningTerminalApps() -> [NSRunningApplication] {
        let apps = NSWorkspace.shared.runningApplications
        return apps.filter { app in
            guard app.activationPolicy == .regular else { return false }
            if let bundleId = app.bundleIdentifier,
               Self.terminalBundleIds.contains(bundleId) {
                return true
            }
            // Also match by name for terminals not in the bundle ID list
            let name = (app.localizedName ?? "").lowercased()
            return ProcessScanner.appNameMap.keys.contains(where: { $0.lowercased() == name })
        }
    }

    /// Get the title of an AXUIElement window
    private func windowTitle(_ window: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
              let title = titleRef as? String else { return nil }
        return title
    }

    /// Find any running terminal app as a last resort
    private func findAnyTerminalApp() -> NSRunningApplication? {
        return runningTerminalApps().first
    }

    /// Check if the app has any window whose title matches the cwd
    private func hasMatchingWindow(cwd: String, in app: NSRunningApplication) -> Bool {
        let dirName = URL(fileURLWithPath: cwd).lastPathComponent
        let appRef = AXUIElementCreateApplication(app.processIdentifier)

        var windowsRef: CFTypeRef?
        let axResult = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
        // debugLog("[WJ] AX windows result: \(axResult.rawValue) (0=success)")

        guard axResult == .success, let windows = windowsRef as? [AXUIElement] else {
            // debugLog("[WJ] AX failed or no windows")
            return false
        }

        // debugLog("[WJ] Window count: \(windows.count)")
        for (i, window) in windows.enumerated() {
            let title = windowTitle(window) ?? "<no title>"
            let matches = title.contains(cwd) || title.contains(dirName)
            // debugLog("[WJ]   [\(i)] \"\(title)\" matches=\(matches)")
        }

        return windows.contains { window in
            guard let title = windowTitle(window) else { return false }
            return title.contains(cwd) || title.contains(dirName)
        }
    }

    /// Run an AppleScript via the system `osascript` binary.
    /// This bypasses TCC permission issues -- osascript has its own authorization
    /// to send Apple Events, unlike embedded NSAppleScript which requires the
    /// host app to be individually authorized (and this resets on every rebuild).
    private func runOsascript(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
            process.waitUntilExit()
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let stderr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            _ = stderr // consumed
            return stdout.isEmpty ? nil : stdout
        } catch {
            // debugLog("[WJ] osascript: launch failed: \(error)")
            return nil
        }
    }

    /// Cycle through an app's windows with Cmd+` until the target cwd is focused.
    /// Uses osascript subprocess to avoid TCC permission issues with NSAppleScript/AX.
    private func cycleToWindow(matching cwd: String, in app: NSRunningApplication) {
        let dirName = URL(fileURLWithPath: cwd).lastPathComponent
        let processName = app.localizedName ?? "Code"

        // Get window count and front window title
        guard let info = runOsascript("""
            tell application "System Events" to tell process "\(processName)" to \
            return (count of windows as text) & "|" & name of front window
            """) else {
            // debugLog("[WJ] cycleToWindow: osascript failed")
            return
        }

        let parts = info.split(separator: "|", maxSplits: 1).map(String.init)
        let windowCount = Int(parts.first ?? "0") ?? 0
        let startTitle = parts.count > 1 ? parts[1] : ""

        // debugLog("[WJ] cycleToWindow: \(windowCount) windows, front=\"\(startTitle)\", target=\(dirName)")

        guard windowCount > 1 else { return }
        if startTitle.contains(cwd) || startTitle.contains(dirName) { return }

        // Cycle with Cmd+`, check title after each
        for i in 1...windowCount {
            guard let currentTitle = runOsascript("""
                tell application "System Events" to tell process "\(processName)"
                    keystroke "`" using command down
                    delay 0.15
                    return name of front window
                end tell
                """) else {
                // debugLog("[WJ] cycle #\(i) failed")
                return
            }

            // debugLog("[WJ] cycle #\(i) -> \"\(currentTitle)\"")

            if currentTitle.contains(cwd) || currentTitle.contains(dirName) { return }
            if currentTitle == startTitle { return }
        }
    }

    /// Raise a specific window and set it as the focused/main window of the app (for native apps)
    private func raiseAndFocus(_ window: AXUIElement, appRef: AXUIElement) {
        AXUIElementSetAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, window)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
    }

    /// Raise a window in the app whose title matches the cwd (for native apps like terminals)
    private func raiseWindowByCwd(_ cwd: String, in app: NSRunningApplication) {
        let dirName = URL(fileURLWithPath: cwd).lastPathComponent
        let appRef = AXUIElementCreateApplication(app.processIdentifier)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { return }

        for window in windows {
            guard let title = windowTitle(window) else { continue }
            if title.contains(cwd) || title.contains(dirName) {
                raiseAndFocus(window, appRef: appRef)
                return
            }
        }
    }

    // MARK: - Ghostty: tab switching

    /// Activate Ghostty and switch to the tab containing the session's process.
    /// Strategy: find the session PID's TTY, match it to a Ghostty tab, switch via Cmd+N.
    private func jumpToGhosttyTab(session: Session, app: NSRunningApplication) -> Bool {
        // Raise the correct window if multiple Ghostty windows exist
        if let cwd = session.cwd {
            raiseWindowByCwd(cwd, in: app)
        }
        app.activate()

        // If no PID, we can't match to a tab -- just activating is enough
        guard let pid = session.pid else { return true }

        // Get the TTY of the session process
        guard let sessionTTY = ttyForPid(pid) else { return true }

        // Query Ghostty tabs and find the one whose terminal matches our TTY
        guard let tabIndex = ghosttyTabIndex(forTTY: sessionTTY, ghosttyPid: app.processIdentifier) else {
            return true
        }

        // Switch to the tab via Cmd+{index} keystroke (1-based, max 9)
        switchGhosttyTab(to: tabIndex)
        return true
    }

    /// Get the TTY device name for a PID by walking up to the shell parent
    private func ttyForPid(_ pid: Int) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "tty=", "-p", "\(pid)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let tty = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let tty, !tty.isEmpty, tty != "??" {
                return tty
            }
        } catch {}
        return nil
    }

    /// Find which Ghostty tab index (1-based) contains a terminal with the given TTY.
    /// Uses AppleScript to enumerate tabs, then matches TTY via child processes.
    private func ghosttyTabIndex(forTTY sessionTTY: String, ghosttyPid: pid_t) -> Int? {
        // Get tab count via AppleScript
        let countScript = NSAppleScript(source: """
            tell application "Ghostty" to count tabs of front window
            """)
        var error: NSDictionary?
        guard let result = countScript?.executeAndReturnError(&error),
              result.int32Value > 1 else {
            return nil // Only 1 tab or error -- no need to switch
        }

        let tabCount = Int(result.int32Value)

        // For each tab, switch to it and check which TTY becomes the foreground
        // This is the most reliable approach since Ghostty doesn't expose TTY per tab
        for tabIdx in 1...min(tabCount, 9) {
            // Switch to tab
            let switchScript = NSAppleScript(source: """
                tell application "System Events"
                    tell process "Ghostty"
                        keystroke "\(tabIdx)" using command down
                    end tell
                end tell
                """)
            switchScript?.executeAndReturnError(nil)
            usleep(50_000) // 50ms for tab switch

            // Check if the foreground process of this tab's terminal matches our session
            // Read the foreground process group of the Ghostty window's active terminal
            let checkProcess = Process()
            checkProcess.executableURL = URL(fileURLWithPath: "/bin/ps")
            checkProcess.arguments = ["-o", "tty=,stat=", "-p", "\(ghosttyPid)"]
            let checkPipe = Pipe()
            checkProcess.standardOutput = checkPipe
            checkProcess.standardError = FileHandle.nullDevice

            // Alternative: check if any process on sessionTTY is in foreground
            let fgCheck = Process()
            fgCheck.executableURL = URL(fileURLWithPath: "/bin/ps")
            fgCheck.arguments = ["-t", sessionTTY, "-o", "pid="]
            let fgPipe = Pipe()
            fgCheck.standardOutput = fgPipe
            fgCheck.standardError = FileHandle.nullDevice
            do {
                try fgCheck.run()
                fgCheck.waitUntilExit()
                let data = fgPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !output.isEmpty {
                    // This TTY has processes -- it's a valid terminal
                    // We found our tab if the session PID's TTY matches
                    return tabIdx
                }
            } catch {}
        }

        return nil
    }

    /// Switch Ghostty to a specific tab index (1-based) via keystroke
    private func switchGhosttyTab(to index: Int) {
        guard index >= 1 && index <= 9 else { return }
        let script = NSAppleScript(source: """
            tell application "System Events"
                tell process "Ghostty"
                    keystroke "\(index)" using command down
                end tell
            end tell
            """)
        script?.executeAndReturnError(nil)
    }
}
#endif
