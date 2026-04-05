# Session Switcher -- Implementation Spec

## Status

| Phase | Status | Notes |
|-------|--------|-------|
| 1. Global Hotkey | Not started | Carbon RegisterEventHotKey |
| 2. Floating Panel Shell | Not started | NSPanel + vibrancy |
| 3. Session Cards | Not started | Custom NSView cards in NSStackView |
| 4. Keyboard Navigation | Not started | moveUp/moveDown/insertNewline |
| 5. Integration | Not started | Wire panel to existing reload + focus logic |

---

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Hotkey API | Carbon RegisterEventHotKey | No Accessibility permission required. Exclusive capture (event consumed, not passed to other apps). Battle-tested by Spotlight, Alfred, Raycast. Deprecated in name only -- no replacement exists, works through macOS 15. |
| Window type | NSPanel (borderless, nonactivatingPanel) | Correct AppKit primitive for floating auxiliary panels. Receives key events without stealing activation from the terminal. |
| Vibrancy material | .hudWindow | Dark translucent appearance matching Spotlight/Cmd+Tab. Can revisit for light mode support. |
| Window level | .floating | Above normal windows, below modals. Same tier as Spotlight. |
| Default hotkey | Cmd+Shift+Space (keyCode 49) | Intuitive, matches Spotlight muscle memory. If it conflicts with input source switching, user can remap later. |
| Card layout | Grid: up to 5 columns, rows wrap | Compact for many sessions. Dynamic panel sizing based on count. NSStackView rows nested in a vertical NSStackView. |
| Keyboard handling | 2D grid navigation via keyDown | Arrow Left/Right within row, Up/Down between rows. Enter confirms, Escape dismisses. Raw keyDown required for Left/Right (no built-in selector). |
| Menubar behavior | Dropdown (unchanged) | Menubar click shows the existing dropdown. Panel is hotkey-only. Two separate interaction paths. |
| Project colors | DJB2 hash to HSL hue | Deterministic, fast, no state. Fixed saturation/brightness keeps colors readable. |
| File structure | Extend CCNotifyBar.swift | Single-file pattern. Add new classes to the same file. Restructure only if it becomes unwieldy. |

---

## System Architecture

```
┌──────────────────────────────────────────────────────┐
│                   CCNotifyBar.swift                   │
│                                                      │
│  ┌─────────────┐    ┌──────────────────────────────┐ │
│  │ HotKeyManager│───>│    SessionSwitcherPanel      │ │
│  │ (Carbon API) │    │    (NSPanel subclass)        │ │
│  └─────────────┘    │                              │ │
│                     │  ┌────────────────────────┐  │ │
│                     │  │  CardGridView           │  │ │
│                     │  │  (NSView, 2D nav)       │  │ │
│                     │  │                        │  │ │
│                     │  │  [Card][Card][Card]    │  │ │
│                     │  │  [Card][Card][Card]    │  │ │
│                     │  │  [Card]                │  │ │
│                     │  └────────────────────────┘  │ │
│                     └──────────────────────────────┘ │
│                                                      │
│  ┌─────────────────┐    ┌────────────────────────┐   │
│  │ CCNotifyBar      │───>│ Existing: reload(),    │   │
│  │ (AppDelegate)    │    │ focusGhosttyTerminal(),│   │
│  │                  │    │ watchLogDir(), etc.     │   │
│  └─────────────────┘    └────────────────────────┘   │
└──────────────────────────────────────────────────────┘
```

---

## Hotkey Toggle Flow

```
Developer presses Cmd+Shift+Space (anywhere in macOS)
    │
    ▼
Carbon EventHotKeyPressed fires
    │
    ▼
HotKeyManager.onToggle callback
    │
    ├── Panel is hidden → show()
    │   │
    │   ├── CCNotifyBar.reload() to refresh sessions
    │   ├── Build card views from sessions array
    │   ├── Sort: approval > complete > working > idle, then by recency
    │   ├── Center panel on NSScreen.main
    │   ├── orderFrontRegardless() + makeKey()
    │   ├── makeFirstResponder(cardListView)
    │   └── Fade in (0.15s)
    │
    └── Panel is visible → dismiss()
        │
        └── Fade out (0.12s) + orderOut
```

## Card Selection Flow

```
Panel is visible, cardGridView is first responder
    │
    ├── Arrow Right → index + 1 (clamp to last card)
    ├── Arrow Left  → index - 1 (clamp to 0)
    ├── Arrow Down  → index + maxColumns (clamp to last card)
    ├── Arrow Up    → index - maxColumns (clamp to 0)
    │   All arrows: deselect old card, select new card (needsDisplay)
    │
    ├── Enter → insertNewline()
    │   │
    │   ├── Get session at selectedIndex
    │   ├── Dismiss panel
    │   └── Call focusSession(sessionId) — existing focus logic
    │
    ├── Mouse click on card → same as Enter for that card
    ├── Escape     → cancelOperation() → dismiss panel
    └── Click outside → resignKey() → dismiss panel
```

