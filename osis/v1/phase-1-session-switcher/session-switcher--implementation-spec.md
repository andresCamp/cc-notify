# Overstory Phase 1 -- Session Switcher Implementation Spec

## Scope

This spec replaces the earlier Phase 1 implementation doc and narrows the feature to the part of Overstory that the current codebase can actually support.

Phase 1 ships a hotkey-driven floating panel for **hook-visible Claude Code sessions**:
- A session is visible when Overstory has received a `Stop` or `Notification` hook for it within the retention window.
- The panel is an **attention switcher**, not a complete inventory of all running sessions.
- Phase 1 does **not** attempt polling-based runtime discovery.
- Phase 1 does **not** infer true `working` or `idle` state. Those require polling, heartbeat data, or another active runtime signal.

Current implementation artifact names still use `Overstory*` and `.overstory`. This spec uses **Overstory** as the product name, but references the current file and type names verbatim where needed.

---

## Status

| Phase | Status | Notes |
|-------|--------|-------|
| 0. Contract normalization | Not started | Extend hook log/state payloads with typed panel data |
| 1. Global hotkey + panel shell | Not started | Carbon hotkey + floating `NSPanel` |
| 2. Session projection | Not started | Parse normalized log entries into panel sessions |
| 3. Card grid | Not started | Grid layout, card styling, panel sizing |
| 4. Interaction | Not started | Keyboard navigation, click, dismiss |
| 5. Focus integration | Not started | Reuse existing Ghostty focus path |

---

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Hotkey API | Carbon `RegisterEventHotKey` | No accessibility permission required and still the pragmatic macOS choice for a global toggle. |
| Default hotkey | Cmd+Shift+Space (`keyCode 49`) | Already resolved in the surrounding Phase 1 docs and good enough for initial implementation. |
| Detection source for Phase 1 | Hooks + log/state files only | Matches the code that exists today. Avoids over-promising runtime discovery that is not implemented. |
| Panel promise | Show recent hook-visible sessions, not all running sessions | The current system only materializes sessions when a hook fires and prunes logs after 1 hour. |
| Status model | `needsApproval`, `waitingForInput`, `turnComplete`, `informational` | These are the only attention states the hook payload can support reliably today. |
| Session model | Extend `OverstorySession` with `cwd`, typed event/status, and optional `notificationType` | The panel needs directory context and typed sorting. String heuristics on title are not sufficient. |
| Sort order | `needsApproval` > `waitingForInput` > `turnComplete` > `informational`, then newest first | Preserves attention-first behavior while staying honest about the available data. |
| Visual identity | Deterministic gradient from `project` name hash | Gives each card a stable visual anchor without relying on mutable titles. |
| Panel placement | Center on the screen containing the mouse pointer | A global-hotkey accessory app has no reliable “active window” screen. Cursor location is explicit and implementable. |
| Layout | Grid, up to 5 columns | Matches the existing Phase 1 direction and scales better than a single column. |
| Keyboard navigation | Row-sticky Left/Right, column-preserving Up/Down, no wrap | Prevents boundary jumps and removes ambiguity. |
| Dismiss behavior | Auto-dismiss after confirm, plus Escape, click-outside, and hotkey toggle | Already resolved in the broader spec set and should not remain open. |
| File structure | Keep work in `app/OverstoryBar.swift` for Phase 1 | Consistent with the current single-file Swift app pattern. |

---

## Explicit Non-Goals

Phase 1 does not ship:
- Polling via `pgrep`, process-tree walking, or Ghostty enumeration to discover sessions that have not emitted a hook.
- A `working` or `idle` runtime badge.
- Hover-to-preview window activation.
- Configurable hotkeys or a settings UI.
- Terminal support beyond the existing Ghostty focus path.

Those items remain future work and should not appear in the Phase 1 UI contract.

---

## User-Facing Contract

