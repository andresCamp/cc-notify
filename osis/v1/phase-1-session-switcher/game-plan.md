# Phase 1 Game Plan -- Session Switcher

**Goal:** Deliver the floating panel session switcher with global hotkey, keyboard navigation, and visual session cards for recent hook-visible Claude Code sessions.
**Target date:** TBD
**Status:** Not started

---

## 1. What This Phase Accomplishes

After this phase, the developer can press a global hotkey and see recent Claude Code sessions that have emitted hook events in a floating panel. They navigate with arrow keys and Enter to focus the correct Ghostty terminal instantly. The panel disappears on selection. This replaces tab-cycling as the primary way to reach recent attention-worthy sessions.

The existing menubar app and notification system continue to work. The floating panel is additive.

---

## 2. Constraints

- **Timeline:** Solo developer, no hard deadline
- **Resources:** Single-file Swift app pattern (`OverstoryBar.swift`) -- extend, don't rewrite
- **Dependencies:** Existing hook handler, state/log files, and Ghostty focus logic are already in place
- **Platform:** macOS only, Ghostty only (per v1 product spec)
- **Detection source:** Hook-backed recent log/state files only for Phase 1

---

## 3. Systems

| System | Type | Description |
|--------|------|-------------|
| Floating Panel | New | Global-hotkey-activated session switcher window |
| Session Cards | New | Visual card views with status, project color, sorting |
| Keyboard Navigation | New | Grid navigation with arrows + Enter + Escape |
| Global Hotkey | New | System-wide shortcut to toggle the panel |
| Focus Engine | Changed | Existing Ghostty focus path triggered from panel selection |
| Session Projection | Changed | `reload()` parses normalized hook logs into panel sessions |

---

## 4. What Ships

| Component | Tier | System | Notes |
|-----------|------|--------|-------|
| Global hotkey registration | T1 | Global Hotkey | Carbon `RegisterEventHotKey` |
| Floating `NSPanel` with vibrancy | T1 | Floating Panel | Borderless, centered on the interaction screen |
| Session card views | T1 | Session Cards | Project, latest title, directory, timestamp, status |
| Normalized status sorting | T1 | Session Cards | needs approval > waiting for input > turn complete > informational |
| Grid keyboard navigation | T1 | Keyboard Navigation | Left/Right row-sticky, Up/Down column-preserving |
| Hook log contract update | T1 | Session Projection | Add `cwd`, `notification_type`, and normalized `status` |
| Deterministic project colors | T2 | Session Cards | Hash-to-HSL from project name |
| Click-outside dismiss | T2 | Floating Panel | Panel resigns key and dismisses |
| Fade in/out animation | T2 | Floating Panel | 120-150ms transitions |
| Mouse click on cards | T2 | Keyboard Navigation | Click as alternative to Enter |

---

## 5. What Does NOT Ship

| Deferred Item | Reason | Revisit In |
|---------------|--------|------------|
| Runtime discovery of all running sessions | Not implemented in the current architecture | Phase 2 |
| True `working` / `idle` runtime status | Requires runtime discovery or another active signal | Phase 2 |
| Window preview on hover | Extra focus complexity | Phase 2 |
| Configurable hotkey | No settings UI in v1 | Phase 2 |
| Settings UI | Out of v1 scope | Phase 2 |

---

## 6. Success Criteria

- [ ] Global hotkey toggles the panel from any app
- [ ] Panel shows recent hook-visible sessions from log files with normalized status
- [ ] Every card can show a real working directory when the hook provided one
- [ ] Arrow keys move selection according to the grid navigation rules, and Enter focuses the terminal
- [ ] Escape and click-outside dismiss the panel
- [ ] Panel appears on the screen containing the current mouse pointer, above all windows
- [ ] Existing menubar and notifications continue working

---

## 7. Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Carbon hotkey API deprecated | Could break in a future macOS release | Monitor Apple releases; keep fallback options in reserve |
| `NSPanel` keyboard focus in accessory mode | Panel might not receive key events reliably | Activate the app on show, make the panel key, make the grid first responder, and use `NSPanel` key behavior deliberately |
| Hook log contract drift | Panel sorts or renders incorrect data | Normalize `status` and required fields in the hook script before UI work begins |
| Single-file Swift app getting too large | Harder to maintain | Accept for Phase 1; split in a later refactor if needed |

---

## 8. Open Questions

- [x] Default hotkey -- *Resolved: Cmd+Shift+Space.*
- [x] Panel size -- *Resolved: Dynamic grid, up to 5 columns, rows wrap.*
- [x] Menubar behavior -- *Resolved: Menubar keeps dropdown, panel is hotkey-only.*
- [x] Auto-dismiss after focus -- *Resolved: Yes. Confirm dismisses the panel.*
- [x] Screen placement -- *Resolved: Use the screen containing the current mouse pointer.*
