# Digital Twin -- Overstory

Last updated: 2026-04-04

The product is Overstory. This twin documents what exists in code today.

---

## System Topology

```
                         Claude Code Hooks
                        (Stop, Notification)
                               |
                               v
                      +------------------+
                      |  overstory.sh    |
                      |  Hook Handler    |
                      +--------+---------+
                               |
              +----------------+----------------+
              |                |                |
              v                v                v
     Terminal Adapters    Log Entry         State File
     (overstory-terminal-       (~/.overstory/    (~/.overstory/
      adapters.sh)        log/*.json)       state/*.json)
              |                |
              |                v
              |       +------------------+
              |       |  OverstoryBar     |
              |       |  (Menubar App)   |
              |       +--------+---------+
              |                |
              v                v
        OSC 9 / osascript   Ghostty AppleScript
        (Push Notification)  (Focus Engine)
```

## Product Loops

### Loop 1: Hook-to-Notification

1. Claude Code fires a hook event (Stop or Notification) with JSON on stdin
2. `overstory.sh` parses the event, determines notification title/body/sound
3. Terminal adapter detects the terminal kind (Ghostty, iTerm2, etc.) via `$TERM_PROGRAM`
4. For Ghostty: captures the terminal's stable ID by setting a title marker via OSC escape, then querying AppleScript
5. Writes a state file (`~/.overstory/state/{session_id}.json`) with full terminal context
6. Writes a log entry (`~/.overstory/log/{ts}-{session_id}.json`) for the menubar app
7. Sends a push notification: OSC 9 for Ghostty, `osascript display notification` for others

### Loop 2: Menubar Awareness

1. OverstoryBar watches `~/.overstory/log/` for filesystem changes (DispatchSource)
2. On change, debounces 300ms, then reloads all log JSON files
3. Deduplicates by session ID, keeping the latest event per session
4. Prunes entries older than 1 hour
5. Updates the menubar icon (bell with/without badge) and session count
6. Rebuilds the dropdown menu with session cards

### Loop 3: Click-to-Focus

1. Developer clicks a session in the menubar dropdown
2. OverstoryBar reads the state file for that session's Ghostty terminal ID and TTY
3. Attempts to focus via AppleScript: walks Ghostty windows > tabs > terminals to find the ID
4. If the stored ID is stale, re-captures by setting a title marker on the TTY and querying again
5. If all strategies fail, falls back to activating Ghostty.app

## Systems

### Hook Handler (`overstory.sh`)

**What it does:** Receives Claude Code hook events on stdin, extracts session context, persists state, and dispatches notifications.

**JTBD:** When Claude Code finishes a turn or needs approval, ensure the developer gets a notification and the system has enough context to focus the right terminal later.

**Current capabilities:**
- Parses `Stop` and `Notification` hook events (ignores all others)
- Maps notification types: `permission_prompt` (approval needed), `idle_prompt` (waiting for input), and generic
- Walks the process tree to find the session's TTY
- Writes both state files (for focus) and log files (for menubar)
- Distinct notification sounds per event type (Funk, Glass, default)

### Terminal Adapters (`overstory-terminal-adapters.sh`)

**What it does:** Abstracts terminal detection, context capture, focus, and notification delivery across terminal emulators.

**JTBD:** Provide a consistent interface for identifying which terminal a session lives in and focusing it later, regardless of terminal app.

**Current capabilities:**
- Detects terminal kind from `$TERM_PROGRAM` and `$TERM` environment variables
- Supports detection of: Ghostty, iTerm2, Terminal.app, WezTerm, kitty, Alacritty
- Ghostty-specific: captures stable terminal ID via title marker + AppleScript query
- Ghostty-specific: focuses terminal by walking windows/tabs/terminals via AppleScript
- Ghostty-specific: sends native desktop notifications via OSC 9
- Fallback focus: activates the app and sends a bell character to the TTY
- State files store terminal-specific IDs (Ghostty terminal ID, iTerm session ID, WezTerm pane, kitty window ID) but only Ghostty IDs are actively captured and used

