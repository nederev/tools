#!/bin/sh
set -u

APP_PATH="${APP_PATH:-$HOME/Applications/Sidecar Reconnector.app}"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.nederev.SidecarReconnector.plist"
LOG_PATH="$HOME/Library/Logs/SidecarReconnector.log"
APP_ID="com.nederev.SidecarReconnector"
failed=0

ok() {
  printf 'ok: %s\n' "$1"
}

warn() {
  printf 'warn: %s\n' "$1"
}

fail() {
  printf 'fail: %s\n' "$1"
  failed=1
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print $1" "$2" 2>/dev/null || true
}

fresh_log_seconds() {
  python3 - "$1" <<'PY'
import os
import sys
import time

path = sys.argv[1]
try:
    print(int(time.time() - os.path.getmtime(path)))
except OSError:
    print("")
PY
}

echo "Sidecar Reconnector health"
echo "app: $APP_PATH"

if [ -d "$APP_PATH" ]; then
  ok "installed app bundle exists"
else
  fail "installed app bundle missing"
fi

app_plist="$APP_PATH/Contents/Info.plist"
app_bin="$APP_PATH/Contents/MacOS/SidecarReconnector"
if [ -f "$app_plist" ]; then
  version=$(plist_value CFBundleShortVersionString "$app_plist")
  build=$(plist_value CFBundleVersion "$app_plist")
  title="Sidecar Reconnector v${version:-unknown}"
  ok "installed version $title build ${build:-unknown}"
else
  fail "installed app Info.plist missing"
fi

if [ -x "$app_bin" ]; then
  ok "installed app executable is present"
else
  fail "installed app executable missing or not executable"
fi

if pgrep -x SidecarReconnector >/dev/null 2>&1; then
  ok "app process is running"
else
  warn "app process is not running"
fi

if [ -f "$LAUNCH_AGENT" ]; then
  ok "LaunchAgent exists"
  agent_program=$(plist_value "ProgramArguments:0" "$LAUNCH_AGENT")
  if [ "$agent_program" = "$app_bin" ]; then
    ok "LaunchAgent points to installed app executable"
  else
    warn "LaunchAgent points to: ${agent_program:-unknown}"
  fi
else
  warn "LaunchAgent missing; Launch at login is disabled"
fi

if [ -f "$LOG_PATH" ]; then
  age=$(fresh_log_seconds "$LOG_PATH")
  if [ -n "$age" ]; then
    ok "log exists; last modified ${age}s ago"
    if [ "$age" -gt 86400 ]; then
      warn "log has not been updated in more than 24h"
    fi
  else
    warn "log exists but freshness could not be read"
  fi

  hotkey_line=$(grep -E "registered hotkey|hotkey registration failed" "$LOG_PATH" | tail -n 1 || true)
  if [ -z "$hotkey_line" ]; then
    warn "no hotkey registration line found in log"
  elif printf '%s\n' "$hotkey_line" | grep -q "hotkey registration failed"; then
    fail "latest hotkey registration log line is a failure"
  elif printf '%s\n' "$hotkey_line" | grep -q "registered hotkey"; then
    ok "latest hotkey registration log line is successful"
  else
    warn "no hotkey registration line found in log"
  fi
else
  warn "log file missing"
fi

if defaults read "$APP_ID" >/dev/null 2>&1; then
  target_name=$(defaults read "$APP_ID" targetName 2>/dev/null || true)
  if [ -n "$target_name" ]; then
    ok "target preference is configured"
  else
    warn "target preference is not configured"
  fi
else
  warn "app preferences not found"
fi

exit "$failed"