When the developer presses the global hotkey:
1. Overstory reloads the recent hook-backed session list.
2. The floating panel appears on the interaction screen.
3. Sessions are sorted by attention priority, then by recency.
4. The developer can move through cards with the keyboard or click one.
5. Confirming a card dismisses the panel and focuses the matching Ghostty terminal through the existing focus engine.

If there are no recent hook-visible sessions, the panel shows an empty state:

> No recent Claude Code sessions

Secondary empty-state copy:

> Sessions appear here after they emit a hook event.

---

## Source of Truth

### Retention Window

- The panel reads from `~/.overstory/log`.
- Only log entries from the last **60 minutes** are eligible.
- Old log entries continue to be pruned during reload.
- State files in `~/.overstory/state` are used for focus enrichment, not discovery.

### Hook Log Contract

`scripts/overstory.sh` must write the following fields into every log entry:

```json
{
  "session_id": "abc123",
  "project": "overstory",
  "cwd": "/Users/andrescampos/Projects/overstory",
  "event": "Notification",
  "notification_type": "permission_prompt",
  "status": "needsApproval",
  "title": "Approval Needed",
  "body": "Claude needs permission",
  "terminal_kind": "ghostty",
  "tty": "/dev/ttys012",
  "ghostty_terminal_id": "9A2B...",
  "ts": 1775422800
}
```

Required fields:
- `session_id`
- `project`
- `cwd`
- `event`
- `status`
- `title`
- `body`
- `ts`

Optional fields:
- `notification_type`
- `terminal_kind`
- `tty`
- `ghostty_terminal_id`

### State File Contract

The state file remains the focus hand-off artifact and must also carry:
- `cwd`
- `event`
- `notification_type`
- `status`
- `ts`

This keeps the focus path and the panel projection aligned on the same typed data.

### Status Normalization Rules

Normalization happens in `scripts/overstory.sh`, not in Swift title parsing.

| Hook payload | Normalized status | Sort rank |
|--------------|-------------------|-----------|
| `Notification` + `permission_prompt` | `needsApproval` | 0 |
| `Notification` + `idle_prompt` | `waitingForInput` | 1 |
| `Stop` | `turnComplete` | 2 |
| Any other logged `Notification` | `informational` | 3 |

If a hook event is not mapped into one of the states above, it should not be written as a Phase 1 panel log entry.

---

## Swift Data Model

`app/OverstoryBar.swift` should stop treating the panel as a pure consumer of the current minimal `OverstorySession` shape.

Phase 1 extends `OverstorySession` to:

```swift
enum SessionEventKind: String {
    case notification = "Notification"
    case stop = "Stop"
}

enum SessionStatus: Int, Comparable {
    case needsApproval = 0
    case waitingForInput = 1
    case turnComplete = 2
    case informational = 3

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct OverstorySession {
    let sessionId: String
    let project: String
    let cwd: String
    let latestTitle: String
    let latestBody: String
    let eventKind: SessionEventKind
    let notificationType: String?
    let status: SessionStatus
    let terminalKind: String
    let tty: String
    let ghosttyTerminalId: String
    let timestamp: Date
    let notificationCount: Int
}
```

Implementation requirement:
- `reload()` is no longer “unchanged”.
- `reload()` must parse the normalized log contract, build the typed `OverstorySession` array, sort it, and feed both the menubar menu and the panel.

Sort implementation:

```swift
sessions.sorted {
    if $0.status != $1.status { return $0.status < $1.status }
    if $0.timestamp != $1.timestamp { return $0.timestamp > $1.timestamp }
    return $0.project.localizedCaseInsensitiveCompare($1.project) == .orderedAscending
}
```

---

## Floating Panel Contract

### Window Type

