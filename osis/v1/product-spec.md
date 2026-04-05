# Product Spec -- v1

## Overview

v1 delivers a macOS menubar app with a global-hotkey-activated floating panel that shows all running Claude Code sessions, their status, and lets the developer focus any session with keyboard or mouse. Ghostty is the supported terminal. Claude Code is the supported agent.

## User Stories

**P0 -- Must have:**

1. As a developer running 5+ Claude Code sessions, I want to press a global hotkey and see all my sessions so I can find the one that needs me without checking each tab.

2. As a developer, I want to see at a glance which sessions need approval, which are done, and which are still working, so I can prioritize my attention.

3. As a developer, I want to select a session from the panel and have the correct Ghostty window/tab focused immediately, so I do not waste time navigating tabs.

4. As a developer, I want a push notification when Claude needs approval or finishes a turn, so I can work on something else without polling.

5. As a developer, I want the panel to disappear after I select a session, so it does not obstruct my workflow.

**P1 -- Should have:**

6. As a developer, I want each session to have a distinct visual identity so I can quickly distinguish between projects.

7. As a developer, I want the app to start on login and run silently in the background, so I never have to think about launching it.

8. As a developer, I want to see the session's project directory and the agent's current title, so I have enough context to pick the right session.

**P2 -- Nice to have:**

9. As a developer, I want to use arrow keys and Enter to navigate the panel, so I never need to reach for the mouse.

10. As a developer, I want hovering/highlighting a card to preview that window (bring it forward briefly), so I can confirm it is the right one before committing.

## Systems

### Session Detection

Two complementary mechanisms detect active Claude Code sessions:

**Hooks (primary, rich data):**
- Claude Code fires `Stop` and `Notification` hook events with JSON on stdin.
- The hook handler (`cc-notify.sh`) parses the event, captures terminal context, and writes state + log files.
- Provides: session ID, project directory, event type, notification type, message, terminal kind, TTY, Ghostty terminal ID.

**Polling (baseline, no hooks required):**
- `pgrep` to find running `claude` processes.
- Walk the process tree to associate each process with a TTY.
- Query the terminal (AppleScript for Ghostty) to get window/tab context.
- Provides: session existence, TTY, terminal window association.
- Polling ensures the app works even if hooks are not configured, showing sessions without rich status data.

v1 ships hooks as the primary mechanism. Polling is a future hardening step to ensure sessions are never missed.

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

**Behavior:**
- Panel appears above all windows (floating window level).
- Clicking outside the panel dismisses it.
- If no sessions exist, shows an empty state message.

### Session Cards

Each card in the floating panel represents one Claude Code session.

**Content:**
- Project name (derived from the working directory basename).
- Agent title / latest status message from Claude Code.
- Working directory path (truncated, shown secondary).
- Status indicator with clear visual hierarchy:
  - **Needs approval:** urgent styling -- red/pulsing accent. Top-sorted.
  - **Turn complete:** green accent. Developer action likely.
  - **Working:** neutral, subtle animation (spinner or pulse). No action needed.
  - **Idle:** dimmed. No recent activity.

**Visual identity:**
- Each card has a unique gradient/color derived deterministically from the project name (similar to GitHub's default avatar generation).
- The gradient serves as a quick visual anchor -- developers learn to associate the color with the project.

**Sorting:**
- Sessions needing attention sort to the top (approval > complete > working > idle).
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
- Clicking a notification focuses the correct session (currently requires terminal-notifier for click callbacks; v1 relies on menubar/panel for focus).

### Menubar

The ambient status indicator. Secondary to the floating panel.

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
- Support any CLI agent other than Claude Code. The architecture accommodates others, but v1 only handles Claude Code hooks.
- Include polling-based session detection. v1 relies entirely on hooks for session awareness.
- Provide a settings UI. Configuration (hotkey, notification preferences) is future scope.
- Support Linux or Windows. macOS only.
- Replace the terminal. It is a switcher and notifier, not a multiplexer or terminal emulator.
- Persist session history. Log entries are pruned after 1 hour.

## Roadmap

### v1: Ghostty + Claude Code

- Menubar app with session list and focus.
- Floating panel with global hotkey (session switcher).
- Session cards with status, project, visual identity.
- Keyboard navigation (arrows + Enter).
- Ghostty-specific focus via AppleScript.
- Push notifications via OSC 9 and osascript.
- Claude Code hooks for rich status data.
- LaunchAgent for auto-start.
- Install/uninstall scripts.

### v2: Terminal-agnostic

- Polling-based session detection as a baseline (pgrep + process tree).
- iTerm2 adapter (AppleScript focus, session ID matching).
- WezTerm adapter (CLI-based focus).
- kitty adapter (remote control protocol).
- Terminal.app adapter (AppleScript).
- Settings UI for hotkey and notification preferences.

### v3: Multi-agent

- Support for Codex, Cursor agent, and other CLI agents.
- Agent-specific status parsing (each agent exposes status differently).
- Product rename to reflect the broader "session switcher for CLI agents" identity.
- Potential for cross-platform (Linux).
