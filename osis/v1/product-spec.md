# Product Spec -- v1

## Overview

Overstory v1 delivers a macOS app with a global-hotkey floating panel as the primary interface. The panel shows recent hook-visible Claude Code sessions, their latest attention state, and lets the developer focus a session with keyboard or mouse. Ghostty is the supported terminal. Claude Code is the supported agent. The menubar provides secondary, ambient status.

## User Stories

**P0 -- Must have:**

1. As a developer running many Claude Code sessions, I want to press a global hotkey and see recent sessions that have emitted hook events, so I can find the one that needs me without checking each tab.

2. As a developer, I want to see at a glance which sessions need approval, are waiting for input, or just completed, so I can prioritize my attention.

3. As a developer, I want to select a session from the panel and have the correct Ghostty window/tab focused immediately, so I do not waste time navigating tabs.

4. As a developer, I want a push notification when Claude needs approval or finishes a turn, so I can work on something else without polling.

5. As a developer, I want the panel to disappear after I select a session, so it does not obstruct my workflow.

6. As a developer, I want each session card to have a unique visual identity derived from the project name, so I can quickly distinguish between projects at a glance.

7. As a developer, I want to use arrow keys and Enter to navigate the panel, so I never need to reach for the mouse.

**P1 -- Should have:**

8. As a developer, I want the panel to appear on the screen I am interacting with, so it opens where my attention already is.

9. As a developer, I want the app to start on login and run silently in the background, so I never have to think about launching it.

10. As a developer, I want to see the project name, latest attention title, and working directory on each card, so I have enough context to pick the right session.

**P2 -- Nice to have:**

11. As a developer, I want the menubar to show a badge and session count as ambient awareness when I am not using the panel.

12. As a developer, I want hovering or highlighting a card to preview that window, so I can confirm it is the right one before committing.

## Systems

### Session Detection

v1 uses Claude Code hooks as the session discovery baseline.

**Hooks (baseline):**
- Claude Code fires `Stop` and `Notification` hook events with JSON on stdin.
- The hook handler (`overstory.sh`) parses the event, captures terminal context, and writes state + log files.
- Provides: session ID, event type, notification type, message title/body, working directory, project name, terminal kind, TTY, Ghostty terminal ID, timestamp.
- A session becomes visible to Overstory after at least one qualifying hook event has been written.

**Retention model:**
- Recent session logs are kept for 1 hour.
- The panel and menubar read from those recent log entries.
- State files are used to enrich focus, not to discover sessions on their own.

**Future runtime discovery:**
- A later version may add `pgrep` + process-tree walking + Ghostty queries to discover all running sessions and infer true `working` / `idle` runtime state.

### Floating Panel (Session Switcher)

The primary interface. A borderless, floating window that appears on a global hotkey and disappears on selection or Escape.

**Activation:**
- Global hotkey, default `Cmd+Shift+Space`.
- Hotkey toggles the panel: press to open, press again to dismiss.

**Layout:**
- Centered on the interaction screen, defined as the screen containing the current mouse pointer.
- Grid layout, up to 5 columns, with rows wrapping as needed.
- Translucent background with vibrancy (`NSVisualEffectView`), similar to Spotlight or Cmd+Tab.
- No title bar, no resize handles, no dock presence.

**Navigation:**
- Arrow Left/Right move within the current row.
- Arrow Up/Down move between rows while preserving column intent.
- Enter confirms selection: dismiss panel, focus the selected session's terminal.
- Escape dismisses without action.
- Mouse click on a card selects it.
- Hover may highlight the card visually. Window preview is future scope.

**Behavior:**
- Panel appears above normal windows.
- Clicking outside the panel dismisses it.
- If no recent hook-visible sessions exist, shows an empty state message.

### Session Cards

Each card in the floating panel represents one recent hook-visible Claude Code session.

**Content:**
- Project name (derived from the working directory).
- Working directory path (truncated, shown secondary).
- Latest attention title from the most recent hook event.
- Relative timestamp.
- Status indicator with clear visual hierarchy:
  - **Needs approval:** urgent styling, red accent. Top-sorted. The session is blocked on the developer.
  - **Waiting for input:** amber accent. Claude is waiting for the developer.
  - **Turn complete:** green accent. Claude finished a turn; developer action is likely.
  - **Informational:** neutral styling. Recent activity exists, but no stronger attention state applies.

