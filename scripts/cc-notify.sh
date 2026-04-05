#!/usr/bin/env bash
set -euo pipefail

# cc-notify: Claude Code hook handler
# Sends macOS notifications on turn complete / approval needed.
# Reads hook JSON from stdin, detects terminal, sends notification.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/cc-terminal-adapters.sh"

STATE_DIR="$HOME/.cc-notify/state"
mkdir -p "$STATE_DIR"

shell_quote() {
  printf '%q' "$1"
}

# Read hook JSON from stdin
INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // "unknown"')
CWD=$(echo "$INPUT" | jq -r '.cwd // ""')
PROJECT=$(basename "$CWD")

# Event-specific fields
NOTIFICATION_TYPE=$(echo "$INPUT" | jq -r '.notification_type // ""')
MESSAGE=$(echo "$INPUT" | jq -r '.message // ""')

# Determine notification title and body
case "$EVENT" in
  Notification)
    case "$NOTIFICATION_TYPE" in
      permission_prompt)
        TITLE="Approval Needed"
        BODY="${MESSAGE:-Claude needs permission}"
        SOUND="Funk"
        ;;
      idle_prompt)
        TITLE="Waiting for Input"
        BODY="${MESSAGE:-Claude is waiting for you}"
        SOUND="default"
        ;;
      *)
        TITLE="Claude Code"
        BODY="${MESSAGE:-Notification}"
        SOUND="default"
        ;;
    esac
    ;;
  Stop)
    TITLE="Turn Complete"
    BODY="Claude finished in $PROJECT"
    SOUND="Glass"
    ;;
  *)
    # Ignore events we don't care about
    exit 0
    ;;
esac

# --- Detect terminal app ---
TERMINAL_KIND=$(cc_notify_detect_terminal_kind)
APP_NAME=$(cc_notify_app_name_for_kind "$TERMINAL_KIND")

# --- Find the TTY for this terminal session ---
# The hook's own stdin is a pipe (JSON), so we walk up the process tree
# to find a parent that owns a real TTY.
find_session_tty() {
  local pid=$$
  local max_depth=15
  local depth=0
  while [ "$pid" != "1" ] && [ -n "$pid" ] && [ "$depth" -lt "$max_depth" ]; do
    local tty
    tty=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ') || true
    if [ -n "$tty" ] && [ "$tty" != "??" ] && [ "$tty" != "-" ]; then
      echo "/dev/$tty"
      return
    fi
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ') || break
    depth=$((depth + 1))
  done
  echo ""
}

TTY_PATH=$(find_session_tty)
cc_notify_capture_context "$TERMINAL_KIND" "$CWD" "$TTY_PATH" "$PROJECT" "$SESSION_ID"

# --- Save session state for the focus script ---
jq -cn \
  --arg app "$APP_NAME" \
  --arg terminal_kind "$TERMINAL_KIND" \
  --arg tty "$TTY_PATH" \
  --arg cwd "$CWD" \
  --arg project "$PROJECT" \
  --arg event "$EVENT" \
  --arg focus_capability "${CC_NOTIFY_FOCUS_CAPABILITY:-fallback}" \
  --arg term_program "${TERM_PROGRAM:-}" \
  --arg term "${TERM:-}" \
  --arg term_program_version "${TERM_PROGRAM_VERSION:-}" \
  --arg iterm_session_id "${ITERM_SESSION_ID:-}" \
  --arg wezterm_pane_id "${WEZTERM_PANE:-}" \
  --arg kitty_window_id "${KITTY_WINDOW_ID:-}" \
  --arg ghostty_terminal_id "${CC_NOTIFY_GHOSTTY_TERMINAL_ID:-}" \
  --argjson ts "$(date +%s)" \
  '{
    app: $app,
    terminal_kind: $terminal_kind,
    tty: $tty,
    cwd: $cwd,
    project: $project,
    event: $event,
    focus_capability: $focus_capability,
    term_program: $term_program,
    term: $term,
    term_program_version: $term_program_version,
    iterm_session_id: $iterm_session_id,
    wezterm_pane_id: $wezterm_pane_id,
    kitty_window_id: $kitty_window_id,
    ghostty_terminal_id: $ghostty_terminal_id,
    ts: $ts
  }' \
  > "$STATE_DIR/$SESSION_ID.json"

# --- Write log entry for menubar app ---
LOG_DIR="$HOME/.cc-notify/log"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date +%s)-${SESSION_ID}.json"
jq -cn \
  --arg session_id "$SESSION_ID" \
  --arg title "$TITLE" \
  --arg body "$BODY" \
  --arg project "$PROJECT" \
  --arg event "$EVENT" \
  --arg terminal_kind "$TERMINAL_KIND" \
  --argjson ts "$(date +%s)" \
  '{session_id:$session_id,title:$title,body:$body,project:$project,event:$event,terminal_kind:$terminal_kind,ts:$ts}' \
  > "$LOG_FILE"

# --- Send notification ---
# For Ghostty: use OSC 9 (native desktop notification via the terminal).
# For other terminals: use osascript display notification.
if [ "$TERMINAL_KIND" = "ghostty" ] && [ -n "$TTY_PATH" ] && [ -w "$TTY_PATH" ]; then
  cc_notify_send_ghostty_notification "$TTY_PATH" "$TITLE: $BODY" &
else
  osascript - "$TITLE" "$BODY" "$PROJECT" "$SOUND" <<'APPLESCRIPT' &
on run argv
  display notification (item 2 of argv) with title (item 1 of argv) subtitle (item 3 of argv) sound name (item 4 of argv)
end run
APPLESCRIPT
fi

exit 0
