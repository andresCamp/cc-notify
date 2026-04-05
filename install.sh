#!/usr/bin/env bash
set -euo pipefail

# cc-notify installer
# Installs hook scripts and configures Claude Code settings.

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
RESET='\033[0m'

info()  { echo -e "${GREEN}[ok]${RESET} $1"; }
warn()  { echo -e "${YELLOW}[!]${RESET} $1"; }
fail()  { echo -e "${RED}[error]${RESET} $1"; exit 1; }

shell_quote() {
  printf '%q' "$1"
}

echo -e "${BOLD}cc-notify installer${RESET}"
echo "Sends macOS notifications when Claude Code needs your attention."
echo ""

# --- Check dependencies ---
command -v jq &>/dev/null || fail "jq is required. Install with: brew install jq"

if ! command -v terminal-notifier &>/dev/null; then
  warn "terminal-notifier not found. Click-to-focus requires it."
  echo "  Install with: brew install terminal-notifier"
  echo "  Without it, notifications still work but won't focus the right window on click."
  echo ""
  read -rp "Continue without terminal-notifier? [y/N] " choice
  case "$choice" in
    y|Y) ;;
    *) echo "Install terminal-notifier first, then re-run."; exit 0 ;;
  esac
fi

# --- Install scripts ---
INSTALL_DIR="$HOME/.cc-notify"
SCRIPTS_DIR="$INSTALL_DIR/scripts"
STATE_DIR="$INSTALL_DIR/state"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$SCRIPTS_DIR" "$STATE_DIR"

cp "$SOURCE_DIR/scripts/cc-notify.sh" "$SCRIPTS_DIR/cc-notify.sh"
cp "$SOURCE_DIR/scripts/cc-focus.sh"  "$SCRIPTS_DIR/cc-focus.sh"
cp "$SOURCE_DIR/scripts/cc-terminal-adapters.sh" "$SCRIPTS_DIR/cc-terminal-adapters.sh"
chmod +x "$SCRIPTS_DIR/cc-notify.sh" "$SCRIPTS_DIR/cc-focus.sh" "$SCRIPTS_DIR/cc-terminal-adapters.sh"

info "Scripts installed to $SCRIPTS_DIR"

# --- Build menubar app ---
APP_SRC="$SOURCE_DIR/app/CCNotifyBar.swift"
APP_BIN="$INSTALL_DIR/CCNotifyBar"

if [ -f "$APP_SRC" ]; then
  if command -v swiftc &>/dev/null; then
    echo "Compiling menubar app..."
    swiftc -O -o "$APP_BIN" "$APP_SRC" \
      -framework AppKit \
      -target arm64-apple-macosx13.0 2>&1 || {
        warn "Swift compilation failed. Menubar app will not be available."
        warn "Notifications still work without it."
        APP_BIN=""
      }
    if [ -n "$APP_BIN" ] && [ -f "$APP_BIN" ]; then
      info "Menubar app compiled"
    fi
  else
    warn "swiftc not found. Menubar app will not be available."
    warn "Install Xcode Command Line Tools: xcode-select --install"
    APP_BIN=""
  fi
else
  APP_BIN=""
fi

# --- Configure Claude Code hooks ---
SETTINGS_FILE="$HOME/.claude/settings.json"

if [ ! -f "$SETTINGS_FILE" ]; then
  fail "$SETTINGS_FILE not found. Is Claude Code installed?"
fi

# Build the hooks config
HOOK_CMD="bash $(shell_quote "$SCRIPTS_DIR/cc-notify.sh")"

HOOKS_JSON=$(cat <<EOF
{
  "Stop": [
    {
      "matcher": ".*",
      "hooks": [
        {
          "type": "command",
          "command": "$HOOK_CMD",
          "timeout": 10
        }
      ]
    }
  ],
  "Notification": [
    {
      "matcher": ".*",
      "hooks": [
        {
          "type": "command",
          "command": "$HOOK_CMD",
          "timeout": 10
        }
      ]
    }
  ]
}
EOF
)

# Merge hooks into existing settings (preserves all other keys)
CURRENT=$(cat "$SETTINGS_FILE")

# Check if hooks already exist
if echo "$CURRENT" | jq -e '.hooks' &>/dev/null; then
  warn "Existing hooks found in settings.json."
  echo "  Current hooks will be preserved. cc-notify hooks will be added."
  echo ""
  # Merge by event: keep existing handlers, replace prior cc-notify entries, append ours.
  MERGED=$(echo "$CURRENT" | jq --argjson new "$HOOKS_JSON" '
    def strip_cc_notify:
      map(
        .hooks |= map(select(((.command? // "") | test("cc-notify")) | not))
      )
      | map(select(.hooks | length > 0));

    .hooks = ((.hooks // {}) | reduce ($new | keys_unsorted[]) as $event (.;
      .[$event] = (((.[$event] // []) | strip_cc_notify) + $new[$event])
    ))
  ')
else
  MERGED=$(echo "$CURRENT" | jq --argjson new "$HOOKS_JSON" '.hooks = $new')
fi

echo "$MERGED" | jq '.' > "$SETTINGS_FILE"
info "Claude Code hooks configured in $SETTINGS_FILE"

# --- Done ---
echo ""
echo -e "${BOLD}Installed!${RESET} cc-notify is now active for all Claude Code sessions."
echo ""
echo "What happens now:"
echo "  - When Claude finishes a turn  -> macOS notification"
echo "  - When Claude needs approval   -> macOS notification (different sound)"
echo "  - Click the notification       -> uses a terminal-specific focus adapter"
echo "                                    when available, otherwise app+bell fallback"
echo ""
if ! command -v terminal-notifier &>/dev/null; then
  echo -e "${YELLOW}Reminder:${RESET} Install terminal-notifier for click-to-focus:"
  echo "  brew install terminal-notifier"
  echo ""
fi
# --- Install LaunchAgent for menubar app ---
if [ -n "$APP_BIN" ] && [ -f "$APP_BIN" ]; then
  PLIST_DIR="$HOME/Library/LaunchAgents"
  PLIST_FILE="$PLIST_DIR/com.cc-notify.bar.plist"
  mkdir -p "$PLIST_DIR"

  cat > "$PLIST_FILE" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.cc-notify.bar</string>
  <key>ProgramArguments</key>
  <array>
    <string>$APP_BIN</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
</dict>
</plist>
PLIST

  # Stop existing instance if running
  launchctl bootout gui/$(id -u) "$PLIST_FILE" 2>/dev/null || true
  launchctl bootstrap gui/$(id -u) "$PLIST_FILE" 2>/dev/null || true

  info "Menubar app installed and started (launches on login)"
  echo ""
  echo "  Look for the bell icon in your menubar."
fi

echo "To uninstall: bash $SOURCE_DIR/uninstall.sh"
