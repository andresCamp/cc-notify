# Overstory

Overstory is a macOS attention layer for Claude Code sessions, starting with Ghostty.

Today the repo ships:
- Claude Code hook handlers for notifications and session-state capture
- A menubar app that lists recent sessions and can focus them
- A Ghostty-first focus engine with fallbacks for less capable terminals

The floating hotkey panel is the Phase 1 target described in [`osis/v1`](./osis/v1), but it is not implemented in the app code yet.

## Current Behavior

When Claude Code fires a `Stop` or `Notification` hook, Overstory:
1. Reads the hook payload from `stdin`
2. Detects terminal context and session TTY
3. Captures focus-related identifiers
4. Writes per-session state to `~/.overstory/state/<session_id>.json`
5. Writes a recent log entry to `~/.overstory/log/`
6. Sends a macOS notification

The menubar app reads those recent log entries and lets you focus a session from the menu.

## Focus Behavior

Ghostty is the best-supported terminal today.

The current Ghostty focus path is:
1. Use the stored Ghostty terminal ID when available
2. Re-capture the terminal ID by writing a temporary title marker to the session TTY
3. Focus the matching Ghostty terminal via AppleScript
4. Fall back to activating Ghostty if exact focus fails

Other terminals currently fall back to app activation and whatever saved terminal context is available.

## Files

- `install.sh`: installs scripts, configures Claude Code hooks, and builds the menubar app when `swiftc` is available
- `uninstall.sh`: removes installed files and Claude hook entries
- `scripts/overstory.sh`: Claude Code hook entrypoint
- `scripts/overstory-focus.sh`: focus helper for a saved session ID
- `scripts/overstory-terminal-adapters.sh`: terminal detection, context capture, and focus logic
- `app/OverstoryBar.swift`: menubar app

## Installation

Requirements:
- macOS
- `jq`
- `swiftc` if you want the menubar app compiled locally

Install:

```bash
bash install.sh
```

The installer copies scripts into `~/.overstory/` and updates `~/.claude/settings.json` to register the `Stop` and `Notification` hooks.

## Limits

- The floating panel switcher is specified in OSIS but not yet implemented in the app code.
- Exact focus is only fully supported for Ghostty.
- Overstory currently shows recent hook-visible sessions, not all running sessions.
- True runtime `working` and `idle` status are future work.
- Notification-click focus is future work; the current focus paths are the menubar app and internal focus helpers.

## Roadmap

- Implement the hotkey floating panel in `osis/v1`
- Add runtime discovery for all running sessions
- Add more terminal adapters
- Expand beyond Claude Code to other CLI agents
