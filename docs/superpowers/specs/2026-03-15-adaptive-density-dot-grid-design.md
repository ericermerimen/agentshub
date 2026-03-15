# Adaptive Density + Dot Grid View

**Date:** 2026-03-15
**Status:** Draft
**Version:** 0.7.0

## Problem

AgentPing shows 7 elements per session row regardless of whether the session needs attention or is quietly working. This creates visual noise that undermines the core value proposition: "Run 10 agents. Know which one needs you."

The noise problem is not that there are too many elements -- it's that every session gets the same visual weight. A "Running" session (no action needed) competes for attention with a "Reply" session (action needed NOW).

## Solution

Two complementary features:

1. **Adaptive Density** -- List view automatically adjusts row height based on session state. Attention sessions (needsInput, error, freshIdle) get expanded rows with full detail. Working sessions (running, idle, done) get compact single-line rows.

2. **Dot Grid View** -- Alternative view mode inspired by the app logo. Each session is a colored dot with a project label. Status encoded as color, urgency encoded as pulse animation and glow. Optimized for the "glance" use case with 3-8 sessions.

## Architecture

### View Mode

```swift
enum ViewMode: String {
    case list    // default - adaptive density list
    case dotGrid // compact dot grid
}
```

Stored in `@AppStorage("viewMode")`, defaults to `.list`. Toggle button in popover header.

### Component Structure

```
PopoverView
  ├── header (+ view mode toggle button)
  ├── tabBar
  ├── searchBar
  ├── SessionListView (when viewMode == .list OR search is active)
  │   ├── projectHeader (when multiple projects)
  │   ├── ExpandedRowView (for attention sessions)
  │   │   └── SessionHoverView (on hover)
  │   └── CompactRowView (for working sessions)
  │       └── SessionHoverView (on hover)
  └── DotGridView (when viewMode == .dotGrid AND search is empty)
      ├── DotCellView
      │   └── SessionHoverView (on hover)
      └── empty state
```

### DisplayPreferences

Centralizes all display-related `@AppStorage` values:

```swift
class DisplayPreferences: ObservableObject {
    @AppStorage("viewMode") var viewMode: ViewMode = .list
    @AppStorage("costTrackingEnabled") var costTrackingEnabled = false
    // Future: element toggles go here
}
```

Injected via `@EnvironmentObject` instead of scattered `@AppStorage` bindings in each view.

## Adaptive Density (List View)

### Session Classification

Sessions are classified into two display tiers:

| Tier | Conditions | Row Style |
|------|-----------|-----------|
| **Attention** | `status == .needsInput` OR `status == .error` OR `isFreshIdle == true` | Expanded (current row layout) |
| **Working** | Everything else (`running`, `idle`, `done`, `unavailable`) | Compact (single line) |

This classification already exists as `isAttention` in `SessionRowView`. No new logic needed.

### Expanded Row (Attention Sessions)

Same as current `SessionRowView` layout:
- Left accent bar (teal/orange/red)
- Project name + app badge
- Subtitle (task description or path)
- Context bar + percentage
- Cost (if enabled)
- Status label (Ready/Reply/Error)
- Background tint
- Hover popover on 0.4s delay

### Compact Row (Working Sessions)

Single-line row:
```
  [project-name]                    [status]
```

- Project name: size 12, regular weight, secondary color
- Status: size 11, colored (green for Running, tertiary for idle/done)
- No accent bar, no app badge, no subtitle, no context bar, no cost
- Same hover popover on 0.4s delay (full detail on demand)
- Same context menu (right-click)
- Same click-to-jump behavior

### Visual Separation

When both tiers are present, a subtle divider or spacing separates them:
```
  ┌─ Attention ────────────────────────┐
  │ [expanded row - Reply]             │
  │ [expanded row - Ready]             │
  ├────────────────────────────────────┤
  │ [compact row - Running]            │
  │ [compact row - Running]            │
  │ [compact row - idle 5m]            │
  └────────────────────────────────────┘
```

No explicit "Attention" / "Working" section headers -- the visual density difference is self-documenting. Project grouping headers still appear when multiple projects exist.

### Edge Cases