---

## Wire Contracts

### Session Data (existing, reused from CCSession)

```swift
struct CCSession {
    let sessionId: String
    let project: String
    let latestTitle: String
    let latestEvent: String       // "Notification" | "Stop" | ""
    let terminalKind: String
    let tty: String
    let ghosttyTerminalId: String
    let timestamp: Date
    let notificationCount: Int
}
```

### Status Priority (new)

```swift
enum SessionPriority: Int, Comparable {
    case approval = 0      // latestEvent == "Notification", title contains "Approval"
    case complete = 1      // latestEvent == "Stop"
    case working = 2       // latestEvent == "Notification", other
    case idle = 3          // no recent events

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
```

### Card Layout Constants

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

Panel size is dynamic based on session count:

```
columns = min(sessionCount, maxColumns)
rows    = ceil(sessionCount / maxColumns)

panelWidth  = panelPadding * 2 + columns * cardWidth + (columns - 1) * gridSpacing
panelHeight = panelPadding * 2 + rows * cardHeight + (rows - 1) * gridSpacing
```

| Sessions | Grid | Panel Size |
|----------|------|------------|
| 1 | 1x1 | 192 x 132 |
| 3 | 3x1 | 512 x 132 |
| 5 | 5x1 | 832 x 132 |
| 7 | 5x2 | 832 x 240 |
| 10 | 5x2 | 832 x 240 |
| 15 | 5x3 | 832 x 348 |

### 2D Navigation Model

```
Grid indices (5 columns):
  [ 0] [ 1] [ 2] [ 3] [ 4]
  [ 5] [ 6] [ 7] [ 8] [ 9]
  [10] [11] [12]

Arrow Right: index + 1 (clamp to last)
Arrow Left:  index - 1 (clamp to 0)
Arrow Down:  index + maxColumns (clamp to last)
Arrow Up:    index - maxColumns (clamp to 0)
```

---

## Directory Structure

```
app/
└── CCNotifyBar.swift          ← all new code added here
    ├── CCSession (existing)
    ├── CCNotifyBar (existing, modified)
    ├── HotKeyManager (new)
    ├── SessionSwitcherPanel (new)
    ├── CardGridView (new)
    ├── SessionCardView (new)
    └── Entry point (existing)
```

---

## Build Phases

### Phase 1: Global Hotkey
**Scope:** Register a system-wide hotkey that toggles a minimal empty panel (no content).
**Validates:** Carbon API works with .accessory activation policy. Hotkey fires reliably from any app.

```swift
// HotKeyManager — isolated Carbon wrapper
import Carbon

final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    var onToggle: (() -> Void)?

    func register(keyCode: UInt32 = 49, modifiers: UInt32 = UInt32(cmdKey | shiftKey)) {
        var hotKeyID = EventHotKeyID(signature: OSType(0x4343), id: 1) // "CC"
        RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Store self reference for C callback
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, refcon -> OSStatus in
            guard let refcon = refcon else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(refcon).takeUnretainedValue()
            DispatchQueue.main.async { manager.onToggle?() }
            return noErr
        }, 1, &eventType, refcon, nil)
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}
```

### Phase 2: Floating Panel Shell
**Depends on:** Phase 1
**Scope:** NSPanel with vibrancy, centered on active screen, fade in/out, dismiss on Escape and click-outside.
**Validates:** Panel appears above all windows, receives keyboard events, doesn't steal focus from terminal.

```swift
final class SessionSwitcherPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 420),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true
        )
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let vibrancy = NSVisualEffectView(frame: contentRect)
        vibrancy.autoresizingMask = [.width, .height]
        vibrancy.blendingMode = .behindWindow
        vibrancy.material = .hudWindow
        vibrancy.state = .active
        vibrancy.wantsLayer = true
        vibrancy.layer?.cornerRadius = 16
        vibrancy.layer?.masksToBounds = true
        contentView = vibrancy
    }

    override func cancelOperation(_ sender: Any?) { dismiss() }
    override func resignKey() { super.resignKey(); dismiss() }

    func showOnActiveScreen() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let sf = screen.visibleFrame
        setFrameOrigin(NSPoint(x: sf.midX - frame.width / 2,
                               y: sf.midY - frame.height / 2 + 80))
        alphaValue = 0
        orderFrontRegardless()
        makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.animator().alphaValue = 1
        }
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            self.animator().alphaValue = 0
        }, completionHandler: { self.orderOut(nil) })
    }
}
```

