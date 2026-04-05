#!/usr/bin/env bash
set -euo pipefail

# overstory-focus: Bring the correct terminal window to front for a saved session ID.
# Used as a generic focus helper for session-aware focus flows.

SESSION_ID="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/overstory-terminal-adapters.sh"

STATE_DIR="$HOME/.overstory/state"
STATE_FILE="$STATE_DIR/$SESSION_ID.json"

if [ -z "$SESSION_ID" ] || [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

overstory_focus_context "$STATE_FILE" "$SESSION_ID"

exit 0