- All sessions are attention: No compact section. Looks like current view.
- All sessions are working: No expanded section. All compact rows.
- Session transitions (running → needsInput): Row animates from compact to expanded.
- Pinned sessions: Float to top within their tier.

## Dot Grid View

### Layout

4-column CSS-style grid. Each cell is a dot + label.

```
  ┌──────────────────────────────┐
  │  (o)     (o)     (o)    (o) │
  │ pe-ui   pe-ui   pe-ui  agnt │
  │                              │
  │  (o)     (o)     (o)    (o) │
  │ ccs-ui  ccs-ui  cls-ui apps │
  └──────────────────────────────┘
```

### Dot Encoding

| Status | Color | Glow | Pulse Animation |
|--------|-------|------|-----------------|
| Running | Green (#22c55e) | Subtle | Slow pulse (2s) |
| Ready (freshIdle) | Teal (#06b6d4) | Medium | None |
| Needs Input | Orange (#f59e0b) | Strong | Medium pulse (1.5s) |
| Error | Red (#ef4444) | Strong | Fast pulse (1s) |
| Idle | Gray (#475569) | None | None |
| Done | Dark gray (#334155) | None | None, 50% opacity |

### Dot Cell

- Dot: 28pt diameter circle with status color
- Label: project name, 9pt, secondary color, truncated, max 60pt wide
- Hover: same `SessionHoverView` popover
- Click: jump to window (same as list view)
- Right-click: same context menu

### Sorting

Same sort order as list view: pinned first, then by status priority (needsInput > error > freshIdle > running > idle > done).

### Edge Cases

- 0 sessions: Show same empty state as list view
- 1 session: Single dot, top-left
- 3 sessions same project: 3 dots all labeled "pe-ui" -- distinguishable by color. Hover reveals task description.
- 12+ sessions: Grid scrolls vertically
- Search active: Auto-switch to list view. Clearing search returns to dot grid.

## Search Interaction

When `viewMode == .dotGrid` and user activates search:
- View temporarily switches to list mode (adaptive density)
- Search filter applies to list
- When search text is cleared or search is dismissed, view returns to dot grid

Rationale: dot grid is for glancing, not searching. Text search needs text results.

## Preferences Integration

### General Tab Additions

Under "Monitoring" section, after the cost toggle:

```
Section("Display") {
    // No new toggles needed for v0.7
    // Future: element visibility toggles go here
}
```

No new preferences for v0.7. The view mode toggle lives in the popover header for quick access, not in Preferences.

### Debug Info Addition

Add current view mode to the "Copy Debug Info" output:
```
View mode: list
```

## Files Changed

| File | Change |
|------|--------|
| `Views/SessionRowView.swift` | Rename to `ExpandedRowView.swift`, extract shared computeds |
| `Views/CompactRowView.swift` | **New** -- single-line working session row |
| `Views/DotGridView.swift` | **New** -- dot grid container + DotCellView |
| `Views/PopoverView.swift` | Add view mode toggle, wire up adaptive density + dot grid |
| `Views/PreferencesView.swift` | Add viewMode to debug info |
| `DisplayPreferences.swift` | **New** -- ObservableObject wrapping display @AppStorage |

### Not Changed

- `Session.swift` -- no model changes
- `SessionHoverView.swift` -- reused as-is
- `SessionManager.swift` -- no logic changes
- `APIRouter.swift` / `APIServer.swift` -- no API changes
- `AgentPingApp.swift` -- no app lifecycle changes

## Shared Computeds (DRY Extraction)

Extract from `SessionRowView` into `Session` extensions:

```swift
extension Session {
    var projectName: String { ... }
    var subtitle: String? { ... }
    var displayPath: String { ... }
    var isAttention: Bool {
        status == .needsInput || status == .error || isFreshIdle
    }
}
```

Both `ExpandedRowView`, `CompactRowView`, and `DotCellView` use these.

## Rollout

- Default view mode: `.list`
- Adaptive density is always on in list mode (no toggle)
- Dot grid is opt-in via header toggle
- Zero migration, zero data model changes
- Revert: `git revert` or ship next version defaulting back to list
