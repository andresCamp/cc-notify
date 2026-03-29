#!/usr/bin/env bash
set -euo pipefail

# cc-focus: Bring the correct terminal window to front when a notification is clicked.
# Called by terminal-notifier's -execute flag with a session ID.

SESSION_ID="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/cc-terminal-adapters.sh"

STATE_DIR="$HOME/.cc-notify/state"
STATE_FILE="$STATE_DIR/$SESSION_ID.json"

if [ -z "$SESSION_ID" ] || [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

cc_notify_focus_context "$STATE_FILE"

exit 0