**Visual identity:**
- Each card has a unique gradient/blur derived deterministically from the project name.
- The gradient serves as a quick visual anchor developers learn to associate with the session.

**Sorting:**
- Sessions needing attention sort to the top: needs approval > waiting for input > turn complete > informational.
- Within the same status tier, sort by most recent event.

### Focus Engine

Translates "focus this session" into the correct terminal-level action.

**Ghostty (v1):**
1. Read the session's state file for the Ghostty terminal ID.
2. AppleScript: walk Ghostty windows > tabs > terminals, match by ID.
3. Activate the window, select the tab, focus the terminal.
4. If the ID is stale, re-capture by setting a title marker on the TTY and querying AppleScript again.
5. If all strategies fail, activate Ghostty.app as a fallback.

**Architecture:**
- Terminal adapters are a defined abstraction (`overstory-terminal-adapters.sh` today, a Swift protocol in the future).
- Each adapter implements: detect, capture context, focus, send notification.
- v1 ships Ghostty as the only fully-implemented adapter. Others are detected but fall back to app activation.

### Notification System

Push notifications alert the developer to high-priority events when they are not looking at the panel.

**Events:**
- `Notification/permission_prompt`: "Approval Needed" -- Claude needs permission to proceed. Sound: Funk.
- `Notification/idle_prompt`: "Waiting for Input" -- Claude is waiting for the developer. Sound: default.
- `Stop`: "Turn Complete" -- Claude finished in {project}. Sound: Glass.

**Delivery:**
- Ghostty: OSC 9 escape sequence written to the session's TTY. Rendered as a native Ghostty desktop notification.
- Other terminals: `osascript display notification` (macOS native).

**Future:**
- Clicking a notification focuses the correct session. v1 relies on the menubar and floating panel for focus.

### Menubar

Secondary, ambient status indicator. Not the primary interface.

**Icon:**
- System bell icon (SF Symbols). Badged when recent sessions exist.
- Session count displayed next to the icon when sessions are active.

**Dropdown:**
- Lists recent hook-visible sessions with: status icon, project name, latest title, relative timestamp.
- Click a session to focus it.
- Clear All (Cmd+K) to dismiss all notifications.
- Quit option.

**Behavior:**
- No dock icon. The app runs as a menubar-only accessory.
- LaunchAgent ensures it starts on login.

## Constraints

v1 does NOT:
- Support any terminal other than Ghostty for full focus functionality. Other terminals are detected but focus falls back to app activation.
- Support any CLI agent other than Claude Code. The architecture accommodates others, but v1 only handles Claude Code.
- Provide a settings UI. Configuration is future scope.
- Support Linux or Windows. macOS only.
- Replace the terminal. It is a switcher and notifier, not a multiplexer or terminal emulator.
- Show all running sessions. It only shows recent sessions that have emitted hook events within the retention window.
- Detect true `working` or `idle` runtime state.
- Persist session history beyond the recent log window.
- Provide notification-click focus.

## Roadmap

### v1: Ghostty + Claude Code

- Floating panel with global hotkey as the primary interface (session switcher).
- Hook-backed session detection via Claude Code `Stop` and `Notification` events.
- Session cards with project name, directory, latest attention title, status, and unique visual identity.
- Status hierarchy: needs approval > waiting for input > turn complete > informational.
- Keyboard navigation (arrows + Enter), click selection, and dismiss behavior.
- Ghostty-specific focus via AppleScript.
- Push notifications via OSC 9 and `osascript`.
- Menubar with ambient session count and badge.
- LaunchAgent for auto-start.
- Install/uninstall scripts.

### v2: Broader session discovery

- Runtime discovery for all running sessions via process inspection and terminal queries.
- True `working` and `idle` runtime states.
- Hover-to-preview window behavior.
- iTerm2 adapter (AppleScript focus, session ID matching).
- WezTerm adapter (CLI-based focus).
- kitty adapter (remote control protocol).
- Terminal.app adapter (AppleScript).
- Settings UI for hotkey and notification preferences.

### v3: Multi-agent

- Support for Codex, Cursor agent, and other CLI agents.
- Agent-specific status parsing.
- Potential for cross-platform support.