### Phase 3: Session Cards + Grid Layout
**Depends on:** Phase 2
**Scope:** Custom SessionCardView (160x100 tile) with project name, status dot, directory, timestamp, deterministic color. CardGridView arranges cards in rows of up to 5. Panel resizes dynamically based on session count.
**Validates:** Cards render correctly in grid, colors are visually distinct, status sorting works, panel sizes correctly for 1-15+ sessions.

```swift
// Deterministic color from project name
func colorForProject(_ name: String) -> NSColor {
    var hash: UInt64 = 5381
    for byte in name.utf8 {
        hash = ((hash &<< 5) &+ hash) &+ UInt64(byte)
    }
    let hue = CGFloat(hash % 360) / 360.0
    return NSColor(calibratedHue: hue, saturation: 0.55, brightness: 0.85, alpha: 1.0)
}

// Card layout (160x100, compact tile for grid):
// ┌──────────────────┐
// │ ● ProjectName    │  ← status dot + project name (bold)
// │                  │
// │ Status Title     │  ← latest event title (secondary)
// │ ~/Projects/foo   │  ← truncated directory (tertiary)
// │              2m  │  ← relative timestamp (corner)
// └──────────────────┘
//
// Background: subtle gradient from project color (left edge)
// Selected: brighter border + elevated background
```

### Phase 4: Keyboard Navigation
**Depends on:** Phase 3
**Scope:** 2D grid navigation with all four arrow keys. Enter confirms (dismiss + focus). Escape dismisses. Mouse click as alternative.
**Validates:** Full keyboard-driven flow works end-to-end in grid layout. Navigation wraps correctly at row boundaries and last row.

```swift
class CardGridView: NSView {
    var cards: [SessionCardView] = []
    var selectedIndex = 0
    let maxColumns = CardLayout.maxColumns
    var onConfirm: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let last = cards.count - 1
        guard last >= 0 else { return }

        switch event.keyCode {
        case 126: // Arrow Up
            select(max(0, selectedIndex - maxColumns))
        case 125: // Arrow Down
            select(min(last, selectedIndex + maxColumns))
        case 123: // Arrow Left
            select(max(0, selectedIndex - 1))
        case 124: // Arrow Right
            select(min(last, selectedIndex + 1))
        case 36:  // Enter
            onConfirm?(cards[selectedIndex].sessionId)
        case 53:  // Escape
            onDismiss?()
        default:
            super.keyDown(with: event)
        }
    }

    private func select(_ index: Int) {
        cards[selectedIndex].isSelected = false
        selectedIndex = index
        cards[selectedIndex].isSelected = true
    }
}
```

### Phase 5: Integration
**Depends on:** Phase 4
**Scope:** Wire HotKeyManager to CCNotifyBar. Panel toggle calls reload() to refresh sessions. Card confirmation calls existing focusSession logic. Panel auto-dismisses after focus.
**Validates:** Full end-to-end flow: hotkey > panel > select > focus > panel gone.

Integration points in CCNotifyBar:
1. `applicationDidFinishLaunching` — create HotKeyManager and SessionSwitcherPanel, register hotkey
2. `togglePanel()` — new method: if panel visible, dismiss; else reload sessions, populate cards, show panel
3. `onConfirm` callback — calls existing `focusSession` logic, then dismisses panel
4. `reload()` — existing method, unchanged; panel reads from `sessions` array

---

## Latency / Performance Budget

| Operation | Budget | Notes |
|-----------|--------|-------|
| Hotkey to panel visible | < 100ms | reload() + card build + fade-in start |
| Arrow key selection | < 16ms | Single needsDisplay on two cards (old + new) |
| Enter to terminal focus | < 200ms | Dismiss animation overlaps with AppleScript focus |
| Panel dismiss (fade) | 120ms | Non-blocking |

---

## Engineering Notes

_Empty -- to be filled during implementation._

---

## Open Questions

- [x] Default hotkey — *Resolved: Cmd+Shift+Space (keyCode 49, cmdKey | shiftKey). Good default.*
- [x] Panel sizing — *Resolved: Dynamic grid. Up to 5 cards across, then new rows. Panel resizes to fit.*
- [ ] becomesKeyOnlyIfNeeded: docs say set to false to receive key events, but need to verify this works with .nonactivatingPanel style mask.
- [x] Menubar behavior — *Resolved: Menubar keeps existing dropdown. Panel is hotkey-only. Two separate paths.*
