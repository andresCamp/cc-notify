# cc-notify

`cc-notify` sends macOS notifications for Claude Code sessions so you notice when a turn finishes or when Claude is waiting on you.

The project is designed for people running many Claude Code sessions in parallel. The goal is simple: reduce the time between "Claude is blocked" and "you noticed."

## What It Does

- Sends a notification when a Claude Code turn stops.
- Sends a notification when Claude Code asks for approval or input.
- Stores per-session state so a notification click can try to bring you back to the originating terminal session.
- Uses terminal-specific focus adapters where possible, with a generic fallback when exact focus is not available.

## How It Works

Claude Code hooks execute inside the same process tree as the running session. Because of that, the hook script inherits terminal-related environment from the session that triggered it.

At hook time, `cc-notify`:

1. Reads the Claude Code hook payload from `stdin`.
2. Detects the terminal from inherited environment such as `TERM_PROGRAM` and `TERM`.
3. Walks up the process tree to find the session TTY.
4. Captures any adapter-specific context it can.
5. Writes that state to `~/.cc-notify/state/<session_id>.json`.
6. Sends a macOS notification.

When you click the notification, `cc-focus.sh` loads the saved state and asks the terminal adapter to focus the originating session.

## Current Terminal Support

### Ghostty

Ghostty is the first terminal with a real adapter.

The adapter uses Ghostty's macOS AppleScript dictionary, which exposes:

- windows
- tabs
- terminals
- stable terminal IDs
- terminal working directories
- a `focus` command on terminals

Current Ghostty strategy:

1. At hook time, write an invisible per-session marker into the Ghostty surface title.
2. Also try to capture a stable Ghostty terminal ID when `cwd` matching is unique.
3. On notification click, first look for the invisible title marker and focus that exact Ghostty surface.
4. If marker-based focus fails, try focusing by the captured Ghostty terminal ID.
5. If that also fails, try again by working directory.
6. If all Ghostty-specific strategies fail, fall back to generic app activation plus TTY bell.

The title marker path is the main strategy because it does not depend on `cwd` uniqueness. The `cwd` path remains a weaker fallback.

### Other Terminals

The adapter framework is in place for additional terminals, but most currently use the generic fallback path.

Stored state already includes common terminal-specific fields so future adapters can use them:

- `ITERM_SESSION_ID`
- `WEZTERM_PANE`
- `KITTY_WINDOW_ID`
- `TERM_PROGRAM`
- `TERM_PROGRAM_VERSION`

Fallback behavior:

- activate the terminal app
- write a bell to the saved TTY if possible

That fallback is useful, but it does not guarantee exact tab or pane selection.

## Why An Adapter Pattern Is Needed

macOS notifications can activate an app or run a command when clicked. They do not know how to focus an arbitrary terminal tab or pane.

Exact focus is terminal-specific because each terminal has its own:

- object model
- automation API
- shell environment variables
- window/tab/pane identifiers

That is why `cc-notify` splits the problem into:

- a generic notification layer
- a terminal adapter layer

Each adapter has two responsibilities:

- `capture_context`: collect stable identifiers at hook time
- `focus_context`: use those identifiers when the notification is clicked

## Files

- `install.sh`: installs the scripts and registers Claude Code hooks.
- `uninstall.sh`: removes installed files and strips `cc-notify` hooks from Claude settings.
- `scripts/cc-notify.sh`: Claude Code hook entrypoint.
- `scripts/cc-focus.sh`: click handler for notifications.
- `scripts/cc-terminal-adapters.sh`: terminal detection, adapter capture, and focus logic.

## Installation

Requirements:

- macOS
- `jq`
- `terminal-notifier` for click-to-focus behavior

Install:

```bash
bash install.sh
```

The installer copies scripts into:

```text
~/.cc-notify/
```

and updates:

```text
~/.claude/settings.json
```

to register `Stop` and `Notification` hooks.

## Uninstall

```bash
bash uninstall.sh
```

This removes installed scripts and removes `cc-notify` hook entries from Claude Code settings.

## State Format

Each session writes a state file at:

```text
~/.cc-notify/state/<session_id>.json
```

Typical fields include:

- `app`
- `terminal_kind`
- `tty`
- `cwd`
- `project`
- `event`
- `focus_capability`
- `term_program`
- `term_program_version`
- `iterm_session_id`
- `wezterm_pane_id`
- `kitty_window_id`
- `ghostty_terminal_id`
- `ghostty_title_marked`
- `ts`

## Notifications

Current events handled:

- `Stop`
- `Notification`

Current notification mapping:

- `Notification` + `permission_prompt` -> "Approval Needed"
- `Notification` + `idle_prompt` -> "Waiting for Input"
- `Stop` -> "Turn Complete"

## Limits

- Exact focus is not universal yet.
- Ghostty exact focus now prefers a per-session title marker, but still falls back when Ghostty scripting is unavailable or when the marker is lost.
- If multiple sessions share the same terminal app and same `cwd`, fallback behavior may only bring the app forward and ring the correct TTY.
- `osascript` notifications work without click actions, but click-to-focus requires `terminal-notifier`.

## Roadmap

- Add real adapters for iTerm2, WezTerm, kitty, and Terminal.app.
- Improve Ghostty capture so it does not rely on `cwd` uniqueness.
- Add runtime diagnostics so users can see which adapter path was used for a given click.
- Add an automated test harness around state capture and focus dispatch.
