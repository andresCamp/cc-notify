#!/usr/bin/env bash

cc_notify_detect_terminal_kind() {
  case "${TERM_PROGRAM:-}" in
    ghostty|Ghostty)         echo "ghostty" ;;
    iTerm.app|iTerm2)        echo "iterm2" ;;
    Apple_Terminal)          echo "apple_terminal" ;;
    WezTerm)                 echo "wezterm" ;;
    kitty)                   echo "kitty" ;;
    Alacritty|alacritty)     echo "alacritty" ;;
    *)
      case "${TERM:-}" in
        xterm-ghostty)       echo "ghostty" ;;
        *)                   echo "unknown" ;;
      esac
      ;;
  esac
}

cc_notify_app_name_for_kind() {
  case "$1" in
    ghostty)          echo "Ghostty" ;;
    iterm2)           echo "iTerm2" ;;
    apple_terminal)   echo "Terminal" ;;
    wezterm)          echo "WezTerm" ;;
    kitty)            echo "kitty" ;;
    alacritty)        echo "Alacritty" ;;
    *)                echo "${TERM_PROGRAM:-}" ;;
  esac
}

# Capture terminal-specific identifiers at hook time.
# For Ghostty: briefly set a unique title marker, query AppleScript to
# find which terminal has that title, capture its stable ID. The marker
# is set while CC is blocked waiting for this hook, so there is no race.
cc_notify_capture_context() {
  local terminal_kind="$1"
  local cwd="$2"
  local tty="$3"
  local project="$4"
  local session_id="$5"

  CC_NOTIFY_FOCUS_CAPABILITY="fallback"
  CC_NOTIFY_GHOSTTY_TERMINAL_ID=""

  case "$terminal_kind" in
    ghostty)
      CC_NOTIFY_GHOSTTY_TERMINAL_ID=$(cc_notify_capture_ghostty_id_via_marker "$tty" "$session_id")
      if [ -n "$CC_NOTIFY_GHOSTTY_TERMINAL_ID" ]; then
        CC_NOTIFY_FOCUS_CAPABILITY="ghostty_terminal_id"
      fi
      ;;
  esac
}

# Set a temporary title marker on the TTY, query Ghostty for the terminal
# with that exact title, capture its stable ID.
cc_notify_capture_ghostty_id_via_marker() {
  local tty="$1"
  local session_id="$2"
  [ -n "$tty" ] && [ -w "$tty" ] || return 0

  local marker="cc-notify:${session_id}"

  # Set the marker title directly on the TTY device
  printf '\033]2;%s\007' "$marker" > "$tty" 2>/dev/null || return 0
  sleep 0.15

  # Find the terminal with that exact title
  osascript - "$marker" <<'APPLESCRIPT' 2>/dev/null || true
on run argv
  set marker to item 1 of argv
  tell application "Ghostty"
    repeat with t in terminals
      if (name of t) is marker then return id of t
    end repeat
  end tell
  return ""
end run
APPLESCRIPT
}

# Send a native Ghostty desktop notification via OSC 9.
cc_notify_send_ghostty_notification() {
  local tty="$1"
  local message="$2"
  [ -n "$tty" ] && [ -w "$tty" ] || return 1
  printf '\033]9;%s\007' "$message" > "$tty" 2>/dev/null
}

# Focus the correct terminal. Uses the captured Ghostty terminal ID
# to activate the window, select the tab, and focus the terminal.
cc_notify_focus_context() {
  local state_file="$1"
  local session_id="$2"
  local terminal_kind app tty ghostty_terminal_id

  terminal_kind=$(cc_notify_json_field "$state_file" '.terminal_kind // "unknown"')
  app=$(cc_notify_json_field "$state_file" '.app // ""')
  tty=$(cc_notify_json_field "$state_file" '.tty // ""')
  ghostty_terminal_id=$(cc_notify_json_field "$state_file" '.ghostty_terminal_id // ""')

  case "$terminal_kind" in
    ghostty)
      if cc_notify_focus_ghostty_terminal "$ghostty_terminal_id"; then
        return 0
      fi
      ;;
  esac

  cc_notify_focus_fallback "$app" "$tty"
}

# Focus a Ghostty terminal by its stable ID.
# Walks windows > tabs > terminals to find the containing tab,
# activates the window, selects the tab, and focuses the terminal.
cc_notify_focus_ghostty_terminal() {
  local terminal_id="$1"
  [ -n "$terminal_id" ] || return 1

  [ "$(osascript - "$terminal_id" <<'APPLESCRIPT' 2>/dev/null || true
on run argv
  set targetId to item 1 of argv
  tell application "Ghostty"
    activate
    repeat with w in windows
      repeat with tb in tabs of w
        repeat with t in terminals of tb
          if (id of t) is targetId then
            activate window w
            select tab tb
            focus t
            return "ok"
          end if
        end repeat
      end repeat
    end repeat
  end tell
  return ""
end run
APPLESCRIPT
  )" = "ok" ]
}

cc_notify_focus_fallback() {
  local app="$1"
  local tty="$2"

  if [ -n "$app" ] && [ "$app" != "unknown" ]; then
    open -a "$app" 2>/dev/null || true
  fi

  if [ -n "$tty" ] && [ -w "$tty" ]; then
    printf '\a' > "$tty" 2>/dev/null || true
  fi

  return 0
}

cc_notify_json_field() {
  local state_file="$1"
  local jq_expr="$2"
  jq -r "$jq_expr" "$state_file" 2>/dev/null || echo ""
}