### Menubar App (`OverstoryBar.swift`)

**What it does:** A native macOS menubar app that shows active Claude Code sessions and lets the developer focus any session with one click.

**JTBD:** When the developer has multiple Claude Code sessions running, provide ambient awareness of session count and a quick way to jump to any session.

**Current capabilities:**
- Compiled Swift binary, runs as a menubar accessory app (no dock icon)
- Bell icon in menubar, badged when sessions exist, with session count
- Dropdown menu listing sessions with: status icon, project name, latest title, relative timestamp
- Status icons: yellow circle (notification/needs attention), green circle (done), white circle (other)
- Click a session to focus its Ghostty terminal (same AppleScript focus logic as the shell scripts)
- Stale terminal ID recovery: re-captures via TTY title marker if the stored ID fails
- Filesystem watcher on `~/.overstory/log/` with 300ms debounce
- Auto-prunes log entries older than 1 hour
- Clear All (Cmd+K) to reset
- LaunchAgent for auto-start on login

### Focus Engine

**What it does:** Resolves a session ID to the correct terminal window/tab and brings it to the foreground.

**JTBD:** When the developer selects a session, switch to the exact terminal where that agent is running, not just the terminal app.

**Current capabilities:**
- Ghostty: AppleScript-based focus that walks windows > tabs > terminals by stable ID
- Ghostty: title-marker-based ID recovery when stored IDs go stale
- Fallback: `open -a {app}` + bell character on TTY
- State file stores IDs for iTerm2, WezTerm, kitty but focus logic is only implemented for Ghostty
- Implemented in both shell (overstory-terminal-adapters.sh) and Swift (OverstoryBar.swift) -- duplicated

## Actors

| Actor | Role |
|---|---|
| Developer | Runs multiple Claude Code sessions. Receives notifications. Clicks sessions to focus. |
| Claude Code | The CLI agent. Fires hook events (Stop, Notification) that trigger the system. |
| Ghostty | The terminal emulator. Hosts Claude Code sessions. Exposes AppleScript API for focus. Renders OSC 9 notifications. |
| macOS | Hosts the menubar, delivers notifications, runs the LaunchAgent. |

## Architecture

```
+------------------+     hook events (stdin JSON)     +------------------+
|   Claude Code    | -------------------------------->|  overstory.sh    |
|   (CLI Agent)    |                                  |  (Hook Handler)  |
+------------------+                                  +--------+---------+
                                                               |
                                                    +----------+----------+
                                                    |                     |
                                               state/*.json          log/*.json
                                                    |                     |
                                                    v                     v
                                            +-------+-------+    +-------+-------+
                                            | overstory-focus.sh   |    | OverstoryBar   |
                                            | (CLI Focus)   |    | (Menubar App) |
                                            +-------+-------+    +-------+-------+
                                                    |                     |
                                                    +----------+----------+
                                                               |
                                                               v
                                                    +----------+----------+
                                                    | Terminal Adapters   |
                                                    | (AppleScript/OSC)  |
                                                    +----------+----------+
                                                               |
                                                               v
                                                    +----------+----------+
                                                    |      Ghostty        |
                                                    | (Terminal Emulator) |
                                                    +---------------------+
```

## File Map

| File | Purpose |
|---|---|
| `scripts/overstory.sh` | Hook handler. Entry point from Claude Code hooks. |
| `scripts/overstory-focus.sh` | CLI focus script. Called with a session ID to focus that terminal. |
| `scripts/overstory-terminal-adapters.sh` | Terminal detection, context capture, focus, and notification abstractions. |
| `app/OverstoryBar.swift` | Native macOS menubar app. Single-file Swift binary. |
| `install.sh` | Installer. Copies scripts, compiles Swift app, configures CC hooks, sets up LaunchAgent. |
| `uninstall.sh` | Uninstaller. Removes hooks, LaunchAgent, and installed files. |
| `~/.overstory/log/*.json` | Log entries consumed by the menubar app. Ephemeral (pruned after 1 hour). |
| `~/.overstory/state/*.json` | Session state files with terminal context for focus. |
