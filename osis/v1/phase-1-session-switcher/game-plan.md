# Phase 1 Game Plan -- Session Switcher

**Goal:** Deliver the floating panel session switcher with global hotkey, keyboard navigation, and visual session cards -- the core interaction model described in the vision.
**Target date:** TBD
**Status:** Not started

---

## 1. What This Phase Accomplishes

After this phase, the developer can press a global hotkey and see all running Claude Code sessions in a floating panel. They navigate with arrow keys and Enter to focus the correct Ghostty terminal instantly. The panel disappears on selection. This replaces tab-cycling as the primary way to find a session.

The existing menubar app and notification system continue to work. The floating panel is additive.

---

## 2. Constraints

- **Timeline:** Solo developer, no hard deadline
- **Resources:** Single-file Swift app pattern (CCNotifyBar.swift) -- extend, don't rewrite
- **Dependencies:** Existing hook handler, state/log files, and Ghostty focus logic are all in place
- **Platform:** macOS only, Ghostty only (per v1 product spec)

---

## 3. Systems

| System | Type | Description |
|--------|------|-------------|
| Floating Panel | New | Global-hotkey-activated session switcher window |
| Session Cards | New | Visual card views with status, project color, sorting |
| Keyboard Navigation | New | Arrow keys + Enter + Escape within the panel |
| Global Hotkey | New | System-wide shortcut to toggle the panel |
| Focus Engine | Changed | Already built -- now triggered from panel selection |

---

## 4. What Ships

| Component | Tier | System | Notes |
|-----------|------|--------|-------|
| Global hotkey registration | T1 | Global Hotkey | Carbon RegisterEventHotKey |
| Floating NSPanel with vibrancy | T1 | Floating Panel | Borderless, centered, Spotlight-style |
| Session card views | T1 | Session Cards | Project name, status, directory, color |
| Status-based sorting | T1 | Session Cards | Approval > complete > working > idle |
| Arrow key navigation | T1 | Keyboard Navigation | Up/Down/Enter/Escape |
| Deterministic project colors | T2 | Session Cards | Hash-to-HSL from project name |
| Click-outside dismiss | T2 | Floating Panel | resignKey triggers dismiss |
| Fade in/out animation | T2 | Floating Panel | 150ms ease transitions |
| Mouse click on cards | T2 | Keyboard Navigation | Click as alternative to Enter |

---

## 5. What Does NOT Ship

| Deferred Item | Reason | Revisit In |
|---------------|--------|------------|
| Configurable hotkey | No settings UI in v1 | Phase 2 |
| Window preview on hover | Complex, P2 in product spec | Phase 2 |
| Polling-based session detection | v1 relies on hooks per product spec | v2 |
| Settings UI | Out of v1 scope | v2 |

---

## 6. Success Criteria

- [ ] Global hotkey toggles the panel from any app
- [ ] Panel shows all sessions from log files with correct status
- [ ] Arrow keys move selection, Enter focuses the terminal
- [ ] Escape and click-outside dismiss the panel
- [ ] Panel appears on the active screen, above all windows
- [ ] Existing menubar and notifications continue working

---

## 7. Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Carbon hotkey API deprecated | Could break in future macOS | Monitor Apple releases; NSEvent.addGlobalMonitorForEvents as fallback (requires Accessibility permission) |
| NSPanel keyboard focus with .accessory policy | Panel might not receive key events | Set becomesKeyOnlyIfNeeded=false, makeFirstResponder explicitly |
| Single-file Swift app getting too large | Harder to maintain | Accept for v1; restructure in v2 if needed |

---

## 8. Open Questions

- [x] Default hotkey -- *Resolved: Cmd+Shift+Space.*
- [x] Panel size -- *Resolved: Dynamic grid, up to 5 columns, rows wrap.*
- [x] Menubar behavior -- *Resolved: Menubar keeps dropdown, panel is hotkey-only.*
- [ ] Should the panel auto-dismiss after focus, or should the developer explicitly dismiss?
