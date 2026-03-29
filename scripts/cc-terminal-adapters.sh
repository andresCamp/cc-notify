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

cc_notify_capture_context() {
  local terminal_kind="$1"
  local cwd="$2"

  CC_NOTIFY_FOCUS_CAPABILITY="fallback"
  CC_NOTIFY_GHOSTTY_TERMINAL_ID=""

  case "$terminal_kind" in
    ghostty)
      CC_NOTIFY_GHOSTTY_TERMINAL_ID=$(cc_notify_capture_ghostty_terminal_id "$cwd")
      if [ -n "$CC_NOTIFY_GHOSTTY_TERMINAL_ID" ]; then
        CC_NOTIFY_FOCUS_CAPABILITY="ghostty_terminal_id"
      elif [ -n "$cwd" ]; then
        CC_NOTIFY_FOCUS_CAPABILITY="ghostty_cwd"
      fi
      ;;
  esac
}

cc_notify_capture_ghostty_terminal_id() {
  local cwd="$1"
  [ -n "$cwd" ] || return 0

  osascript - "$cwd" <<'APPLESCRIPT' 2>/dev/null || true
on normalizePath(pathText)
  if pathText is missing value then return ""
  if pathText is "/" then return "/"
  if pathText ends with "/" then
    return text 1 thru -2 of pathText
  end if
  return pathText
end normalizePath

on run argv
  set targetCwd to normalizePath(item 1 of argv)
  tell application "Ghostty"
    set matches to {}
    repeat with t in every terminal
      set terminalCwd to normalizePath(working directory of t)
      if terminalCwd is targetCwd then set end of matches to t
    end repeat
    if (count of matches) is 1 then
      return id of item 1 of matches
    end if
  end tell
  return ""
end run
APPLESCRIPT
}

cc_notify_focus_context() {
  local state_file="$1"
  local terminal_kind app tty cwd ghostty_terminal_id

  terminal_kind=$(cc_notify_json_field "$state_file" '.terminal_kind // "unknown"')
  app=$(cc_notify_json_field "$state_file" '.app // ""')
  tty=$(cc_notify_json_field "$state_file" '.tty // ""')
  cwd=$(cc_notify_json_field "$state_file" '.cwd // ""')
  ghostty_terminal_id=$(cc_notify_json_field "$state_file" '.ghostty_terminal_id // ""')

  case "$terminal_kind" in
    ghostty)
      if cc_notify_focus_ghostty_terminal "$ghostty_terminal_id"; then
        return 0
      fi
      if cc_notify_focus_ghostty_cwd "$cwd"; then
        return 0
      fi
      ;;
  esac

  cc_notify_focus_fallback "$app" "$tty"
}

cc_notify_focus_ghostty_terminal() {
  local terminal_id="$1"
  [ -n "$terminal_id" ] || return 1

  [ "$(osascript - "$terminal_id" <<'APPLESCRIPT' 2>/dev/null || true
on run argv
  set targetId to item 1 of argv
  tell application "Ghostty"
    set matches to every terminal whose id is targetId
    if (count of matches) > 0 then
      focus item 1 of matches
      return "ok"
    end if
  end tell
  return ""
end run
APPLESCRIPT
)" = "ok" ]
}

cc_notify_focus_ghostty_cwd() {
  local cwd="$1"
  [ -n "$cwd" ] || return 1

  [ "$(osascript - "$cwd" <<'APPLESCRIPT' 2>/dev/null || true
on normalizePath(pathText)
  if pathText is missing value then return ""
  if pathText is "/" then return "/"
  if pathText ends with "/" then
    return text 1 thru -2 of pathText
  end if
  return pathText
end normalizePath

on run argv
  set targetCwd to normalizePath(item 1 of argv)
  tell application "Ghostty"
    set matches to {}
    repeat with t in every terminal
      set terminalCwd to normalizePath(working directory of t)
      if terminalCwd is targetCwd then set end of matches to t
    end repeat
    if (count of matches) is 1 then
      focus item 1 of matches
      return "ok"
    end if
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
