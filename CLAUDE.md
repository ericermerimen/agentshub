# AgentPing

## What is this

AgentPing (formerly AgentsHub) is a macOS menu bar app for monitoring Claude Code sessions in real time. It shows session status, lets you jump to terminal windows, sends notifications when agents need input, and tracks context window usage and cost.

The project was renamed from AgentsHub to AgentPing. The local directory is still `/Users/eric.er/agentshub` but the GitHub repo is `ericermerimen/agentping`.

## Tech stack

- **Language**: Swift 5.9+
- **UI**: SwiftUI + AppKit (menu bar popover)
- **Platform**: macOS 14 (Sonoma)+
- **Build**: Swift Package Manager (no Xcode project)
- **Dependencies**: swift-argument-parser (Apple, v1.6.2) -- only dependency
- **CI**: GitHub Actions (release on tag push)
- **Distribution**: Homebrew tap (`ericermerimen/tap/agentping`), curl installer, GitHub Releases

## Architecture

Three Swift targets in a single Swift package:

```
Sources/
├── AgentPing/          # macOS menu bar GUI app (SwiftUI + AppKit)
│   ├── AgentPingApp.swift       # AppDelegate, global hotkey, notifications, popover
│   ├── Views/
│   │   ├── PopoverView.swift    # Main UI: tabs, search, project grouping, context menu
│   │   ├── SessionRowView.swift # Session list row with status, context bar, cost
│   │   └── PreferencesView.swift # Settings window
│   └── Notifications/
│       └── NotificationManager.swift  # macOS notification handling
├── AgentPingCLI/       # CLI tool (ArgumentParser)
│   └── main.swift      # Commands: report, list, status, clear, delete
└── AgentPingCore/      # Shared library (no UI)
    ├── Models/Session.swift           # Session data model + JSON codable
    ├── Store/SessionStore.swift       # File-based JSON persistence (~/.agentping/sessions/)
    ├── Manager/SessionManager.swift   # Session lifecycle, sync, auto-purge
    ├── Scanner/ProcessScanner.swift   # Detects running Claude processes via ps
    ├── Watcher/DirectoryWatcher.swift # FSEvents watcher for live updates
    ├── WindowJumper/WindowJumper.swift # Accessibility API window focus
    └── CLI/ReportHandler.swift        # Processes hook events, reads transcripts
```

## How it works

1. Claude Code hooks call `agentping report --session ID --event TYPE` on each tool use, stop, and notification
2. The CLI writes/updates a JSON file in `~/.agentping/sessions/<session-id>.json`
3. `DirectoryWatcher` detects the file change via FSEvents
4. `SessionManager.reload()` reads all session files
5. The SwiftUI popover updates reactively via `@ObservedObject`
6. Clicking a session uses `WindowJumper` (Accessibility API) to focus the right terminal window

## Key features

- **Active/History tabs** with attention badge counts
- **Project grouping** -- sessions grouped by cwd directory name
- **Search/filter** -- filter by name, project, task, app
- **Pin sessions** -- pinned sessions float to top
- **Global hotkey** -- Ctrl+Option+A toggles the popover
- **Context menu** -- right-click: jump, copy path, open transcript, open terminal, pin, mark done, delete
- **Notifications** -- needs-input, error, done, context window warning (80%+)
- **Context bar** -- visual progress bar for context window usage (green/orange/red)
- **Cost tracking** -- optional per-session and total cost display
- **Auto-purge** -- finished sessions older than 24h removed on launch
- **CLI** -- `agentping list/status/report/clear/delete`

## GitHub repos

- **Main repo**: `ericermerimen/agentping` (was `ericermerimen/agentshub`)
- **Homebrew tap**: `ericermerimen/homebrew-tap`
- **Old repo**: `ericermerimen/agentshub` (still exists, should be archived)

## Secrets

- `TAP_TOKEN` -- fine-grained GitHub PAT with Contents:RW on `homebrew-tap` repo. Used by release workflow to auto-update the Homebrew formula.

## Release process

```bash
git tag v0.X.0
git push origin v0.X.0
```

This triggers `.github/workflows/release.yml` which:
1. Builds universal binary (arm64 + x86_64)
2. Creates `.app` bundle via `Scripts/package_app.sh`
3. Creates tarball with LICENSE (prevents Homebrew directory stripping)
4. Publishes GitHub Release with SHA256 checksums
5. Auto-updates `homebrew-tap` formula with new URL + SHA

## Marketing site

- `site/index.html` -- dark-themed landing page
- Auto-deployed to GitHub Pages via `.github/workflows/pages.yml`
- URL: `https://ericermerimen.github.io/agentping/`
- Accent color: teal (#06b6d4)

## Data storage

- Sessions: `~/.agentping/sessions/<id>.json` (0700 dir permissions)
- Preferences: macOS UserDefaults (`launchAtLogin`, `notificationsEnabled`, `scanInterval`, `costTrackingEnabled`)

## Build commands

```bash
swift build              # Debug build
swift build -c release   # Release build
swift test               # Tests (requires Xcode toolchain for XCTest)
./Scripts/package_app.sh # Build .app bundle
./Scripts/install.sh     # Build + install to /Applications
```

## Known issues / notes

- Sandbox is disabled (required for Accessibility API / window jumping)
- Context window size is hardcoded to 200K tokens (Claude Opus)
- Stale session detection uses 5-minute timeout + process check
- Tests require Xcode toolchain (XCTest not available with plain swift CLI)
- The local directory is still named `agentshub` -- only the repo and all code references are renamed to `agentping`
