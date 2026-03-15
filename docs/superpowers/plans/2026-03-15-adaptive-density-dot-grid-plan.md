# Implementation Plan: Adaptive Density + Dot Grid View

**Spec:** `docs/superpowers/specs/2026-03-15-adaptive-density-dot-grid-design.md`
**Target version:** 0.7.0

## Dependency Graph

```
  Step 1: DisplayPreferences + Session extensions (foundation)
     │
     ├──► Step 2: Rename SessionRowView → ExpandedRowView
     │       │
     │       └──► Step 3: CompactRowView (new)
     │               │
     │               └──► Step 4: Adaptive density in PopoverView
     │
     └──► Step 5: DotCellView + DotGridView (new, parallel with 2-4)
             │
             └──► Step 6: View mode toggle + search interaction
                     │
                     └──► Step 7: Debug info + final polish
```

Steps 2-4 and Step 5 can run in parallel (independent view branches).

## Steps

### Step 1: Foundation -- DisplayPreferences + Session Extensions

**Files:**
- Create `Sources/AgentPing/DisplayPreferences.swift`
- Edit `Sources/AgentPingCore/Models/Session.swift`

**Tasks:**
1. Create `DisplayPreferences` as an `ObservableObject`:
   ```swift
   class DisplayPreferences: ObservableObject {
       @AppStorage("viewMode") var viewMode = "list"
       @AppStorage("costTrackingEnabled") var costTrackingEnabled = false
   }
   ```
   Use a String-backed approach for `viewMode` with a computed `ViewMode` enum property, since `@AppStorage` doesn't natively support custom enums.

2. Add `ViewMode` enum (in same file or in AgentPingCore):
   ```swift
   enum ViewMode: String {
       case list
       case dotGrid
   }
   ```

3. Extract shared computed properties from `SessionRowView` into `Session` extensions in `Session.swift`:
   - `var projectName: String` -- derives display name from cwd/taskDescription/name
   - `var displayPath: String` -- home-relative path
   - `var subtitle: String?` -- task or path based on context
   - `var isAttention: Bool` -- needsInput || error || isFreshIdle

   Note: `projectName` currently reads `FileManager.default.homeDirectoryForCurrentUser` which makes it impure. This is fine for a UI helper on the model -- it won't be called in background threads.

**Verification:** `swift build` succeeds. No view changes yet.

---

### Step 2: Rename SessionRowView to ExpandedRowView

**Files:**
- Rename `Sources/AgentPing/Views/SessionRowView.swift` → `Sources/AgentPing/Views/ExpandedRowView.swift`
- Edit `Sources/AgentPing/Views/PopoverView.swift` (update reference)

**Tasks:**
1. Rename the file and the struct: `SessionRowView` → `ExpandedRowView`
2. Replace inline computed properties (`projectName`, `subtitle`, `displayPath`, `isAttention`, `isHomeCwd`) with the `Session` extensions from Step 1
3. Replace `@AppStorage("costTrackingEnabled")` with `@EnvironmentObject var displayPrefs: DisplayPreferences`
4. Update `PopoverView.sessionRow()` to reference `ExpandedRowView`

**Verification:** `swift build` succeeds. App looks identical to before -- no visual changes.

---

### Step 3: Create CompactRowView

**Files:**
- Create `Sources/AgentPing/Views/CompactRowView.swift`

