#!/usr/bin/env bash
set -euo pipefail

# cc-notify uninstaller
# Removes hooks from Claude Code settings and cleans up installed files.

BOLD='\033[1m'
GREEN='\033[0;32m'
RESET='\033[0m'

info() { echo -e "${GREEN}[ok]${RESET} $1"; }

echo -e "${BOLD}cc-notify uninstaller${RESET}"
echo ""

# --- Remove hooks from settings.json ---
SETTINGS_FILE="$HOME/.claude/settings.json"

if [ -f "$SETTINGS_FILE" ]; then
  CURRENT=$(cat "$SETTINGS_FILE")
  if echo "$CURRENT" | jq -e '.hooks.Stop' &>/dev/null || echo "$CURRENT" | jq -e '.hooks.Notification' &>/dev/null; then
    # Remove only our hook entries (those that reference cc-notify.sh)
    CLEANED=$(echo "$CURRENT" | jq '
      if .hooks then
        .hooks |= with_entries(
          .value |= map(
            .hooks |= map(select(((.command? // "") | test("cc-notify")) | not))
          ) | map(select(.hooks | length > 0))
        ) | if .hooks | to_entries | map(select(.value | length > 0)) | length == 0 then del(.hooks) else . end
      else . end
    ')
    echo "$CLEANED" | jq '.' > "$SETTINGS_FILE"
    info "Hooks removed from $SETTINGS_FILE"
  else
    info "No cc-notify hooks found in settings"
  fi
fi

# --- Stop and remove LaunchAgent ---
PLIST_FILE="$HOME/Library/LaunchAgents/com.cc-notify.bar.plist"
if [ -f "$PLIST_FILE" ]; then
  launchctl bootout gui/$(id -u) "$PLIST_FILE" 2>/dev/null || true
  rm -f "$PLIST_FILE"
  info "LaunchAgent removed"
fi

# --- Kill menubar app if running ---
pkill -f CCNotifyBar 2>/dev/null || true

# --- Remove installed files ---
if [ -d "$HOME/.cc-notify" ]; then
  rm -rf "$HOME/.cc-notify"
  info "Removed $HOME/.cc-notify"
fi

echo ""
echo "cc-notify uninstalled."
