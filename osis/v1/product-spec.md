# Product Spec -- v1

## Overview

Overstory v1 delivers a macOS app with a global-hotkey-activated floating panel as the primary interface. The panel shows all running Claude Code sessions, their status, and lets the developer focus any session with keyboard or mouse. Ghostty is the supported terminal. Claude Code is the supported agent. The menubar provides secondary, ambient status.

## User Stories

**P0 -- Must have:**

1. As a developer running 5+ Claude Code sessions, I want to press a global hotkey and see all my sessions so I can find the one that needs me without checking each tab.

2. As a developer, I want to see at a glance which sessions need approval, which are done, and which are still working, so I can prioritize my attention.

3. As a developer, I want to select a session from the panel and have the correct Ghostty window/tab focused immediately, so I do not waste time navigating tabs.

4. As a developer, I want a push notification when Claude needs approval or finishes a turn, so I can work on something else without polling.

5. As a developer, I want the panel to disappear after I select a session, so it does not obstruct my workflow.

6. As a developer, I want each session card to have a unique visual identity (gradient derived from the title) so I can quickly distinguish between projects at a glance.

7. As a developer, I want to use arrow keys and Enter to navigate the panel, so I never need to reach for the mouse.

**P1 -- Should have:**

8. As a developer, I want hovering or highlighting a card to preview that window (bring it forward briefly), so I can confirm it is the right one before committing.

9. As a developer, I want the app to start on login and run silently in the background, so I never have to think about launching it.

10. As a developer, I want to see the session's CC title and working directory on each card, so I have enough context to pick the right session.

**P2 -- Nice to have:**

11. As a developer, I want the menubar to show a badge and session count as ambient awareness when I am not using the panel.

## Systems

### Session Detection

Two complementary mechanisms detect active Claude Code sessions:

**Polling (baseline, always-on):**
- `pgrep` to find running `claude` processes.
- Walk the process tree to associate each process with a TTY.
- Query Ghostty via AppleScript to get window/tab context and terminal names.
- Provides: session existence, TTY, terminal window association, CC title (from Ghostty terminal name), working directory.
- Polling ensures the app always finds sessions without any developer configuration.

**Hooks (enrichment, richer status):**
- Claude Code fires `Stop` and `Notification` hook events with JSON on stdin.
- The hook handler (`cc-notify.sh`) parses the event, captures terminal context, and writes state + log files.
- Provides: session ID, event type, notification type, message, terminal kind, TTY, Ghostty terminal ID.
- Hooks layer richer status data on top of what polling discovers.

v1 ships polling as the baseline detection mechanism. Hooks enrich sessions with detailed status when configured.

### Floating Panel (Session Switcher)

The primary interface. A borderless, floating window that appears on a global hotkey and disappears on selection or Escape.

**Activation:**
- Global hotkey (configurable, default TBD -- something in the Cmd+Shift or Hyper key space).
- Hotkey toggles the panel: press to open, press again to dismiss.

**Layout:**
- Centered on the active screen, vertically stacked session cards.
- Translucent background with vibrancy (NSVisualEffectView), similar to Spotlight or Cmd+Tab.
- No title bar, no resize handles, no dock presence.

**Navigation:**
- Arrow Up/Down to move selection between cards.
- Enter to confirm selection: dismiss panel, focus the selected session's terminal.
- Escape to dismiss without action.
- Mouse click on a card to select.
- Hovering or highlighting a card previews the window by focusing it temporarily.

**Behavior:**
- Panel appears above all windows (floating window level).
- Clicking outside the panel dismisses it.
- If no sessions exist, shows an empty state message.

### Session Cards

Each card in the floating panel represents one Claude Code session.

**Content:**
- CC title (from the Ghostty terminal name -- this is what Claude Code sets as its working title).
- Working directory path (truncated, shown secondary).
- Status indicator with clear visual hierarchy:
  - **Needs approval:** urgent styling -- red/pulsing accent. Top-sorted. The session is blocked on the developer.
  - **Turn complete:** green accent. Claude finished; developer action likely.
  - **Working:** neutral, subtle animation (spinner or pulse). Claude is actively running.
  - **Idle:** dimmed. No recent activity.

**Visual identity:**
- Each card has a unique gradient/blur derived deterministically from the CC title.
- The gradient serves as a quick visual anchor -- developers learn to associate the color pattern with the session.

**Sorting:**
- Sessions needing attention sort to the top: needs approval > turn complete > working > idle.
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
- Terminal adapters are a defined abstraction (`cc-terminal-adapters.sh` today, a Swift protocol in the future).
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
- Clicking a notification focuses the correct session (currently requires terminal-notifier for click callbacks; v1 relies on the panel for focus).

### Menubar

Secondary, ambient status indicator. Not the primary interface.

**Icon:**
- System bell icon (SF Symbols). Badged when sessions with notifications exist.
- Session count displayed next to the icon when sessions are active.

**Dropdown:**
- Lists all active sessions with: status icon, project name, latest title, relative timestamp.
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
- Provide a settings UI. Configuration (hotkey, notification preferences) is future scope.
- Support Linux or Windows. macOS only.
- Replace the terminal. It is a switcher and notifier, not a multiplexer or terminal emulator.
- Persist session history. Log entries are pruned after 1 hour.

## Roadmap

### v1: Ghostty + Claude Code

- Floating panel with global hotkey as the primary interface (session switcher).
- Polling-based session detection (pgrep + Ghostty AppleScript) as baseline.
- Session cards with CC title, directory, status, and unique visual identity (gradient from title).
- Status hierarchy: needs approval > turn complete > working > idle.
- Keyboard navigation (arrows + Enter), hover/highlight previews.
- Ghostty-specific focus via AppleScript.
- Claude Code hooks for enriched status data.
- Push notifications via OSC 9 and osascript.
- Menubar with ambient session count and badge.
- LaunchAgent for auto-start.
- Install/uninstall scripts.

### v2: Terminal-agnostic

- iTerm2 adapter (AppleScript focus, session ID matching).
- WezTerm adapter (CLI-based focus).
- kitty adapter (remote control protocol).
- Terminal.app adapter (AppleScript).
- Settings UI for hotkey and notification preferences.

### v3: Multi-agent

- Support for Codex, Cursor agent, and other CLI agents.
- Agent-specific status parsing (each agent exposes status differently).
- Potential for cross-platform (Linux).
