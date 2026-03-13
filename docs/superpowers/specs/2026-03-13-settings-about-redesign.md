# Settings Window Redesign + About Page

**Date:** 2026-03-13
**Status:** Approved

## Summary

Restructure the Preferences window from 6 tabs into 3, and add an About page with branding, links, update management, and utility actions.

## Current State

The Preferences window (`PreferencesView.swift`, 400x520) is a flat `Form` with 6 `Section`s (General, Notifications, Data, API, Hooks, Updates) -- there is no `TabView`. There is no About page. Update checking is manual only. `UpdateChecker` is created as a `@StateObject` local to `PreferencesView`.

## Proposed Design

### Tab Structure

Introduce a `TabView` and organize the current 6 flat sections into 3 tabs:

| Tab | Icon | Contents |
|---|---|---|
| General | Gear | Startup, Monitoring, Notifications, Data |
| Integrations | Link | API Server port, Claude Code Hooks config |
| About | Info circle | Brand identity, links, updates, utilities |

### General Tab

Merges current General + Notifications + Data tabs:

- **Startup section**: Launch at login toggle
- **Monitoring section**: Scan interval picker (10/30/60s), Show estimated cost toggle
- **Notifications section**: Enable notifications toggle, hint about per-session context menu control
- **Data section**: Hint about 24h auto-purge of finished sessions

### Integrations Tab

Merges current API + Hooks tabs:

- **API Server section**: Port field (1024-65535), hint about localhost-only + restart requirement
- **Claude Code Hooks section**: Hint about ~/.claude/settings.json, "Copy Hook Config" button

### About Tab

New tab, inspired by CodexBar's About page pattern:

- **App icon**: Load via `Image(nsImage: NSApplication.shared.applicationIconImage)` (works regardless of how the icon is bundled)
- **App name**: "AgentPing"
- **Version**: Dynamic via `UpdateChecker.currentVersion` (reads `CFBundleShortVersionString`, falls back to "0.0.0-dev" in debug builds -- this is expected)
- **Tagline**: "Run 10 agents. Know which one needs you."
- **Links row** (horizontal): GitHub, Website, License -- each opens in default browser
- **Updates section**:
  - "Check automatically" toggle (new `@AppStorage` preference, checks on app launch)
  - Status line showing current state (Up to date / vX.Y.Z available / error)
  - "Check Now" button (existing `UpdateChecker.check()`)
  - Homebrew upgrade command copy + GitHub release link when update available
- **Utility buttons** (horizontal): "Copy Debug Info", "Open Data Folder"
  - Copy Debug Info: copies a formatted block to clipboard for bug reports:
    ```
    AgentPing v0.6.12
    macOS 14.2.1 (23C71)
    API port: 19199
    Active sessions: 3
    Claude processes: 2
    ```
    Sources: `UpdateChecker.currentVersion`, `ProcessInfo.processInfo.operatingSystemVersionString`, `@AppStorage("apiPort")`, `SessionManager.sessions` count, `ProcessScanner` count
  - Open Data Folder: opens ~/.agentping/ in Finder
- **Copyright**: "2026 Eric Ermerimen. PolyForm Noncommercial 1.0.0"

### Auto-Update Check (New Feature)

`UpdateChecker` must become a shared instance so the launch check result is visible in the About tab:
- Convert to `static let shared = UpdateChecker()` singleton pattern
- `PreferencesView` uses `@ObservedObject var updateChecker = UpdateChecker.shared` instead of `@StateObject`
- `AppDelegate` references `UpdateChecker.shared` for the launch check

Behavior:
- New `@AppStorage("checkForUpdatesAutomatically")` preference, default `true`
- On app launch (`AppDelegate.applicationDidFinishLaunching`), if enabled, call `UpdateChecker.shared.check()` after a short delay (e.g., 5 seconds)
- No recurring timer -- just once on launch

### Window Dimensions

- Keep width at 400px
- Use a fixed height that accommodates the tallest tab (About): 540px
- SwiftUI `TabView` inside `Form` does not auto-resize the `NSWindow` per tab, so pick a height that works for all tabs without excessive empty space

## Files to Modify

| File | Change |
|---|---|
| `Sources/AgentPing/Views/PreferencesView.swift` | Restructure into 3-tab TabView (General, Integrations, About) |
| `Sources/AgentPing/UpdateChecker.swift` | Add auto-check on launch support |
| `Sources/AgentPing/AgentPingApp.swift` | Trigger auto-update check on launch |

## Files to Create

None. All changes go into existing files.

## Design Decisions

- **Dropped Diagnostics tab**: The popover already surfaces session counts and status. API server health is implicitly visible (sessions appear or they don't). The useful bits (Copy Debug Info, Open Data Folder) fit naturally in the About tab.
- **3 tabs, not 4**: Fewer tabs means less cognitive overhead. A dev tool settings window should be scannable in seconds.
- **Auto-check on launch only**: No recurring timer. Keeps it simple, avoids unnecessary network calls. Users who want to check manually can click "Check Now".
- **Horizontal link row**: More compact than stacked links. GitHub/Website/License are the three things someone visiting About actually wants.

## Out of Scope

- In-app auto-update/download (still via Homebrew)
- Diagnostics tab (see design decisions)
- Changes to the popover UI
- Changes to the marketing site