**Tasks:**
1. Build a minimal single-line session row:
   - Left: project name (size 12, secondary color)
   - Right: status label (size 11, colored)
   - No accent bar, no app badge, no subtitle, no context bar, no cost
   - Same padding as ExpandedRowView (horizontal 14, vertical 6 -- slightly less than expanded's 8)
2. Same hover behavior: `SessionHoverView` popover on 0.4s delay
3. Same click behavior: `onTap` closure for jump-to-window
4. Same context menu support (passed in from PopoverView)
5. Hover background: subtle `Color.primary.opacity(isHovered ? 0.04 : 0)`
6. Use `session.projectName` from Session extension

**Verification:** `swift build` succeeds. Not wired up yet.

---

### Step 4: Adaptive Density in PopoverView

**Files:**
- Edit `Sources/AgentPing/Views/PopoverView.swift`

**Tasks:**
1. Inject `DisplayPreferences` as `@EnvironmentObject` (or `@StateObject` at the app level, passed down)
2. Split `activeSessionList` to render attention sessions as `ExpandedRowView` and working sessions as `CompactRowView`:
   ```
   ForEach(group.sessions) { session in
       if session.isAttention {
           ExpandedRowView(...)
       } else {
           CompactRowView(...)
       }
   }
   ```
3. Within project groups, attention sessions sort first (already handled by existing sort -- needsInput/error/freshIdle have lower sortPriority).
4. History tab: all sessions use `CompactRowView` (they're all done/idle -- no attention sessions in history).
5. Wire up `DisplayPreferences` in `AgentPingApp.swift` as `@StateObject` and inject via `.environmentObject()`.

**Verification:** Build and run. Active tab should show expanded rows for attention sessions, compact rows for working sessions. History tab should show compact rows. Hover popover works on both. Click-to-jump works on both. Context menu works on both.

---

### Step 5: DotCellView + DotGridView (parallel with Steps 2-4)

**Files:**
- Create `Sources/AgentPing/Views/DotGridView.swift` (contains both DotGridView and DotCellView)

**Tasks:**
1. `DotCellView`: a single dot + label
   - 28pt circle with status-derived fill color
   - Glow via `.shadow(color:radius:)` for attention statuses
   - Pulse animation via `scaleEffect` + `opacity` on an overlay circle, using `Animation.easeOut.repeatForever`
   - Project label: 9pt, secondary, truncated, max-width 60
   - Hover: `SessionHoverView` popover on 0.4s delay (same pattern as rows)
   - Click: `onTap` closure
   - Context menu: passed in

2. `DotGridView`: grid container
   - `LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12)`
   - Takes `sessions: [Session]`, `onTap: (Session) -> Void`, `onReviewed: (Session) -> Void`
   - Same sort order as list view
   - Empty state: same empty state view from PopoverView

3. Color mapping (use `Session` extension):
   ```swift
   extension Session {
       var dotColor: Color { ... }
       var dotGlowRadius: CGFloat { ... }
       var dotPulseSpeed: Double? { ... }  // nil = no pulse
   }
   ```

**Verification:** `swift build` succeeds. Create a `#Preview` with mock sessions to visually verify.

---

### Step 6: View Mode Toggle + Search Interaction

**Files:**
- Edit `Sources/AgentPing/Views/PopoverView.swift`

**Tasks:**
1. Add view mode toggle button in the header (between search and sync buttons):
   - Icon: `square.grid.2x2` for dot grid, `list.bullet` for list
   - Toggles `displayPrefs.viewMode`
   - Tooltip: "Switch to dot grid" / "Switch to list"
   - Same button style as existing header buttons (11pt, secondary, 22x22 frame)

2. Wire up view mode in `sessionList`:
   ```swift
   if displayPrefs.viewMode == .dotGrid && searchText.isEmpty {
       DotGridView(sessions: ..., onTap: ..., onReviewed: ...)
   } else {
       // existing adaptive density list
   }
   ```

3. Search override: when `viewMode == .dotGrid` and search is active, show list view. When search is cleared, return to dot grid. No state to manage -- the condition `searchText.isEmpty` handles this automatically.

4. Tab behavior: dot grid only applies to Active tab. History tab always shows list (compact rows). This is because dot grid is for real-time triage of active sessions.

5. Animation: `withAnimation(.easeInOut(duration: 0.15))` on view mode toggle, matching existing search toggle animation.

**Verification:** Build and run. Toggle between list and dot grid. Verify search auto-switches to list. Verify history tab always shows list. Verify dots are clickable, hoverable, right-clickable.

---

### Step 7: Debug Info + Final Polish

**Files:**
- Edit `Sources/AgentPing/Views/PreferencesView.swift`

**Tasks:**
1. Add view mode to debug info string in `AboutTab.copyDebugInfo()`:
   ```swift
   View mode: \(UserDefaults.standard.string(forKey: "viewMode") ?? "list")
   ```

2. Polish pass:
   - Verify accessibility labels on CompactRowView and DotCellView
   - Verify VoiceOver reads dot grid cells correctly
   - Test with 0, 1, 4, 8, 16 sessions in dot grid
   - Test all session status transitions in both views
   - Test app restart preserves view mode

**Verification:** Full manual QA pass. Build release binary: `swift build -c release`.

## Review Checkpoints

- After Step 2: Confirm no visual regression (app looks identical)
- After Step 4: Confirm adaptive density works (expanded attention, compact working)
- After Step 6: Confirm dot grid works (toggle, search override, click/hover/context menu)
- After Step 7: Final QA before tagging release