Use `NSPanel` with:
- `styleMask: [.borderless]`
- `level = .floating`
- `isFloatingPanel = true`
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`
- transparent background + `NSVisualEffectView`

Phase 1 should prefer reliable keyboard focus over non-activating-window cleverness:
- Show path calls `NSApp.activate(ignoringOtherApps: true)`.
- Then `orderFrontRegardless()`, `makeKey()`, and `makeFirstResponder(cardGridView)`.

The panel is transient and confirmation immediately returns focus to Ghostty, so brief activation of Overstory is acceptable in Phase 1.

### Screen Selection

The panel appears on the **interaction screen**, defined as the screen containing the current mouse pointer:

```swift
func interactionScreen() -> NSScreen? {
    let mouse = NSEvent.mouseLocation
    return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
        ?? NSScreen.main
        ?? NSScreen.screens.first
}
```

Placement rule:
- Use `visibleFrame` of `interactionScreen()`.
- Center horizontally.
- Center vertically with a slight upward offset of `80pt`.

This replaces any Phase 1 use of `NSScreen.main` as the primary placement rule.

### Show / Hide Flow

```
Developer presses Cmd+Shift+Space
    │
    ▼
Hotkey handler calls togglePanel()
    │
    ├── If visible: fade out and orderOut
    │
    └── If hidden:
        1. reload()
        2. rebuild grid from sorted sessions
        3. resize panel to content
        4. move panel to interaction screen
        5. activate app, order front, make key
        6. set first responder to card grid
        7. fade in
```

Dismiss triggers:
- Confirm selection
- Escape
- Click outside / panel loses key status
- Hotkey pressed again

---

## Card Contract

Each card renders:
- Project name
- Truncated working directory path
- Latest title
- Relative timestamp
- Status treatment derived from `SessionStatus`
- A deterministic accent gradient derived from the project hash

Status treatments:
- `needsApproval`: red accent, strongest emphasis
- `waitingForInput`: amber accent
- `turnComplete`: green accent
- `informational`: neutral accent

Phase 1 card design does **not** display a “working” spinner or an “idle” badge.

If `cwd` is empty:
- Show the project name and latest title only.
- Do not synthesize a fake directory from the project name.

Reference color rule:

```swift
func colorForProject(_ project: String) -> NSColor {
    var hash: UInt64 = 5381
    for byte in project.utf8 {
        hash = ((hash << 5) &+ hash) &+ UInt64(byte)
    }

    let hue = CGFloat(hash % 360) / 360.0
    return NSColor(calibratedHue: hue, saturation: 0.55, brightness: 0.88, alpha: 1.0)
}
```

---

## Layout Contract

### Constants

```swift
struct CardLayout {
    static let cardWidth: CGFloat = 160
    static let cardHeight: CGFloat = 100
    static let cornerRadius: CGFloat = 10
    static let gridSpacing: CGFloat = 8
    static let panelPadding: CGFloat = 16
    static let maxColumns = 5
}
```

### Grid Sizing

```swift
columns = min(sessionCount, maxColumns)
rows = Int(ceil(Double(sessionCount) / Double(maxColumns)))

panelWidth = panelPadding * 2
    + CGFloat(columns) * cardWidth
    + CGFloat(max(0, columns - 1)) * gridSpacing

panelHeight = panelPadding * 2
    + CGFloat(rows) * cardHeight
    + CGFloat(max(0, rows - 1)) * gridSpacing
```

Validated examples:

| Sessions | Grid | Panel Size |
|----------|------|------------|
| 1 | 1x1 | 192 x 132 |
| 3 | 3x1 | 528 x 132 |
| 5 | 5x1 | 864 x 132 |
| 7 | 5x2 | 864 x 240 |
| 10 | 5x2 | 864 x 240 |
| 15 | 5x3 | 864 x 348 |

---

## Keyboard Navigation Contract

The grid uses a fixed logical column count equal to `min(sessionCount, maxColumns)`.

Definitions:
- `currentRow = selectedIndex / columns`
- `currentColumn = selectedIndex % columns`
- `rowStart = currentRow * columns`
- `rowEnd = min(rowStart + columns - 1, lastIndex)`

Rules:
- Left: move to `selectedIndex - 1` only if `selectedIndex > rowStart`
- Right: move to `selectedIndex + 1` only if `selectedIndex < rowEnd`
- Up: move to the same logical column in the previous row; clamp to that row’s last item if the column does not exist
- Down: move to the same logical column in the next row; clamp to that row’s last item if the column does not exist
- Enter: confirm selected card
- Escape: dismiss panel
- No wraparound across rows or between first/last items

Reference implementation:

```swift
func moveLeft() {
    let rowStart = (selectedIndex / columns) * columns
    if selectedIndex > rowStart { select(selectedIndex - 1) }
}

func moveRight() {
    let rowStart = (selectedIndex / columns) * columns
    let rowEnd = min(rowStart + columns - 1, lastIndex)
    if selectedIndex < rowEnd { select(selectedIndex + 1) }
}

func moveVertical(delta: Int) {
    let currentRow = selectedIndex / columns
    let currentColumn = selectedIndex % columns
    let targetRow = currentRow + delta
    guard targetRow >= 0 else { return }

    let targetStart = targetRow * columns
    guard targetStart <= lastIndex else { return }

    let targetEnd = min(targetStart + columns - 1, lastIndex)
    select(min(targetStart + currentColumn, targetEnd))
}
```

Pointer rules:
- Hover may update visual highlight only.
- Hover does not focus the terminal in Phase 1.
- Click confirms immediately.

---

## Integration Plan

### Phase 0: Contract Normalization
Scope:
- Update `scripts/overstory.sh` to emit `cwd`, `notification_type`, and normalized `status` in log entries.
- Add the same typed fields to the state file.
- Update `reload()` parsing in `app/OverstoryBar.swift`.

Validates:
- The panel has all required data for rendering and sorting.
- Status is derived from machine-readable fields, not copy text.

### Phase 1: Global Hotkey + Panel Shell
Scope:
- Add `HotKeyManager`
- Add `SessionSwitcherPanel`
- Implement toggle behavior

Validates:
- Global hotkey works from any app
- Panel appears and dismisses reliably

### Phase 2: Session Projection
Scope:
- Load recent log entries
- Group by `session_id`
- Keep latest entry per session
- Count entries per session for the existing notification badge behavior

Validates:
- Panel and menubar share the same normalized session array
- Sort order is stable and predictable

### Phase 3: Card Grid
Scope:
- Add `CardGridView`
- Add `SessionCardView`
- Resize panel from session count

Validates:
- 1 to 15 sessions lay out correctly
- Directory and status render correctly

### Phase 4: Interaction
Scope:
- Implement exact keyboard rules from this spec
- Implement click confirm
- Implement click-outside and Escape dismiss

Validates:
- Keyboard behavior matches the spec at row boundaries and short final rows

### Phase 5: Focus Integration
Scope:
- On confirm, call the existing focus path used by the menubar menu
- Dismiss the panel before or while focus runs

Validates:
- Hotkey -> select -> Ghostty focus works end to end

---

## Acceptance Criteria

- [ ] Global hotkey toggles the panel from any foreground app
- [ ] The panel shows recent hook-visible sessions only, with that limitation reflected in the empty state and implementation
- [ ] Every card can render a real `cwd` when the hook provided one
- [ ] Status sorting is driven by normalized `status`, not by parsing display strings
- [ ] The panel appears on the screen containing the mouse pointer
- [ ] Left/Right never jump across rows
- [ ] Up/Down preserve column intent and clamp correctly on short rows
- [ ] Confirm dismisses the panel and reuses the existing Ghostty focus logic
- [ ] Existing menubar and notifications continue to work

---

## Follow-On Work

The following items should only return to scope when Overstory gains a runtime discovery system:
- Show all running sessions
- Detect true `working` state
- Detect true `idle` state
- Show sessions that have never emitted a hook
- Preview windows on hover
